# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::DraftStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::Service::Forum::BodyLength;
use GPForum::X::Argument;

our $VERSION = '0.001';

const my $MAXIMUM_TITLE   => 300;
const my $MAXIMUM_COMMAND => 200;
const my $DEFAULT_PURGE   => 100;
const my $MAXIMUM_PURGE   => 1_000;
const my %KINDS           => ( thread => 1, reply => 1 );

__PACKAGE__->requires('schema');
has clock     => sub { return GPForum::Service::Clock->new; };
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema )
      // GPForum::X::Argument->throw(
        message => 'draft storage requires PostgreSQL functions' );
};

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(find list_for_user save remove purge_expired));

# The owner's draft by its id, undef when there is none or it expired.
async sub find_p ( $self, $owner, $id, $context = undef ) {
    return undef if !defined $id || !length $id;
    my $row = await $self->functions->row_p( 'forum_draft_find',
        $self->_find_values( $owner, $id ), $context );
    return $row ? $row->{draft} : undef;
}

sub _find_values ( $self, $owner, $id ) {
    return {
        owner_user_id => $owner,
        draft_id      => $id,
        now           => $self->clock->now_iso8601
    };
}

# The owner's drafts that have not expired.
async sub list_for_user_p ( $self, $owner, $context = undef ) {
    return [
        map { $_->{draft} }
          @{ await $self->functions->rows_p( $self->_list_values($owner),
                $context )
          }
    ];
}

sub _list_values ( $self, $owner ) {
    return ( 'forum_draft_list',
        { owner_user_id => $owner, now => $self->clock->now_iso8601 } );
}

# Saves a draft at the revision the owner last read.
async sub save_p ( $self, $input, $context = undef ) {
    my ( $values, $invalid ) = $self->_save_values($input);
    return $invalid if $invalid;
    return _answer(
        await $self->functions->row_p( 'forum_draft_save', $values, $context )
    );
}

sub _save_values ( $self, $input ) {
    my %values = map { $_ => $input->{$_} }
      qw(owner_user_id draft_id draft_revision kind category_id thread_id
      title body_source visibility command_id);
    $values{title}       //= q{};
    $values{body_source} //= q{};
    for my $field (qw(category_id thread_id visibility)) {
        if ( defined $values{$field} && $values{$field} eq q{} ) {
            $values{$field} = undef;
        }
    }
    my $errors = _validation_errors( \%values );
    return ( undef, { ok => 0, status => 'invalid', errors => $errors } )
      if %{$errors};
    $values{now} = $self->clock->now_iso8601;
    return ( \%values, undef );
}

sub _validation_errors ($values) {
    my %errors;
    for my $field (qw(owner_user_id draft_id)) {
        if ( !GPForum::Infrastructure::Id->is_uuid_spelling( $values->{$field} )
          )
        {
            $errors{$field} = 'invalid identifier';
        }
    }
    if ( !defined $values->{draft_revision}
        || $values->{draft_revision} !~ /\A [[:digit:]]+ \z/amsx )
    {
        $errors{draft_revision} = 'invalid draft revision';
    }
    if ( !exists $KINDS{ $values->{kind} // q{} } ) {
        $errors{kind} = 'invalid draft kind';
    }
    if ( length $values->{title} > $MAXIMUM_TITLE ) {
        $errors{title} = 'draft title is too long';
    }
    if ( GPForum::Service::Forum::BodyLength->too_long( $values->{body_source} )
      )
    {
        $errors{body_source} =
          GPForum::Service::Forum::BodyLength->too_long_error;
    }
    if (   !defined $values->{command_id}
        || !length $values->{command_id}
        || length $values->{command_id} > $MAXIMUM_COMMAND )
    {
        $errors{command_id} = 'command_id is required';
    }
    return \%errors;
}

# Removes a draft at the revision the owner last read.
async sub remove_p ( $self, $input, $context = undef ) {
    return _answer(
        await $self->functions->row_p(
            'forum_draft_remove', $self->_remove_values($input), $context
        )
    );
}

sub _remove_values ( $self, $input ) {
    return {
        map( { $_ => $input->{$_} } qw(owner_user_id draft_id draft_revision) ),
        now => $self->clock->now_iso8601
    };
}

# Deletes expired drafts, at most $input->{limit} (100 by default, 1000 at
# most).
async sub purge_expired_p ( $self, $input = undef, $context = undef ) {
    my $limit = $input ? $input->{limit} : undef;
    if ( !defined $limit || $limit !~ /\A [[:digit:]]+ \z/amsx || $limit < 1 ) {
        $limit = $DEFAULT_PURGE;
    }
    if ( $limit > $MAXIMUM_PURGE ) {
        $limit = $MAXIMUM_PURGE;
    }
    my $row = await $self->functions->row_p( 'forum_draft_purge',
        { now => $self->clock->now_iso8601, row_limit => $limit }, $context );
    return { ok => 1, deleted => $row->{deleted} // 0 };
}

sub _answer ($row) {
    return { ok => 0, status => 'not_found' } if !$row;
    my $status = $row->{status} // 'failed';
    return {
        ok     => $status eq 'ok' ? 1 : 0,
        status => $status,
        draft  => $row->{draft},
        error  => $row->{error}
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::DraftStore - Owner-private draft calls to PostgreSQL.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Forum::DraftStore->new(schema => $schema);
    my $draft = $store->find($owner_user_id, $draft_id);

=head1 DESCRIPTION

Drafts expire thirty days after their last save. Saves and removals require
the current C<draft_revision>; revision zero creates a new draft. PostgreSQL
owns authorization, limits, concurrent updates and publish cleanup. This
service has no ORM fallback. C<find> does not query for an absent identifier.

=head1 SUBROUTINES/METHODS

=head2 find_p

Takes the authenticated owner identifier and a draft identifier. Answers
the owner's unexpired draft, or C<undef>. An absent identifier sends no
call.

=head2 list_for_user_p

Takes the owner identifier. Answers at most 100 unexpired drafts, newest
first, as metadata without body source.

=head2 save_p

Takes owner, draft, context and source fields with C<draft_revision> and the
publish C<command_id>. Revision zero creates a draft; changes require its
current revision. Answers C<ok>, C<status>, field errors on invalid input,
and the acknowledged draft on success. Retries of an unchanged save are
idempotent. The acknowledged draft carries the publish command identifier.

=head2 remove_p

Takes C<owner_user_id>, C<draft_id> and C<draft_revision>. Removes that
owner's draft only if the revision agrees. Answers C<ok> and C<status>.

=head2 purge_expired_p

Takes an optional input hash with C<limit>. Deletes expired drafts through
a bounded routine, answering C<ok> and C<deleted>. The default batch is
100 drafts and the maximum is 1,000.

=head2 find, list_for_user, save, remove, purge_expired

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise. Every C<_p> method
takes an optional query context last.

=head1 DIAGNOSTICS

Invalid input returns field errors. A stale revision returns C<conflict>.
Database failures propagate to the controller's normal unavailable response.

=head1 CONFIGURATION AND ENVIRONMENT

Requires a PostgreSQL schema. The clock and function adapter are injectable
for tests. Retention batches default to 100 and are bounded at 1,000 rows.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>, L<GPForum::Service::Clock>,
L<GPForum::Service::Forum::BodyLength>.

=head1 INCOMPATIBILITIES

No in-memory ORM fallback is provided.

=head1 BUGS AND LIMITATIONS

The HTTP boundary supplies the authenticated owner identifier. Drafts have
no attachment lifecycle and emit no public events, search or notification rows.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause license.

=cut
