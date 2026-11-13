# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::BookmarkFolders;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SourceFunction;
use GPForum::Infrastructure::SqlFunction;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

# A folder is a few words of the member's own, up to forty characters
# (ADR 0136).
const my $MAX_LENGTH => 40;

__PACKAGE__->requires(qw(schema));

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# The reader the counts are cut to (a GPForum::Service::Forum::Readability).
has readability => undef;    # optional: without one every live bookmark counts

# Each operation is written once, as its promise method (ADR 0177); the
# readability the folder list resolves its viewer with blocks with its
# blocking twin.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(file_bookmark list_folders));
GPForum::Infrastructure::SqlFunction->blocking_parts('readability');

# The folder a text names: trimmed, its spaces folded; nothing when the
# text is empty, undef when it is too long to be a folder.
sub normalise ( $, $text ) {
    my $folder = $text // q{};
    $folder =~ s/\s+/ /gmsx;
    $folder =~ s/\A\s|\s\z//gmsx;
    return undef if length $folder > $MAX_LENGTH;

    return $folder;
}

# Files the member's own bookmark in the folder the text names, or takes it
# out of its folder when the text is empty. Answers { bookmark_id, folder }
# (the folder undef when it has none), or undef when the bookmark is not the
# member's, is removed, is not an id, or the folder is too long.
async sub file_bookmark_p ( $self, $bookmark_id, $user_id, $text,
    $context = undef )
{
    my $values = $self->_folder_values( $bookmark_id, $user_id, $text );
    return undef if !$values;
    return _filed(
        await $self->_functions->row_p(
            'community_set_bookmark_folder',
            $values, $context
        )
    );
}

sub _folder_values ( $self, $bookmark_id, $user_id, $text ) {
    return undef
      if !GPForum::Infrastructure::Id->is_uuid($bookmark_id)
      || !GPForum::Infrastructure::Id->is_uuid($user_id);
    my $folder = $self->normalise($text);
    return undef if !defined $folder;
    return {
        bookmark_id => $bookmark_id,
        folder      => $folder,
        user_id     => $user_id,
    };
}

sub _filed ($row) {
    return undef if !$row;

    return { bookmark_id => $row->{bookmark_id}, folder => $row->{folder} };
}

# The member's folders, by name, each with how many of its bookmarks of
# the kind the page lists the reader may still read: the count the list
# beside it shows. A folder whose bookmarks the reader can no longer read is
# not offered. Options: viewer (the reader, as the bookmark list takes it,
# resolved here when it is not given) and target_type.
async sub list_folders_p ( $self, $user_id, $options = {}, $context = undef ) {
    return [] if !GPForum::Infrastructure::Id->is_uuid($user_id);
    my $readability = $self->readability;
    my $viewer =
      await GPForum::Infrastructure::SourceFunction->viewer_p( $readability,
        $user_id, $options->{viewer}, $context );
    my $rows = await $self->_functions->rows_p(
        'community_list_bookmark_folders',
        {
            %{ GPForum::Infrastructure::SourceFunction->parameters(
                    $readability, $user_id, $viewer )
            },
            target_type => $options->{target_type},
        },
        $context
    );
    return _folders($rows);
}

sub _folders ($rows) {
    return [
        map {
            +{
                bookmark_count => $_->{bookmark_count},
                folder         => $_->{folder}
            }
        } @{$rows}
    ];
}

# Folders exist only as api.* functions (ADR 0126).
sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'bookmark folders need the SQL function layer' );
}

1;

__END__

=head1 NAME

GPForum::Service::Community::BookmarkFolders - The folders a member files bookmarks in.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $folders = GPForum::Service::Community::BookmarkFolders->new(
        schema      => $schema,
        readability => $readability,
    );
    $folders->file_bookmark( $bookmark_id, $user_id, 'Read later' );
    $folders->list_folders( $user_id,
        { viewer => $viewer, target_type => 'thread' } );

=head1 DESCRIPTION

ADR 0136: a member files a bookmark in a folder of their own naming. The
folder is a row beside the bookmark, written after the bookmark command
through C<api.community_set_bookmark_folder_v1>; the bookmarks page lists
the member's folders with their counts through
C<api.community_list_bookmark_folders>, which counts what the list beside
it shows (migration 1047), and the bookmark list carries
each bookmark's folder (C<api.community_list_bookmarks_v3>). Each
operation is written once, as its promise method (ADR 0177).

=head1 SUBROUTINES/METHODS

=head2 normalise

The folder a text names: trimmed and folded; empty for no folder, undef
when too long.

=head2 file_bookmark_p

Takes a bookmark id, the member's id and the folder's text, then an
optional query context. Files the member's own bookmark in a folder, or
takes it out of its folder; answers C<{ bookmark_id, folder }> or undef.

C<file_bookmark> is its blocking twin, with the ids and the text.

=head2 list_folders_p

Takes the member's id and an optional hash reference with C<viewer> (the
reader, by default the member) and C<target_type>, then an optional query
context. Answers the member's folders, by name, each with its
C<bookmark_count>: the bookmarks of that type in it the reader may read,
when C<readability> is set; a folder with none is left out. The viewer is
resolved on the same call layer when it is not given.

C<list_folders> is its blocking twin, with the id and the options.

=head1 DIAGNOSTICS

Without the SQL function layer every call throws
L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SourceFunction>,
L<GPForum::Infrastructure::SqlFunction>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A folder is per bookmark; there is no folder object to rename or delete.
Taking every bookmark out of a folder is the end of the folder.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
