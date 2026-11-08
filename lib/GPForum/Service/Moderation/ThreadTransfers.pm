# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::ThreadTransfers;

use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use Mojo::URL;

our $VERSION = '0.001';
use Const::Fast;
const my $PICKER_PAGE  => 50;
const my $QUERY_LENGTH => 100;

__PACKAGE__->requires('schema');
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

sub history ( $self, $actor ) {
    return _history(
        $self->functions->row(
            'moderation_thread_transfers', { actor => $actor }
        )
    );
}

# The transfers page's reads on the worker's pooled asynchronous
# connections, not a forked child with a connection of its own each.
async sub history_p ( $self, $actor, $context = undef ) {
    return _history(
        await $self->functions->row_p(
            'moderation_thread_transfers', { actor => $actor }, $context
        )
    );
}

sub _history ($row) {
    return $row ? $row->{result} : { status => 'forbidden' };
}

sub picker ( $self, $input ) {
    my ( $refusal, @call ) = _picker_values($input);
    return $refusal // _picker_page( $self->functions->row(@call) );
}

async sub picker_p ( $self, $input, $context = undef ) {
    my ( $refusal, @call ) = _picker_values($input);
    return $refusal
      // _picker_page( await $self->functions->row_p( @call, $context ) );
}

# A refusal, or undef and the picker function's name and values.
sub _picker_values ($input) {
    my $source = _thread_id( $input->{source} );
    return { status => 'not_found' }
      if length( $input->{source} // q{} ) && !$source;
    my $after = $input->{after_position} // 0;
    return { status => 'invalid' }
      if $after !~ /\A[[:digit:]]{1,12}\z/msx
      || length( $input->{query} // q{} ) > $QUERY_LENGTH;
    return (
        undef,
        'moderation_transfer_picker',
        {
            actor          => $input->{actor},
            source_id      => $source,
            query          => $input->{query} // q{},
            after_position => $after
        }
    );
}

sub _picker_page ($row) {
    my $page = $row ? $row->{result} : { status => 'forbidden' };
    if ( @{ $page->{posts} // [] } > $PICKER_PAGE ) {
        pop @{ $page->{posts} };
        $page->{next_after} = $page->{posts}[-1]{position};
    }
    return $page;
}

sub change ( $self, $input ) {
    my ( $refusal, @call ) = _change_values($input);
    return $refusal // _transfer_result( $self->functions->row(@call) );
}

# The same move, merge or split on the worker's pooled asynchronous
# connections, not a forked child with a connection of its own.
async sub change_p ( $self, $input, $context = undef ) {
    return $self->change($input) if !$self->functions;
    my ( $refusal, @call ) = _change_values($input);
    return $refusal
      // _transfer_result( await $self->functions->row_p( @call, $context ) );
}

# A refusal, or undef and the transfer function's name and values.
sub _change_values ($input) {
    return { status => 'invalid' }
      if !GPForum::Infrastructure::Id->is_uuid( $input->{command} );
    my $source  = _thread_id( $input->{source} );
    my $target  = _thread_id( $input->{target} );
    my @numbers = split /[\s,]+/msx, $input->{post_numbers} // q{};
    my @invalid = grep { !/\A[1-9][[:digit:]]{0,8}\z/msx } @numbers;
    return { status => 'invalid' } if !$source || @invalid;
    return { status => 'invalid' }
      if ( $input->{operation} // q{} ) ne 'split' && !$target;
    return (
        undef,
        'moderation_thread_transfer',
        {
            actor        => $input->{actor},
            command      => $input->{command},
            source_id    => $source,
            target_id    => $target,
            operation    => $input->{operation},
            post_numbers => \@numbers,
            title        => $input->{title},
            reason       => $input->{reason},
        }
    );
}

sub undo ( $self, $input ) {
    my ( $refusal, @call ) = _undo_values($input);
    return $refusal // _transfer_result( $self->functions->row(@call) );
}

# The same undo on the worker's pooled asynchronous connections.
async sub undo_p ( $self, $input, $context = undef ) {
    return $self->undo($input) if !$self->functions;
    my ( $refusal, @call ) = _undo_values($input);
    return $refusal
      // _transfer_result( await $self->functions->row_p( @call, $context ) );
}

sub _undo_values ($input) {
    return { status => 'invalid' }
      if !GPForum::Infrastructure::Id->is_uuid( $input->{command} );
    return ( undef, 'moderation_thread_transfer_undo', $input );
}

sub _transfer_result ($row) {
    return $row ? $row->{result} : { status => 'invalid' };
}

sub redirect ( $self, $actor, $thread_id ) {
    return undef if !$self->functions;
    my $row = $self->functions->row( 'forum_thread_redirect',
        { actor => $actor, thread_id => $thread_id } );
    return $row ? $row->{target_id} : undef;
}

async sub redirect_p ( $self, $actor, $thread_id, $context = undef ) {
    return undef if !$self->functions;
    my $row = await $self->functions->row_p( 'forum_thread_redirect',
        { actor => $actor, thread_id => $thread_id }, $context );
    return $row ? $row->{target_id} : undef;
}

sub _thread_id ($value) {
    return undef  if !defined $value;
    return $value if GPForum::Infrastructure::Id->is_uuid($value);
    my $path = Mojo::URL->new($value)->path->to_string;
    my ($id) = $path =~ m{\A/t/([^/]+)(?:/[^/]+)?\z}msx;
    return GPForum::Infrastructure::Id->is_uuid($id) ? $id : undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Moderation::ThreadTransfers - Bounded, reversible thread organization.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $transfers->history($staff_id);

=head1 DESCRIPTION

PostgreSQL functions perform transfers, recounts, audit and outbox writes in
one transaction. Source and target must share category and visibility. Private
threads/posts and polls are refused. One command moves at most 1000 posts.

=head1 SUBROUTINES/METHODS

=head2 history

The hundred most recent transfers for authorized staff.

=head2 history_p

L</history> as a promise, with an optional query context last, read on the
worker's pooled asynchronous connections.

=head2 picker

Returns bounded, permission-checked title choices and a keyset page of selectable
replies. Destinations match the chosen source audience and category.

=head2 picker_p

L</picker> as a promise, with an optional query context last, read on the
worker's pooled asynchronous connections.

=head2 change

Move numbered posts, split them into a thread, or merge an entire thread.

=head2 change_p

L</change> as a promise, with an optional query context last, written on
the worker's pooled asynchronous connections.

=head2 undo

Restores original placement when subsequent work permits safe reversal.

=head2 undo_p

L</undo> as a promise, with an optional query context last, written on the
worker's pooled asynchronous connections.

=head2 redirect

A merged thread's readable destination, otherwise undef.

=head2 redirect_p

L</redirect> as a promise, with an optional query context last, read on the
worker's pooled asynchronous connections.

=head1 DIAGNOSTICS

A conflict leaves all content untouched; database failures propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>, L<Mojo::URL>.

=head1 INCOMPATIBILITIES

Requires migration 1028.

=head1 BUGS AND LIMITATIONS

Unrelated categories and private discussions require a separate audience-change workflow.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
