# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Discovery::Archive;

use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;
use Const::Fast;
use Carp qw(croak);
use File::Temp;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Discovery::Mbox;
use Mojo::Promise;
use GPForum::X::Io;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $ARCHIVE_PAGE_SIZE => 100;
const my $STAT_SIZE         => 7;
const my $STAT_MTIME        => 9;
__PACKAGE__->requires(
    qw(schema category_reader thread_reader thread_detail_reader post_reader signer base_url)
);
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;
has mbox      => sub ($self) {
    return GPForum::Service::Discovery::Mbox->new(
        base_url => $self->base_url );
};

GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(post signature signatures));
GPForum::Infrastructure::SqlFunction->blocking_parts(
    qw(category_reader thread_reader thread_detail_reader post_reader));

async sub post_p ( $self, $id, $viewer, $context = undef ) {
    my $visible =
      await $self->post_reader->find_visible_post_p( $id, $viewer, $context );
    return undef if !$visible;
    my $thread_id = $visible->get_column('thread_id');
    my $thread =
      await $self->thread_detail_reader->find_thread_p( $thread_id, $viewer,
        $context );
    return undef if !$thread;
    return await $self->post_reader->find_listed_post_p(
        {
            post_id        => $id,
            thread_id      => $thread_id,
            viewer_user_id => $viewer->user_id,
            viewer_scope   =>
              $self->thread_detail_reader->post_scope( $viewer, $thread ),
        },
        $context
    );
}

async sub signature_p ( $self, $post, $context = undef ) {
    my $row = await $self->_functions->row_p( 'forum_protocol_signature',
        { body_id => $post->{current_body_id} }, $context );
    return undef if !$row;

    return $self->_verified( $post, $row->{envelope} );
}

# The signatures of a page of posts, by body id, in one statement; a post
# without one is not in the answer. Each was a statement of its own inside
# the export's repeatable-read transaction.
async sub signatures_p ( $self, $posts, $context = undef ) {
    my @body_ids = grep { defined } map { $_->{current_body_id} } @{$posts};
    return {} if !@body_ids;

    my $rows = await $self->_functions->rows_p( 'forum_protocol_signatures',
        { body_ids => \@body_ids }, $context );
    return { map { $_->{body_id} => $_->{envelope} } @{$rows} };
}

sub _verified ( $self, $post, $envelope ) {
    croak 'post signature verification failed'
      if !$self->signer->verify( { %{$post}, body_format => 'markdown' },
        $envelope );

    return $envelope;
}

sub key_set ($self) {
    my %keys = %{ $self->signer->trusted_keys };
    return { keys => [ map { $keys{$_} } sort keys %keys ] };
}

# The key set answered in the worker. It reads no database: the signer
# reads its key files once and keeps them.
sub key_set_p ( $self, $context = undef ) {
    return Mojo::Promise->resolve->then( sub { return $self->key_set; } );
}

# The spool as a file the caller keeps until delivery ends: the blocking
# twin of _spooled_file_p.
sub spool ( $self, @arguments ) {
    return GPForum::Infrastructure::SqlFunction->settle( $self,
        '_spooled_file_p', @arguments );
}

# The spool handed over as plain data: the receiver adopts the file and
# deletes it.
async sub spool_p ( $self, $kind, $id, $viewer, $context = undef ) {
    my $file = await $self->_spooled_file_p( $kind, $id, $viewer, $context );
    return $file ? _descriptor($file) : undef;
}

# One READ ONLY, REPEATABLE READ transaction, the readers' pages read on its
# call layer, each page written to the spool as it is read: memory stays
# bounded however long the thread or category is.
async sub _spooled_file_p ( $self, $kind, $id, $viewer, $context = undef ) {
    my $file  = _spool_file();
    my $found = await $self->_functions->transaction_p(
        sub ($scope) {
            return GPForum::Infrastructure::SqlFunction->joined( $self, $scope )
              ->_spooled_p( $file, $kind, $id, $viewer, $context );
        },
        $context,
        { read_only => 1, repeatable_read => 1 }
    );
    return undef if !$found;
    $file->flush or croak 'cannot flush mbox spool';

    return $file;
}

# The spool's path, size, modification time and identity.
sub _descriptor ($file) {
    my @stat     = stat $file;
    my $metadata = {
        path   => $file->filename,
        size   => $stat[$STAT_SIZE],
        mtime  => $stat[$STAT_MTIME],
        device => $stat[0],
        inode  => $stat[1]
    };
    $file->unlink_on_destroy(0);
    return $metadata;
}

sub _spool_file {
    my $file = File::Temp->new(
        TEMPLATE => 'gpforum-mbox-XXXXXX',
        TMPDIR   => 1,
        UNLINK   => 1
    );
    binmode $file
      or GPForum::X::Io->throw( message => 'cannot open mbox spool' );
    return $file;
}

async sub _spooled_p ( $self, $file, $kind, $id, $viewer, $context ) {
    return await $self->_thread_p( $file, $id, $viewer, $context )
      if $kind eq 'thread';
    my $category =
      await $self->category_reader->find_category_p( $id, $viewer, $context );
    return 0 if !$category;
    my $after;
    while (1) {
        my $page =
          await $self->thread_reader->list_category_threads_p(
            _threads_request( $id, $viewer, $category, $after ), $context );
        for my $row ( @{ $page->{items} } ) {
            await $self->_thread_p( $file, $row->get_column('thread_id'),
                $viewer, $context );
        }
        last if !$page->{has_next};
        $after = $page->{next_cursor};
    }
    return 1;
}

