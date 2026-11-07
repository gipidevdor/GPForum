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
our $VERSION = '0.001';
__PACKAGE__->requires('schema');
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

sub change ( $self, $input ) {
    return { status => 'invalid' }
      if !GPForum::Infrastructure::Id->is_uuid( $input->{command} );
    my $row = $self->functions->row( 'community_follow_change', $input );
    return $row ? $row->{result} : { status => 'forbidden' };
}

sub following ( $self, $actor, $target ) {
    return undef if !$self->functions;
    return _following(
        $self->functions->row(
            'community_follow_state', { actor => $actor, target => $target }
        )
    );
}

# The profile page's follow state, on the worker's pooled asynchronous
# connections instead of a forked child.
async sub following_p ( $self, $actor, $target, $context = undef ) {
    return undef if !$self->functions;
    return _following(
        await $self->functions->row_p(
            'community_follow_state', { actor => $actor, target => $target },
            $context
        )
    );
}

sub _following ($row) {
    return $row ? ( $row->{following} ? 1 : 0 ) : undef;
}

sub followed_users ( $self, $actor ) {
    return $self->functions->rows( 'community_followed_users',
        { actor => $actor } );
}

# The /following reads as the web worker runs them, on its pooled
# asynchronous connections instead of a forked child each.
async sub followed_users_p ( $self, $actor, $context = undef ) {
    return (
        await $self->functions->rows_p(
            'community_followed_users', { actor => $actor }, $context
        )
    );
}

sub feed ( $self, $actor, $viewer, $input ) {
    my ( $window, $plan ) = _feed_plan($input);
    return _feed_page(
        $window, $plan,
        $self->functions->rows(
            'community_follow_feed', _feed_values( $actor, $viewer, $plan )
        )
    );
}

async sub feed_p ( $self, $actor, $viewer, $input, $context = undef ) {
    my ( $window, $plan ) = _feed_plan($input);
    return _feed_page(
        $window, $plan,
        await $self->functions->rows_p(
            'community_follow_feed', _feed_values( $actor, $viewer, $plan ),
            $context
        )
    );
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

=head2 change

Follows or removes a followed user through an authorized, idempotent command.

=head2 following

Reads the actor's own follow state for one target; never a public follower graph.

=head2 following_p

L</following> as a promise, with an optional query context last, read on
the worker's pooled asynchronous connections.

=head2 followed_users

Lists the actor's followed members, at most 500.

=head2 feed

Returns a bounded page of the followed members' currently readable contributions.

=head2 followed_users_p

L</followed_users> as a promise, with an optional query context last, read
on the worker's pooled asynchronous connections.

=head2 feed_p

L</feed> as a promise, read the same way.

=head1 DIAGNOSTICS

Writes return a status; database failures propagate.

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
