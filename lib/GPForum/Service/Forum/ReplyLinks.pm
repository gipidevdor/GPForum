# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::ReplyLinks;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::X;

our $VERSION = '0.001';

__PACKAGE__->requires(qw(schema));

has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

# Links a reply to the post it answers. The function holds the link only
# when both posts are in the same thread and the one answered is there to
# be read; anything else, a target that is not a uuid included, links
# nothing and says so.
sub link_reply ( $self, $post_id, $reply_to_post_id ) {
    return 0
      if !GPForum::Infrastructure::Id->is_uuid($post_id)
      || !GPForum::Infrastructure::Id->is_uuid($reply_to_post_id);
    my $row = $self->_functions->row(
        'forum_link_reply',
        {
            post_id          => $post_id,
            reply_to_post_id => $reply_to_post_id,
        }
    );
    return $row && $row->{linked} ? 1 : 0;
}

# For the posts of a page, by post id: the post each answers, with its
# position and its author's name. A post answering none is absent.
sub targets_for_posts ( $self, $post_ids ) {
    return {} if !@{$post_ids};
    my $rows = $self->_functions->rows( @{ $self->targets_call($post_ids) } );
    return {
        map {
            $_->{post_id} => {
                author_username => $_->{reply_to_author_username},
                position        => $_->{reply_to_position},
                post_id         => $_->{reply_to_post_id},
            }
        } @{$rows}
    };
}

# The call targets_for_posts makes: a page that reads the targets with its
# other reads in one statement (Service::Forum::ThreadPageReads) answers it.
sub targets_call ( $, $post_ids ) {
    return [ 'forum_reply_targets', { post_ids => $post_ids } ];
}

# Reply links exist only as api.* functions (ADR 0126).
sub _functions ($self) {
    return $self->functions // GPForum::X::Argument->throw(
        message => 'reply links need the SQL function layer' );
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::ReplyLinks - Which post a reply answers.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $links = GPForum::Service::Forum::ReplyLinks->new( schema => $schema );
    $links->link_reply( $post_id, $reply_to_post_id );
    $links->targets_for_posts( \@post_ids );

=head1 DESCRIPTION

A reply may answer one post in particular (ADR 0132). The link is a row of
its own, written after the reply, so the reply command stays as it is; the
page reads the links of its posts in one call. Every statement is an
C<api.forum_*> function (ADR 0126).

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>). C<schema> is required.

=head2 link_reply

Takes the reply's post id and the id of the post it answers. Returns 1
when the link holds (made now, or made before), 0 when it cannot: a post
not in the same thread, not visible, the reply itself, or an id that is
not a uuid.

=head2 targets_for_posts

Takes post ids. Returns, by post id, C<post_id>, C<position> and
C<author_username> of the post answered; posts answering none are absent.

=head2 targets_call

Takes post ids; answers the call L</targets_for_posts> makes, the
function's catalogue name and its values. The class answers it too.

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
