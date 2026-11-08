# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::RelationStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

# ADR 0130: the most members one list holds (api.community_relation_set_v1
# refuses the next), and the kinds of relation.
const my $MAXIMUM_RELATIONS => 500;
const my $MAXIMUM_USERNAME  => 200;
const my %KINDS             => ( ignore => 1, block => 1 );

# ADR 0130: the notifications a relation silences. A member's reply or
# mention leaves the list owner's inbox, and so does the notice of their
# direct message (ADR 0139); any other type -- a staff notice -- is never
# silenced, whoever sent it.
const my %MEMBER_NOTIFICATIONS =>
  ( reply => 1, mention => 1, direct_message => 1 );

has clock => sub { return GPForum::Service::Clock->new; };
__PACKAGE__->requires(qw(schema));

# A schema without the function layer -- the in-memory doubles -- holds no
# relations: its reads are empty and its writes unavailable.
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

sub maximum_relations ($self) { return $MAXIMUM_RELATIONS; }

# Lists, or changes the kind of, the member called $username on the owner's
# list. Answers ok (and changed, when it was not already so) or a refusal:
# invalid, self, not_found, limit or forbidden (the owner cannot act).
sub set_relation ( $self, $input ) {
    return _refused('invalid') if !_valid_set($input);

    return _set_answer(
        $self->_functions->row(
            'community_relation_set', $self->_set_values($input)
        )
    );
}

# set_relation on the worker's pooled asynchronous connections.
async sub set_relation_p ( $self, $input, $context = undef ) {
    return $self->set_relation($input) if !$self->functions;
    return _refused('invalid')         if !_valid_set($input);

    return _set_answer(
        await $self->functions->row_p(
            'community_relation_set', $self->_set_values($input), $context
        )
    );
}

