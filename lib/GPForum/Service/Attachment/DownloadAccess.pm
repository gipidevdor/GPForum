# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::DownloadAccess;

use Const::Fast;
use GPForum::Service::Attachment::Record;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my $STATE_AVAILABLE    => 'available';
const my $SCAN_CLEAN         => 'clean';
const my $VISIBILITY_PUBLIC  => 'public';
const my $VISIBILITY_MEMBERS => 'members';
const my $VISIBILITY_PRIVATE => 'private';
const my $STATE_LOCKED       => 'locked';
const my $STATE_VISIBLE      => 'visible';
const my $TARGET_PROFILE     => 'profile';
const my $TARGET_THREAD      => 'thread';

has record => sub { return GPForum::Service::Attachment::Record->new; };

# ADR 0102: who may read the linked post or thread -- its space, category,
# thread and the post itself. Without it, the target's own visibility alone.
has readability => undef;    # optional: visibility decides without it

sub unavailable ( $self, $attachment ) {
    if ( !$attachment ) {
        return $self->not_found;
    }
    if ( !$self->downloadable($attachment) ) {
        return $self->not_found;
    }

    return undef;
}

sub not_found {
    return { error => 'not_found', ok => 0 };
}

sub forbidden {
    return { error => 'forbidden', ok => 0 };
}

sub downloadable ( $self, $attachment ) {
    if ( defined $self->record->column( $attachment, 'deleted_at' ) ) {
        return 0;
    }
    if ( !$self->_is_available($attachment) ) {
        return 0;
    }

    return $self->_is_clean($attachment);
}

sub payload ( $self, $attachment ) {
    return {
        attachment    => $self->record->row_hash($attachment),
        attachment_id => $self->record->column( $attachment, 'attachment_id' ),
        byte_size     => $self->record->column( $attachment, 'byte_size' ),
        media_type    => $self->record->column( $attachment, 'media_type' ),
        object_key    => $self->record->column( $attachment, 'object_key' ),
        ok                => 1,
        original_filename =>
          $self->record->column( $attachment, 'original_filename' ),
    };
}

# The payload of a file listed under a post, from one row that carries the
# link, the file (file_*), the post (post_*) and the post's placement, as
# api.attachment_post_files answers it: the file available and clean, the
# post live and visible, and the post readable by the reader (ADR 0102,
# judged from the placement in hand: no statement) or the viewer the
# file's owner; without a readability policy, the post's visibility open
# to the viewer. The page's one link is the way to the file, so no other
# link of the file is asked for. Undef when the file is not listed.
sub listing_payload ( $self, $row, $reader, $viewer_user_id ) {
    my $attachment = $self->_file_of($row);
    return undef if $self->unavailable($attachment);

    my $target = $self->_post_of($row);
    return undef if !$self->target_visible( $target, 'post' );
    if ( $self->readability ) {
        return undef
          if !$self->readability->may_read( $reader // $viewer_user_id,
            $self->_placement_of($row) )
          && !$self->is_owner( $attachment, $viewer_user_id );
    }
    elsif ( !$self->visibility_allows( $target, $attachment, $viewer_user_id ) )
    {
        return undef;
    }

    return $self->payload($attachment);
}

sub owner_payload ( $self, $attachment, $viewer_user_id ) {
    if ( !$self->is_owner( $attachment, $viewer_user_id ) ) {
        return undef;
    }

    return $self->payload($attachment);
}

sub authorized ( $self, $input ) {
    my $linked = $input->{linked} || [];
    if ( !@{$linked} ) {
        return $self->_unlinked($input);
    }

    return $self->_linked( $input, $linked );
}

sub is_owner ( $self, $attachment, $viewer_user_id ) {
    if ( !$self->record->has_text($viewer_user_id) ) {
        return 0;
    }

    my $owner = $self->record->column( $attachment, 'owner_user_id' ) || q{};
    return $owner eq $viewer_user_id ? 1 : 0;
}