sub _threads_request ( $id, $viewer, $category, $after ) {
    return {
        category_id    => $id,
        viewer_user_id => $viewer->user_id,
        viewer_scope   =>
          $viewer->within( $id, $category->get_column('space_id') ),
        limit => $ARCHIVE_PAGE_SIZE,
        after => $after
    };
}

async sub _thread_p ( $self, $file, $id, $viewer, $context ) {
    my $thread =
      await $self->thread_detail_reader->find_thread_p( $id, $viewer,
        $context );
    return 0 if !$thread;
    my %head = $thread->get_columns;
    my ( $after, $root );
    while (1) {
        my $page =
          await $self->post_reader->list_thread_posts_p(
            $self->_posts_request( $id, $viewer, $thread, $after ), $context );
        my @posts = _listed( $page->{items} );
        $self->_write_posts( $file, \%head, \@posts,
            await $self->signatures_p( \@posts, $context ), \$root );
        last if !$page->{has_next};
        $after = $page->{next_cursor};
    }
    return 1;
}

sub _posts_request ( $self, $id, $viewer, $thread, $after ) {
    return {
        thread_id      => $id,
        viewer_user_id => $viewer->user_id,
        viewer_scope   =>
          $self->thread_detail_reader->post_scope( $viewer, $thread ),
        limit => $ARCHIVE_PAGE_SIZE,
        after => $after
    };
}

# A page's posts as plain hashes, the deleted ones left out.
sub _listed ($items) {
    return map { +{ $_->get_columns } }
      grep { !defined $_->get_column('deleted_at') } @{$items};
}

# A page of posts written to the spool, each signature verified; $root
# holds the thread's first post, which the others answer.
sub _write_posts ( $self, $file, $head, $posts, $envelopes, $root ) {
    for my $post ( @{$posts} ) {
        my $envelope = $envelopes->{ $post->{current_body_id} // q{} };
        print {$file}
          $self->mbox->message( $head, $post,
            defined $envelope
            ? $self->_verified( $post, $envelope )
            : undef,
            ${$root} )
          or GPForum::X::Io->throw( message => 'cannot write mbox spool' );
        ${$root} //= $post->{post_id};
    }
    return;
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'the mbox archive needs the PostgreSQL function layer' );
}

1;

__END__

=head1 NAME

GPForum::Service::Discovery::Archive - Complete authorized thread and category archives.

=head1 DESCRIPTION

C<spool> traverses all reader keyset pages in a repeatable-read transaction
and writes a private temporary mbox file, keeping memory bounded. The caller
retains the File::Temp object until delivery finishes. Permissions apply at
space, category, thread and post level; deleted posts are excluded even for
their authors. Persisted signatures are verified, never replaced on export.
Historic posts without an attestation are explicitly marked unsigned.

Each read is written once, as its promise method (ADR 0177). C<post>,
C<signature>, C<signatures> and C<spool> are that body settled on the
blocking layer, with the four readers blocking too.

=head1 SYNOPSIS

    my $file = $archive->spool( thread => $id, $viewer );

=head1 SUBROUTINES/METHODS

=head2 post_p

Resolves with the authorized visible post with its current source, or
undef; an optional query context last. C<post> is its blocking twin.

=head2 signature_p

Resolves with the persisted envelope, or undef for unsigned content; an
optional query context last. Fails if verification fails. C<signature> is
its blocking twin.

=head2 signatures_p

Takes an array reference of posts (hashes with C<current_body_id>). Resolves
with a hash reference from body id to the persisted envelope, read in one
statement (C<api.forum_protocol_signatures>); unsigned posts have no key.
The envelopes are not verified here: the spool verifies each as it writes
the post. C<signatures> is its blocking twin.

=head2 key_set

Returns the public JWK set trusted by the server filesystem.

=head2 key_set_p

L</key_set> as a promise, answered in the calling process: it reads no
database, and the signer keeps the keys it read. An optional query context
last is accepted and unused.

=head2 spool

Returns a private temporary mbox file for all authorized posts of a thread
or category, or undef when inaccessible: the body of L</spool_p> settled on
the blocking layer.

=head2 spool_p

Builds the archive on the call layer the archive holds, in one READ ONLY,
REPEATABLE READ transaction whose call layer the readers read every page
on, and writes it to a private temporary file as it reads. Resolves with
the file's path, size, modification time, device and inode as plain data,
or undef when the thread or category is not readable; the HTTP caller
adopts the file and owns its deletion after streaming or disconnect.

=head1 VERSION

Version 0.001.

=head1 DIAGNOSTICS

Throws on storage, filesystem or signature failure, and
L<GPForum::X::Unavailable> without the function layer. Inaccessible
resources return undef.

=head1 CONFIGURATION AND ENVIRONMENT

Readers, schema, signer and public base URL are injected.

=head1 DEPENDENCIES

Good Phorum readers, SqlFunction, File::Temp and the mbox renderer.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Archives omit hidden and deleted posts and require enough temporary disk space.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause license.

=cut
