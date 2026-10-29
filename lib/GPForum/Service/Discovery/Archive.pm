# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Discovery::Archive;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;
use Carp qw(croak);
use File::Temp;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Discovery::Mbox;
use GPForum::Service::Forum::Viewer;

our $VERSION = '0.001';

const my $ARCHIVE_PAGE_SIZE => 100;
__PACKAGE__->requires(
    qw(schema category_reader thread_reader thread_detail_reader post_reader signer base_url)
);
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};
has mbox => sub ($self) {
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

sub signature ( $self, $post ) {
    my $row = $self->functions->row( 'forum_protocol_signature',
        { body_id => $post->{current_body_id} } );
    return undef if !$row;

    return $self->_verified( $post, $row->{envelope} );
}

# The signatures of a page of posts, by body id, in one statement; a post
# without one is not in the answer. Each was a statement of its own inside
# the export's repeatable-read transaction.
sub signatures ( $self, $posts ) {
    my @body_ids = grep { defined } map { $_->{current_body_id} } @{$posts};
    return {} if !@body_ids;

    my $rows = $self->functions->rows( 'forum_protocol_signatures',
        { body_ids => \@body_ids } );

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

sub spool ( $self, $kind, $id, $viewer ) {
    my $file = File::Temp->new(
        TEMPLATE => 'gpforum-mbox-XXXXXX',
        TMPDIR   => 1,
        UNLINK   => 1
    );
    binmode $file or croak 'cannot open mbox spool';
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
                    {
                        category_id    => $id,
                        viewer_user_id => $viewer->user_id,
                        viewer_scope   => $viewer->within(
                            $id, $category->get_column('space_id')
                        ),
                        limit => $ARCHIVE_PAGE_SIZE,
                        after => $after
                    }
                );
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

sub _thread ( $self, $file, $id, $viewer ) {
    my $thread = $self->thread_detail_reader->find_thread( $id, $viewer );
    return 0 if !$thread;
    my %head = $thread->get_columns;
    my ( $after, $root );
    while (1) {
        my $page = $self->post_reader->list_thread_posts(
            {
                thread_id      => $id,
                viewer_user_id => $viewer->user_id,
                viewer_scope   =>
                  $self->thread_detail_reader->post_scope( $viewer, $thread ),
                limit => $ARCHIVE_PAGE_SIZE,
                after => $after
            }
        );
        my @posts = map { +{ $_->get_columns } }
          grep { !defined $_->get_column('deleted_at') } @{ $page->{items} };
        my $envelopes = $self->signatures( \@posts );
        for my $post (@posts) {
            my $envelope = $envelopes->{ $post->{current_body_id} // q{} };
            print {$file} $self->mbox->message(
                \%head,
                $post,
                defined $envelope
                ? $self->_verified( $post, $envelope )
                : undef,
                $root
            ) or croak 'cannot write mbox spool';
            $root //= $post->{post_id};
        }
        last if !$page->{has_next};
        $after = $page->{next_cursor};
    }
    return 1;
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

=head2 signature

Returns the persisted envelope, undef for unsigned content, or throws if verification fails.

=head2 signatures

Takes an array reference of posts (hashes with C<current_body_id>). Returns
a hash reference from body id to the persisted envelope, read in one
statement (C<api.forum_protocol_signatures>); unsigned posts have no key.
The envelopes are not verified here: C<spool> verifies each as it writes
the post, and throws as L</signature> does.

=head2 key_set

Returns the public JWK set trusted by the server filesystem.

=head2 spool

Returns a private temporary mbox file for all authorized posts of a thread or category, or undef when inaccessible.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $file = $archive->spool( thread => $id, $viewer );

=head1 DIAGNOSTICS

Throws on storage, filesystem or signature failure. Inaccessible resources return undef.

=head1 CONFIGURATION AND ENVIRONMENT

Readers, schema, signer and public base URL are injected.

=head1 DEPENDENCIES

GPForum readers, SqlFunction, File::Temp and the mbox renderer.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Archives omit hidden and deleted posts and require enough temporary disk space.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
