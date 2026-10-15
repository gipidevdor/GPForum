# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::LikeStore;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::X;

our $VERSION = '0.001';

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };

__PACKAGE__->requires(qw(schema));

has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

# The row a like or an unlike is written from: the post, the member, the
# time, and the ids of the event the write records, drawn here so the
# command function records what the Perl path would.
sub new_like_row ( $self, $input ) {
    return {
        correlation_id => $self->id_service->uuid,
        created_at     => $self->clock->now_iso8601,
        event_id       => $self->id_service->uuid,
        outbox_id      => $self->id_service->uuid,
        post_id        => $input->{post_id},
        user_id        => $input->{user_id},
    };
}

sub like ( $self, $input ) {
    return $self->_written( 'community_like_post', $input );
}

sub unlike ( $self, $input ) {
    return $self->_written( 'community_unlike_post', $input );
}

# The likes on these posts, by post id: how many, and whether the viewer
# gave one. A post nobody liked is absent.
sub summary_for_posts ( $self, $post_ids, $viewer_user_id = undef ) {
    return {} if !@{$post_ids};
    my $rows = $self->_functions->rows(
        'community_post_likes',
        {
            post_ids       => $post_ids,
            viewer_user_id => _nullable($viewer_user_id),
        }
    );
    return {
        map {
            $_->{post_id} => {
                like_count => $_->{like_count},
                liked      => $_->{liked} ? 1 : 0,
            }
        } @{$rows}
    };
}

sub _written ( $self, $name, $input ) {
    my $row =
      $self->_functions->row( $name, { row => $self->new_like_row($input) } );
    return $row ? $row->{result} : undef;
}

# Likes exist only as api.* functions (ADR 0126): there is no Perl path to
# fall back to without them.
sub _functions ($self) {
    return $self->functions // GPForum::X::Argument->throw(
        message => 'likes need the SQL function layer' );
}

sub _nullable ($value) {
    return defined $value && length $value ? $value : undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Community::LikeStore - A member's likes on posts.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $likes = GPForum::Service::Community::LikeStore->new(
        schema => $schema,
    );
    $likes->like( { post_id => $post_id, user_id => $user_id } );
    $likes->summary_for_posts( \@post_ids, $viewer_user_id );

=head1 DESCRIPTION

The write side and the page read of post likes (ADR 0129), every statement
an C<api.community_*> function (ADR 0126). A like is one row per member and
post; the count a page shows is counted from the rows. The author of a post
cannot like it, and a post that is not visible takes no like; a like may
always be taken back. Each like and unlike records an event (C<post.liked>,
C<post.unliked>) with its outbox message.

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>). C<schema> is required; C<clock> and
C<id_service> default to the real ones.

=head2 new_like_row

The row a like or an unlike is written from: C<post_id>, C<user_id>, the
time, and the event's ids (C<event_id>, C<outbox_id>, C<correlation_id>).

=head2 like

Takes C<post_id> and C<user_id>. Returns the function's answer: C<ok> with
C<like_count>, C<liked>, C<post_id>, C<thread_id>, C<user_id> and
C<changed> (0 for a like already given), or C<< ok => 0 >> with C<error>
and C<status> (C<not_found>, or C<invalid> for the author's own post).

=head2 unlike

As L</like>, taking the like back; C<changed> is 0 when none was given.

=head2 summary_for_posts

Takes post ids and the viewer's user id (or nothing). Returns, by post id,
C<like_count> and C<liked>; posts nobody liked are absent.

=head1 DIAGNOSTICS

Throws L<GPForum::X::Argument> when the schema has no SQL function layer.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