sub _valid_set ($input) {
    return exists $KINDS{ $input->{kind} // q{} }
      && _valid_owner_and_name($input);
}

sub _valid_owner_and_name ($input) {
    my $username = $input->{username} // q{};
    return
         length $username
      && length $username <= $MAXIMUM_USERNAME
      && GPForum::Infrastructure::Id->is_uuid_spelling(
        $input->{owner_user_id} ) ? 1 : 0;
}

sub _set_values ( $self, $input ) {
    return {
        owner_user_id => $input->{owner_user_id},
        username      => $input->{username},
        kind          => $input->{kind},
        now           => $self->clock->now_iso8601,
    };
}

sub _set_answer ($row) {
    $row ||= { status => 'forbidden' };
    my $status = $row->{status} // 'forbidden';
    return _refused($status) if $status ne 'ok' && $status ne 'unchanged';

    return {
        ok       => 1,
        status   => $status,
        changed  => $status eq 'ok' ? 1 : 0,
        relation => {
            other_user_id => $row->{other_user_id},
            username      => $row->{username},
            kind          => $row->{kind},
        },
    };
}

# Takes the member called $username off the owner's list; removing one not
# listed is no error (removed is 0).
sub remove_relation ( $self, $input ) {
    return _refused('invalid') if !_valid_owner_and_name($input);

    return _remove_answer(
        $self->_functions->row(
            'community_relation_remove', _remove_values($input)
        )
    );
}

# remove_relation on the worker's pooled asynchronous connections.
async sub remove_relation_p ( $self, $input, $context = undef ) {
    return $self->remove_relation($input) if !$self->functions;
    return _refused('invalid')            if !_valid_owner_and_name($input);

    return _remove_answer(
        await $self->functions->row_p(
            'community_relation_remove', _remove_values($input), $context
        )
    );
}

sub _remove_values ($input) {
    return {
        owner_user_id => $input->{owner_user_id},
        username      => $input->{username},
    };
}

sub _remove_answer ($row) {
    return { ok => 1, status => 'ok', removed => 0 + ( $row->{removed} // 0 ) };
}

sub list_for_user ( $self, $owner_user_id ) {
    return [] if !$self->functions || !defined $owner_user_id;

    return $self->functions->rows( 'community_relation_list',
        { owner_user_id => $owner_user_id } );
}

# The settings page's list on the worker's pooled asynchronous connections.
async sub list_for_user_p ( $self, $owner_user_id, $context = undef ) {
    return $self->list_for_user($owner_user_id)
      if !$self->functions || !defined $owner_user_id;

    return await $self->functions->rows_p( 'community_relation_list',
        { owner_user_id => $owner_user_id }, $context );
}

# The kind of relation the owner holds against the other member, or undef.
sub relation_between ( $self, $owner_user_id, $other_user_id ) {
    return undef
      if !$self->functions
      || !defined $owner_user_id
      || !defined $other_user_id
      || $owner_user_id eq $other_user_id;

    my $row = $self->functions->row( 'community_relation_between',
        { owner_user_id => $owner_user_id, other_user_id => $other_user_id } );

    return $row ? $row->{kind} : undef;
}

# The profile page's relation on the worker's pooled asynchronous
# connections. The cases relation_between answers without reading are
# answered by it.
async sub relation_between_p ( $self, $owner_user_id, $other_user_id,
    $context = undef )
{
    return $self->relation_between( $owner_user_id, $other_user_id )
      if !$self->functions
      || !defined $owner_user_id
      || !defined $other_user_id
      || $owner_user_id eq $other_user_id;

    my $row =
      await $self->functions->row_p( 'community_relation_between',
        { owner_user_id => $owner_user_id, other_user_id => $other_user_id },
        $context );

    return $row ? $row->{kind} : undef;
}

sub blocks ( $self, $owner_user_id, $other_user_id ) {
    my $kind = $self->relation_between( $owner_user_id, $other_user_id );

    return defined $kind && $kind eq 'block' ? 1 : 0;
}

# The block on the worker's pooled asynchronous connections, or on the
# call layer of the transaction the store was joined to.
async sub blocks_p ( $self, $owner_user_id, $other_user_id, $context = undef ) {
    my $kind =
      await $self->relation_between_p( $owner_user_id, $other_user_id,
        $context );

    return defined $kind && $kind eq 'block' ? 1 : 0;
}

# True when a notification of this type, from this actor, is silenced for
# the recipient: a reply, mention or direct message by a member they ignore
# or block.
sub silences ( $self, $recipient_user_id, $notification_type, $actor_id ) {
    return 0 if !$self->silenceable($notification_type);

    return defined $self->relation_between( $recipient_user_id, $actor_id )
      ? 1
      : 0;
}

async sub silences_p ( $self, $recipient_user_id, $notification_type,
    $actor_id, $context = undef )
{
    return 0 if !$self->silenceable($notification_type);

    return
      defined(
        await $self->relation_between_p( $recipient_user_id, $actor_id,
            $context ) ) ? 1 : 0;
}

# Whether relations silence notifications of this kind at all: replies,
# mentions and direct messages, the kinds one member sends another. The
# fan-out asks this once and reads each recipient's relation with the rest.
sub silenceable ( $self, $notification_type ) {
    return exists $MEMBER_NOTIFICATIONS{ $notification_type // q{} } ? 1 : 0;
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'member relations need the PostgreSQL function layer' );
}

sub _refused ($status) {
    return { ok => 0, status => $status };
}

1;

__END__

=head1 NAME

GPForum::Service::Community::RelationStore - The members a member ignores or blocks.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $relations = GPForum::Service::Community::RelationStore->new(
        schema => $schema );
    $relations->set_relation(
        { owner_user_id => $id, username => 'ada', kind => 'ignore' } );
    my $kind = $relations->relation_between( $id, $other_id );

=head1 DESCRIPTION

ADR 0130. A member's private list of the members they ignore or block, at
most 500. Ignoring collapses the other member's posts in threads and keeps
their replies and mentions out of the owner's inbox and mentions page;
blocking does the same and also refuses their mentions of the owner. Every
read and write is a function of schema C<api> (ADR 0126); refusals are
result values (ADR 0118).

=head1 SUBROUTINES/METHODS

=head2 set_relation

Lists a member by username with kind C<ignore> or C<block>, or changes the
kind of one already listed. Answers C<ok> with C<status> C<ok> or
C<unchanged>, or C<ok> 0 with C<status> C<invalid>, C<self>, C<not_found>,
C<limit> or C<forbidden>.

=head2 set_relation_p

The same change and answer as L</set_relation>, on the worker's pooled
asynchronous PostgreSQL connections; a double without the function layer
is answered by L</set_relation>.

=head2 remove_relation

Takes a member off the list by username; answers how many rows went.

=head2 remove_relation_p

The same removal and answer as L</remove_relation>, on the worker's pooled
asynchronous PostgreSQL connections.

=head2 list_for_user

The owner's list, newest change first, with each member's username and
display name.

=head2 list_for_user_p

L</list_for_user> as a promise, with an optional query context last, read
on the worker's pooled asynchronous connections. Without SQL functions it
answers the blocking read.

=head2 relation_between

The kind the owner holds against another member, or undef.

=head2 relation_between_p

L</relation_between> as a promise, with an optional query context last,
read on the worker's pooled asynchronous connections.

=head2 blocks

True when the owner blocks the other member.

=head2 blocks_p

L</blocks> as a promise, with an optional query context last, read on the
worker's pooled asynchronous connections, or on a transaction's call layer
when the store was built with that layer as its C<functions>.

=head2 silences

True when a notification of this type from this actor is silenced for the
recipient: only replies, mentions and direct messages are.

=head2 silences_p

L</silences> as a promise, with an optional query context last, read as
L</blocks_p> reads.

=head2 silenceable

True when relations silence notifications of this type at all: replies,
mentions and direct messages.

=head2 maximum_relations

The list's size bound, 500.

=head1 DIAGNOSTICS

A write on a schema without the function layer throws
L<GPForum::X::Unavailable>; database errors propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A block refuses direct messages (ADR 0139); that is the message store's.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