sub target_visible ( $self, $target, $target_type ) {
    if ( !$self->_target_present($target) ) {
        return 0;
    }

    return $self->_moderation_visible( $target, $target_type );
}

sub visibility_allows ( $self, $target, $attachment, $viewer_user_id ) {
    my $visibility =
      $self->record->column( $target, 'visibility' ) || $VISIBILITY_PUBLIC;
    if ( $self->_open_visibility( $visibility, $viewer_user_id ) ) {
        return 1;
    }
    if ( $self->_private_author( $visibility, $target, $viewer_user_id ) ) {
        return 1;
    }

    return $self->is_owner( $attachment, $viewer_user_id );
}

sub link_allows ( $self, $input ) {
    my $target_type = $self->record->column( $input->{link}, 'target_type' );
    if ( $target_type eq $TARGET_PROFILE ) {
        return $self->is_owner( $input->{attachment},
            $input->{viewer_user_id} );
    }

    return $self->_linked_target_allows($input);
}

sub _unlinked ( $self, $input ) {
    return $self->owner_payload( $input->{attachment},
        $input->{viewer_user_id} )
      || $self->forbidden;
}

sub _linked ( $self, $input, $linked ) {
    for my $item ( @{$linked} ) {
        if ( $self->_item_allows( $input, $item ) ) {
            return $self->payload( $input->{attachment} );
        }
    }

    return $self->forbidden;
}

sub _item_allows ( $self, $input, $item ) {
    return $self->link_allows(
        {
            attachment     => $input->{attachment},
            link           => $item->{link},
            target         => $item->{target},
            viewer         => $input->{viewer},
            viewer_user_id => $input->{viewer_user_id},
        }
    );
}

sub _linked_target_allows ( $self, $input ) {
    my $target_type = $self->record->column( $input->{link}, 'target_type' );
    if ( !$self->target_visible( $input->{target}, $target_type ) ) {
        return 0;
    }
    if ( !$self->readability ) {
        return $self->visibility_allows( $input->{target},
            $input->{attachment}, $input->{viewer_user_id},
        );
    }

    # The uploader keeps their own file; anyone else reads it only through a
    # post or thread they can read.
    return 1
      if $self->readability->readable_by( $input->{viewer}
          // $input->{viewer_user_id},
        $target_type, $self->record->column( $input->{link}, 'target_id' ) );

    return $self->is_owner( $input->{attachment}, $input->{viewer_user_id} );
}

# The file's columns of a row that carries them as file_*, and the post's
# as post_*, under the names the rules read.
const my @FILE_COLUMNS => qw(
  owner_user_id object_key original_filename media_type byte_size state
  scan_status deleted_at
);
const my @POST_COLUMNS => qw(
  thread_id author_user_id visibility moderation_state hidden_at deleted_at
);
const my @PLACEMENT_COLUMNS => qw(
  category_id category_visibility category_deleted_at space_id
  space_visibility thread_author thread_visibility thread_deleted_at
  thread_state post_author post_visibility post_deleted_at post_state
);

sub _file_of ( $self, $row ) {
    return {
        attachment_id => $self->record->column( $row, 'attachment_id' ),
        map { $_ => $self->record->column( $row, "file_$_" ) } @FILE_COLUMNS,
    };
}

