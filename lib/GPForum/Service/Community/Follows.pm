# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Service::Community::Follows;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;
use GPForum::Service::Forum::PageWindow;
use GPForum::Service::Forum::Viewer;
use GPForum::X::Unavailable;
our $VERSION = '0.001';
__PACKAGE__->requires('schema');
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(change following followed_users feed));

# A follow or unfollow, through an authorized, idempotent command.
async sub change_p ( $self, $input, $context = undef ) {
    return { status => 'invalid' }
      if !GPForum::Infrastructure::Id->is_uuid( $input->{command} );
    my $row = await $self->_functions->row_p( 'community_follow_change',
        $input, $context );

    return $row ? $row->{result} : { status => 'forbidden' };
}

# Whether the actor follows the target: 1 or 0, undef when there is no
# answer. Only the actor's own state, never a public follower graph.
async sub following_p ( $self, $actor, $target, $context = undef ) {
    my $row = await $self->_functions->row_p( 'community_follow_state',
        { actor => $actor, target => $target }, $context );

    return $row ? ( $row->{following} ? 1 : 0 ) : undef;
}

# The members the actor follows, at most 500.
async sub followed_users_p ( $self, $actor, $context = undef ) {
    return await $self->_functions->rows_p( 'community_followed_users',
        { actor => $actor }, $context );
}

# A page of what the followed members wrote that the viewer may read.
async sub feed_p ( $self, $actor, $viewer, $input, $context = undef ) {
    my ( $window, $plan ) = _feed_plan($input);
    return _feed_page(
        $window, $plan,
        await $self->_functions->rows_p(
            'community_follow_feed', _feed_values( $actor, $viewer, $plan ),
            $context
        )
    );
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'follows need the PostgreSQL function layer' );
}

sub _feed_plan ($input) {
    my $window = GPForum::Service::Forum::PageWindow->new;
    return (
        $window,
        $window->plan(
            {
                after => $input->{after},
                limit => $input->{limit},
                sort  => 'timestamp'
            }
        )
    );
}

sub _feed_values ( $actor, $viewer, $plan ) {
    my $access = GPForum::Service::Forum::Viewer->from($viewer);
    return {
        actor        => $actor,
        member       => $access->member,
        global_read  => $access->global_read,
        category_ids => $access->category_ids,
        space_ids    => $access->space_ids,
        after_at     => $plan->{after} ? $plan->{after}{sort_value} : undef,
        after_id     => $plan->{after} ? $plan->{after}{id}         : undef,
        row_limit    => $plan->{fetch_rows},
    };
}

sub _feed_page ( $window, $plan, $rows ) {
    my $page = $window->page(
        [ map { GPForum::Infrastructure::ResultRow->from($_) } @{$rows} ],
        $plan->{limit}, [qw(created_at item_id)] );
    $page->{items} = [ map { +{ %{$_} } } @{ $page->{items} } ];
    return $page;
}
1;
__END__

=head1 NAME

GPForum::Service::Community::Follows - Private user follows and a live contribution feed.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $follows->change({actor=>$id,command=>$command,username=>'ada',operation=>'follow'});

=head1 DESCRIPTION

Uses existing subscriptions with a user target. A member follows up to 500
people. Their following feed reads current visible contributions, with keyset
pagination and block/ignore checks before the limit, without notification fanout.

=head1 SUBROUTINES/METHODS

=head2 change_p

Follows or removes a followed user through an authorized, idempotent
command; a command that is not a uuid is invalid.

=head2 following_p

The actor's own follow state for one target: 1, 0, or undef without an
answer. Never a public follower graph.

=head2 followed_users_p

The actor's followed members, at most 500.

=head2 feed_p

A bounded page of the followed members' contributions the viewer may read.

=head2 change, following, followed_users, feed

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise. Every C<_p> method
takes an optional query context last.

=head1 DIAGNOSTICS

Writes return a status; database failures propagate. Without the
PostgreSQL function layer every call raises L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction> and the forum viewer and page window.

=head1 INCOMPATIBILITIES

Requires migration 1061.

=head1 BUGS AND LIMITATIONS

Follows are unidirectional and private. They do not generate email or inbox
notifications. Unfollowing immediately removes the member from this live feed.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
