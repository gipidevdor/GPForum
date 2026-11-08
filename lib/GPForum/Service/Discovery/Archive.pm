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

sub post ( $self, $id, $viewer ) {
    my $visible = $self->post_reader->find_visible_post( $id, $viewer );
    return undef if !$visible;
    my $thread = $self->thread_detail_reader->find_thread(
        $visible->get_column('thread_id'), $viewer );
    return undef if !$thread;
    return $self->post_reader->find_listed_post(
        {
            post_id        => $id,
            thread_id      => $visible->get_column('thread_id'),
            viewer_user_id => $viewer->user_id,
            viewer_scope   =>
              $self->thread_detail_reader->post_scope( $viewer, $thread ),
        }
    );
}

# The post page's read on the worker's pooled asynchronous connections.
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

sub signature ( $self, $post ) {
    my $row = $self->functions->row( 'forum_protocol_signature',
        { body_id => $post->{current_body_id} } );
    return undef if !$row;

    return $self->_verified( $post, $row->{envelope} );
}

async sub signature_p ( $self, $post, $context = undef ) {
    my $row = await $self->functions->row_p( 'forum_protocol_signature',
        { body_id => $post->{current_body_id} }, $context );
    return undef if !$row;

    return $self->_verified( $post, $row->{envelope} );
}

# The signatures of a page of posts, by body id, in one statement; a post
# without one is not in the answer. Each was a statement of its own inside
# the export's repeatable-read transaction.
sub signatures ( $self, $posts ) {
    my @body_ids = _body_ids($posts);
    return {} if !@body_ids;

    return _envelopes(
        $self->functions->rows(
            'forum_protocol_signatures', { body_ids => \@body_ids }
        )
    );
}

async sub signatures_p ( $self, $posts, $context = undef ) {
    my @body_ids = _body_ids($posts);
    return {} if !@body_ids;

    return _envelopes(
        await $self->functions->rows_p(
            'forum_protocol_signatures', { body_ids => \@body_ids },
            $context
        )
    );
}

sub _body_ids ($posts) {
    return grep { defined } map { $_->{current_body_id} } @{$posts};
}

sub _envelopes ($rows) {
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
# reads its key files once and keeps them, so the fork call_p's fallback
# made per request opened a PostgreSQL connection for nothing, and read the
# files again in a child that kept nothing.
sub key_set_p ( $self, $context = undef ) {
    return Mojo::Promise->resolve->then( sub { return $self->key_set; } );
}

# spool on the worker's pooled asynchronous connections, no child process:
# one READ ONLY, REPEATABLE READ transaction, the readers' pages read on its
# call layer, each page written to the spool here as it is read. Resolves
# with the descriptor spool_descriptor gives. Without the function layer (a
# double) the blocking spool answers.
async sub spool_p ( $self, $kind, $id, $viewer, $context = undef ) {
    return $self->spool_descriptor( $kind, $id, $viewer ) if !$self->functions;
    my $file  = _spool_file();
    my $found = await $self->functions->transaction_p(
        sub ($scope) {
            return $self->_on($scope)
              ->_spooled_p( $file, $kind, $id, $viewer, $context );
        },
        $context,
        { read_only => 1, repeatable_read => 1 }
    );
    return undef if !$found;
    $file->flush or croak 'cannot flush mbox spool';

    return _descriptor($file);
}

sub spool_descriptor ( $self, @arguments ) {
    my $file = $self->spool(@arguments) or return undef;
    return _descriptor($file);
}

# The spool's path, size, modification time and identity; the receiver
# adopts the file and deletes it.
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
    binmode $file or croak 'cannot open mbox spool';
    return $file;
}

sub spool ( $self, $kind, $id, $viewer ) {
    my $file  = _spool_file();
    my $found = $self->schema->txn_do(
        sub {
            my $dbh = $self->schema->storage->dbh;
            $dbh->do(
                'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY');
            if ( $kind eq 'thread' ) {
                return $self->_thread( $file, $id, $viewer );
            }
            my $category =
              $self->category_reader->find_category( $id, $viewer );
            return 0 if !$category;
            my $after;
            while (1) {
                my $page = $self->thread_reader->list_category_threads(
                    _threads_request( $id, $viewer, $category, $after ) );
                for my $row ( @{ $page->{items} } ) {
                    $self->_thread( $file, $row->get_column('thread_id'),
                        $viewer );
                }
                last if !$page->{has_next};
                $after = $page->{next_cursor};
            }
            return 1;
        }
    );
    return undef if !$found;
    $file->flush or croak 'cannot flush mbox spool';
    return $file;
}

# The archive and its readers on $scope, the export's transaction.
sub _on ( $self, $scope ) {
    my %readers =
      map { $_ => ref( $self->$_ )->new( %{ $self->$_ }, functions => $scope ) }
      qw(category_reader thread_reader thread_detail_reader post_reader);
    return ref($self)->new( %{$self}, %readers, functions => $scope );
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

sub _thread ( $self, $file, $id, $viewer ) {
    my $thread = $self->thread_detail_reader->find_thread( $id, $viewer );
    return 0 if !$thread;
    my %head = $thread->get_columns;
    my ( $after, $root );
    while (1) {
        my $page = $self->post_reader->list_thread_posts(
            $self->_posts_request( $id, $viewer, $thread, $after ) );
        my @posts = _listed( $page->{items} );
        $self->_write_posts( $file, \%head, \@posts,
            $self->signatures( \@posts ), \$root );
        last if !$page->{has_next};
        $after = $page->{next_cursor};
    }
    return 1;
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
          or croak 'cannot write mbox spool';
        ${$root} //= $post->{post_id};
    }
    return;
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

=head1 SUBROUTINES/METHODS

=head2 post

Returns the authorized visible post with its current source, or undef.

=head2 post_p

L</post> as a promise, with an optional query context last, read on the
worker's pooled asynchronous connections.

=head2 signature

Returns the persisted envelope, undef for unsigned content, or throws if verification fails.

=head2 signature_p

L</signature> as a promise, with an optional query context last; the
envelope is read on the worker's pooled asynchronous connections.

=head2 signatures

Takes an array reference of posts (hashes with C<current_body_id>). Returns
a hash reference from body id to the persisted envelope, read in one
statement (C<api.forum_protocol_signatures>); unsigned posts have no key.
The envelopes are not verified here: C<spool> verifies each as it writes
the post, and throws as L</signature> does.

=head2 signatures_p

L</signatures> as a promise, with an optional query context last, read in
one statement on the call layer the archive holds.

=head2 key_set

Returns the public JWK set trusted by the server filesystem.

=head2 key_set_p

L</key_set> as a promise, answered in the calling process: it reads no
database, and the signer keeps the keys it read. An optional query context
last is accepted and unused.

=head2 spool

Returns a private temporary mbox file for all authorized posts of a thread or category, or undef when inaccessible.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $file = $archive->spool( thread => $id, $viewer );

=head2 spool_descriptor

Creates a spool and transfers its path, size, modification time and file identity as plain data. The receiver must adopt the temporary file with cleanup enabled.

=head2 spool_p

Builds the archive L</spool> builds on the worker's pooled asynchronous
connections, in one READ ONLY, REPEATABLE READ transaction whose call layer
the readers read every page on, and writes it to a private temporary file
as it reads. No child process is involved. Resolves with the descriptor
L</spool_descriptor> returns, or undef when the thread or category is not
readable; the HTTP caller owns deletion after streaming or disconnect.

=head1 DIAGNOSTICS

Throws on storage, filesystem or signature failure. Inaccessible resources return undef.

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