# The post's placement, as Readability reads it from forum_post_placement.
sub _placement_of ( $self, $row ) {
    my %as = (
        post_author => 'post_author_user_id',
        post_state  => 'post_moderation_state',
    );

    return { map { $_ => $self->record->column( $row, $as{$_} // $_ ) }
          @PLACEMENT_COLUMNS };
}

sub _post_of ( $self, $row ) {
    return {
        post_id => $self->record->column( $row, 'target_id' ),
        map { $_ => $self->record->column( $row, "post_$_" ) } @POST_COLUMNS,
    };
}

sub _is_available ( $self, $attachment ) {
    my $state = $self->record->column( $attachment, 'state' ) || q{};
    return $state eq $STATE_AVAILABLE ? 1 : 0;
}

sub _is_clean ( $self, $attachment ) {
    my $scan = $self->record->column( $attachment, 'scan_status' ) || q{};
    return $scan eq $SCAN_CLEAN ? 1 : 0;
}

sub _target_present ( $self, $target ) {
    if ( !$target ) {
        return 0;
    }
    if ( defined $self->record->column( $target, 'deleted_at' ) ) {
        return 0;
    }
    if ( defined $self->record->column( $target, 'hidden_at' ) ) {
        return 0;
    }

    return 1;
}

sub _moderation_visible ( $self, $target, $target_type ) {
    my $state = $self->record->column( $target, 'moderation_state' ) || q{};
    if ( $state eq $STATE_VISIBLE ) {
        return 1;
    }
    if ( $target_type eq $TARGET_THREAD && $state eq $STATE_LOCKED ) {
        return 1;
    }

    return 0;
}

sub _open_visibility ( $self, $visibility, $viewer_user_id ) {
    if ( $visibility eq $VISIBILITY_PUBLIC ) {
        return 1;
    }
    if (   $visibility eq $VISIBILITY_MEMBERS
        && $self->record->has_text($viewer_user_id) )
    {
        return 1;
    }

    return 0;
}

sub _private_author ( $self, $visibility, $target, $viewer_user_id ) {
    if ( $visibility ne $VISIBILITY_PRIVATE ) {
        return 0;
    }

    my $author = $self->record->column( $target, 'author_user_id' ) || q{};
    return $author eq ( $viewer_user_id || q{} ) ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Service::Attachment::DownloadAccess - Attachment download decisions.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $denied = $access->unavailable($attachment);
    my $ok     = $access->link_allows(
        {
            attachment     => $attachment,
            link           => $link,
            target         => $post,
            viewer_user_id => $viewer,
        }
    );

=head1 DESCRIPTION

Owns downloadability, owner checks, target visibility, visibility grants, and
the linked-versus-unlinked download payload. It does not load resultsets.
L<GPForum::Service::Attachment::Store> still finds attachments, links, and
target posts or threads.

=head1 SUBROUTINES/METHODS

=head2 unavailable

Returns a not-found payload when the attachment is missing or not downloadable.

=head2 not_found

Returns the not-found download payload.

=head2 forbidden

Returns the forbidden download payload.

=head2 downloadable

True when the attachment is available, clean, and not deleted.

=head2 payload

Returns the authorized download hash.

=head2 listing_payload

Takes one row of C<api.attachment_post_files> -- a link with its file as
C<file_*> columns, its post as C<post_*> columns and the post's placement
-- the reader (a viewer, or undef) and the viewer's user id. Returns the
download payload when the file is listed under that post: available and
clean, the post live and visible, and the post readable by the reader
(ADR 0102, from the placement in hand) or the viewer the file's owner;
without a readability policy, the post's visibility open to the viewer.
Returns undef otherwise. No statement is made.

=head2 owner_payload

Returns the download payload when the viewer owns an unlinked attachment.

=head2 authorized

Returns the download payload or a forbidden hash from preloaded links and
targets. Empty link lists use the unlinked owner rule.

=head2 is_owner

True when the viewer matches the attachment owner.

=head2 target_visible

True when the linked post or thread is present and readable.

=head2 visibility_allows

True when public, member, private-author, or owner rules grant access.

=head2 link_allows

True when a profile owner or a visible linked target grants download.

=head1 DIAGNOSTICS

Denied downloads use C<not_found> or C<forbidden> without naming storage keys.

=head1 CONFIGURATION AND ENVIRONMENT

Requires an L<GPForum::Service::Attachment::Record> for row access.

=head1 DEPENDENCIES

Uses L<Const::Fast> and L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Target rows must be loaded by the store before C<link_allows>.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
