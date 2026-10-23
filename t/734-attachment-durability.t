# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use Mojo::File qw(tempdir path);
use Test::More;

use lib 'lib';
use lib 't/lib';
use GPForum::OS::Filesystem;
use GPForum::Service::Attachment::FilesystemStorage;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';
const my $STAT_SIZE     => 7;
const my $MODE_MASK     => oct '777';
const my $PRIVATE_MODE  => oct '600';
const my $CREATION_MODE => oct '666';

my $directory = tempdir;
my $storage   = GPForum::Service::Attachment::FilesystemStorage->new(
    root => "$directory/objects" );
ok( $storage->filesystem->durable,
    'attachment storage requires durable writes' );
my $written = $storage->write_object( 'new/nested/file', 'approved bytes' );
is(
    $storage->read_object('new/nested/file'),
    'approved bytes',
    'a real file and directory sync succeeds'
);
ok( !-e $written->{temporary_path},
    'the published object has no leftover temporary file' );
is(
    ( stat $written->{path} )[2] & $MODE_MASK,
    $CREATION_MODE & ~umask,
    'published objects preserve the service umask for proxy access'
);

# fsync only sees the descriptor: small uploads must first leave Perl's
# output buffer. This assertion catches a missing flush before sync.
my @sizes_at_sync;
my @modes_at_flush;
my $flush = IO::Handle->can('flush');
with_replaced_subs(
    'IO::Handle',
    {
        flush => sub ($handle) {
            push @modes_at_flush, ( stat $handle )[2] & $MODE_MASK;
            return $flush->($handle);
        },
        sync => sub ($handle) {
            push @sizes_at_sync, ( stat $handle )[$STAT_SIZE];
            return 1;
        },
    },
    sub {
        $storage->write_object( 'new/nested/buffered', 'buffered bytes' );
    }
);
is(
    $sizes_at_sync[0],
    length('buffered bytes'),
    'all buffered bytes reached the descriptor before fsync'
);
is( $modes_at_flush[0], $PRIVATE_MODE,
    'the temporary object is private while its bytes are written' );

# File sync fails BEFORE publication: an existing, approved object remains
# intact, and neither a new name nor temporary garbage is left behind.
with_replaced_subs(
    'IO::Handle',
    { sync => sub { return 0; } },
    sub {
        my $error;
        try {
            $storage->write_object( 'new/nested/file',
                'incomplete replacement' );
        }
        catch ($failure) { $error = "$failure"; };
        like(
            $error,
            qr/failed[ ]to[ ]sync[ ]temporary[ ]file/msx,
            'a failed fsync fails the upload'
        );
    }
);
is(
    $storage->read_object('new/nested/file'),
    'approved bytes',
    'a failed write leaves the approved version intact'
);
my @files = path( $written->{path} )->dirname->list( { hidden => 1 } )->each;
is_deeply(
    [ sort map { $_->basename } @files ],
    [ 'buffered', 'file' ],
    'failed file sync cleans its temporary file'
);

# A post-rename directory sync failure cannot promise crash durability. The
# bytes visible to readers are nevertheless complete; the upload reports an
# error so the pipeline never marks it uploaded/clean.
with_replaced_subs(
    'GPForum::OS::Filesystem',
    {
        sync_directory => sub { die "directory sync failed\n"; },
    },
    sub {
        my $error;
        try { $storage->write_object( 'new/nested/other', 'complete bytes' ); }
        catch ($failure) { $error = "$failure"; };
        like(
            $error,
            qr/directory[ ]sync[ ]failed/msx,
            'a directory sync failure is never reported as success'
        );
    }
);
is(
    $storage->read_object('new/nested/other'),
    'complete bytes',
    'rename exposes the whole object even if durability cannot be confirmed'
);
done_testing();

1;
