# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::ReviewReader;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::Service::Forum::PageWindow;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $DEFAULT_LIMIT             => 25;
const my @ACTION_CURSOR_COLUMNS     => qw(created_at moderation_action_id);
const my @SUSPENSION_CURSOR_COLUMNS => qw(valid_from suspension_id);
const my %INACTIVE_MODES            => map { $_ => 1 } qw(:0 all: all:0);

has clock       => sub { return GPForum::Service::Clock->new; };
has page_window => sub { return GPForum::Service::Forum::PageWindow->new; };
__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each read is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(list_actions list_suspensions));

async sub list_actions_p ( $self, $options, $context = undef ) {
    $options //= {};
    my $page  = $self->_plan($options);
    my $after = $page->{after} || {};
    my $rows  = await $self->_functions->rows_p(
        'moderation_action_list',
        {
            target_type => $options->{target_type} || undef,
            target_id   => $options->{target_id}   || undef,
            after_at    => $after->{sort_value},
            after_id    => $after->{id},
            row_limit   => $page->{fetch_rows} || $DEFAULT_LIMIT
        },
        $context
    );

    return $self->_page( $page, $rows, \@ACTION_CURSOR_COLUMNS );
}

async sub list_suspensions_p ( $self, $options, $context = undef ) {
    $options //= {};
    my $page  = $self->_plan($options);
    my $after = $page->{after} || {};
    my $rows  = await $self->_functions->rows_p(
        'moderation_suspension_list',
        {
            user_id     => $options->{user_id} || undef,
            active_only => _active_only($options),
            now         => $self->clock->now_iso8601,
            after_at    => $after->{sort_value},
            after_id    => $after->{id},
            row_limit   => $page->{fetch_rows} || $DEFAULT_LIMIT
        },
        $context
    );

    return $self->_page( $page, $rows, \@SUSPENSION_CURSOR_COLUMNS );
}

sub _plan ( $self, $options ) {
    return $self->page_window->plan( { %{$options}, sort => 'timestamp' } );
}

sub _page ( $self, $page, $rows, $cursor ) {
    return $self->page_window->page(
        [ map { GPForum::Infrastructure::ResultRow->from($_) } @{$rows} ],
        $page->{limit}, $cursor );
}

# Active suspensions only, unless the status is all or active is 0.
sub _active_only ($options) {
    my $mode = join q{:}, map { $options->{$_} // q{} } qw(status active);

    return exists $INACTIVE_MODES{$mode} ? 0 : 1;
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw( message =>
          'the moderation review needs the PostgreSQL function layer' );
}

1;

__END__

=head1 NAME

GPForum::Service::Moderation::ReviewReader - Keyset-paged moderation action history and suspension list.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $reader =
      GPForum::Service::Moderation::ReviewReader->new( schema => $schema );

    my $actions = $reader->list_actions(
        { limit => 25, target_id => $post_id, target_type => 'post' } );
    my $older = $reader->list_actions( { after => $actions->{next_cursor} } );

    my $suspensions =
      $reader->list_suspensions( { status => 'all', user_id => $user_id } );

=head1 DESCRIPTION

The read side of the moderation review screens. Both lists are newest first
and keyset paged through L<GPForum::Service::Forum::PageWindow>, so a deep
page costs the same as the first: actions on C<created_at> and
C<moderation_action_id>, suspensions on C<valid_from> and C<suspension_id>.
By default the suspension list holds only active suspensions: not revoked,
with no C<valid_to> or one not yet past.

=head1 SUBROUTINES/METHODS

=head2 list_actions

Takes an optional hash reference with C<limit>, C<after> (a cursor from a
previous page), and C<target_type> and C<target_id> filters, ignored when
empty. Returns C<< { items, has_next, next_cursor } >>, the items being
C<moderation_actions> rows with the action's id, actor, type, target,
reason, metadata, creation time and reversal columns.

=head2 list_suspensions

Takes an optional hash reference with C<limit>, C<after>, C<user_id>,
C<status> and C<active>. Lists active suspensions only, unless C<status> is
C<all> and C<active> is absent or 0, or C<active> is 0 and C<status> is
absent. Returns the page hash as C<list_actions> does, the items being
C<suspensions> rows.

=head2 list_actions_p

L</list_actions> as a promise, with an optional query context last, read on
the worker's pooled asynchronous connections. It is the read's one body: the
blocking method runs it on the blocking call layer (ADR 0177).

=head2 list_suspensions_p

L</list_suspensions> as a promise, as L</list_actions_p> is.

=head1 DIAGNOSTICS

Without the PostgreSQL function layer every read raises
L<GPForum::X::Unavailable>; database errors propagate. A cursor that cannot
be decoded gives the first page.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Service::Forum::PageWindow>, L<GPForum::Service::Clock>.

Extends L<GPForum::Base>: built without C<schema> it throws
L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
