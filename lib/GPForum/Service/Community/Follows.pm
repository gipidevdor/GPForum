# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Service::Community::Follows;
use Mojo::Base 'GPForum::Base', -signatures;
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
    my $row = $self->functions->row( 'community_follow_state',
        { actor => $actor, target => $target } );
    return $row ? ( $row->{following} ? 1 : 0 ) : undef;
}

sub followed_users ( $self, $actor ) {
    return $self->functions->rows( 'community_followed_users',
        { actor => $actor } );
}

sub feed ( $self, $actor, $viewer, $input ) {
    my $access = GPForum::Service::Forum::Viewer->from($viewer);
    my $window = GPForum::Service::Forum::PageWindow->new;
    my $plan   = $window->plan(
        {
            after => $input->{after},
            limit => $input->{limit},
            sort  => 'timestamp'
        }
    );
    my $rows = $self->functions->rows(
        'community_follow_feed',
        {
            actor        => $actor,
            member       => $access->member,
            global_read  => $access->global_read,
            category_ids => $access->category_ids,
            space_ids    => $access->space_ids,
            after_at     => $plan->{after} ? $plan->{after}{sort_value} : undef,
            after_id     => $plan->{after} ? $plan->{after}{id}         : undef,
            row_limit    => $plan->{fetch_rows},
        }
    );
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

=head2 followed_users

Lists the actor's followed members, at most 500.

=head2 feed

Returns a bounded page of the followed members' currently readable contributions.

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
