# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use Test::More;
use Carp qw(croak);
use Test::Exception;
use Digest::SHA qw(sha256_hex);
use Mojo::Asset::File;
use Mojo::File qw(tempfile);
use lib 'lib';
use lib 't/lib';
use GPForum::Infrastructure::Id;
use GPForum::Service::Attachment::PostgresStorage;
use GPForum::Service::Attachment::ContentReview;
use GPForum::Service::Attachment::Source;
use GPForum::Service::Attachment::UploadPipeline;
use GPForum::Service::Attachment::Store;
use GPForum::Service::Attachment::FilesystemStorage;
use GPForum::Service::Attachment::LegacyImport;
use GPForum::Service::Community::AvatarStore;
use GPForum::Service::Community::Avatars;
use GPForum::Test::ImageTool;
use File::Temp qw(tempdir);
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';
const my $ID3_HEADER      => pack 'H*', '49443304000000000000';
const my $PHOTO_SIDE      => 100;
const my $LARGE_FILE_MIB  => 101;
const my $AVATAR_MIDDLE   => 128;
const my $KIB             => 1_024;
const my $SAMPLE_BYTES    => 23;
const my $MAX_BYTE        => 255;
const my $AVATAR_LARGE    => 256;
const my $EXPECTED_CHUNKS => 3;
const my $RANGE_BYTES     => 4;
const my $AVATAR_SMALL    => 64;
const my $SEEK_OFFSET     => 7;
const my $HTTP_CHUNK      => 131_072;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'requires PostgreSQL';
}
my $database = GPForum::Test::PgDatabase->fresh;
my $schema   = $database->schema;
my $dbh      = $database->dbh;
my $storage =
  GPForum::Service::Attachment::PostgresStorage->new( schema => $schema );
my $mib   = $KIB * $KIB;
my $bytes = join q{}, map { chr } 0 .. $MAX_BYTE;
$bytes = $bytes x ( 2 * $mib / length $bytes ) . 'tail';
$storage->write_object( 'binary', $bytes );
is( $storage->read_object('binary'),
    $bytes, 'bytea round trip preserves NUL, backslash and every byte' );
is(
    $dbh->selectrow_array(
q{SELECT count(*) FROM attachment_object_chunks WHERE object_key = 'binary'}
    ),
    $EXPECTED_CHUNKS,
    'one MiB chunking'
);
my $asset = $storage->asset_for('binary');
is( length $asset->get_chunk( 0, undef ),
    $HTTP_CHUNK,
    'an explicit undefined maximum uses the standard Mojo HTTP chunk' );
is(
    $asset->get_chunk( $mib + $SEEK_OFFSET, $SAMPLE_BYTES ),
    substr( $bytes, $mib + $SEEK_OFFSET, $SAMPLE_BYTES ),
    'seek reads requested position'
);
is(
    $asset->start_range( $mib - 2 )->end_range( $mib + 1 )->get_chunk(0),
    substr( $bytes, $mib - 2, 2 ),
    'range ends at chunk boundary'
);
is(
    $asset->get_chunk(2),
    substr( $bytes, $mib, 2 ),
    'range continues into next chunk'
);
is( $asset->get_chunk($RANGE_BYTES), q{}, 'range ends exactly' );
is( $asset->slurp, $bytes, 'slurp reads the whole object after a ranged read' );
is( $asset->get_chunk($RANGE_BYTES), q{}, 'slurp preserves the HTTP range' );
lives_ok { $storage->write_object( 'binary', $bytes ) }
'identical retry reuses immutable object';
throws_ok { $storage->write_object( 'binary', 'changed' ) }
qr/different[ ]bytes/msx, 'a collision cannot overwrite another file';
throws_ok {
    $schema->txn_do(
        sub {
            $storage->write_object( 'rollback', 'not committed' );
            die "rollback\n";
        }
    )
}
qr/rollback/msx, 'transaction interrupted';
ok( !$storage->exists_object('rollback'), 'no object survives rollback' );

# A real file over 100 MiB: source, database and playback never require a
# scalar of that size. Its first and last bytes are checked independently.
my $file   = tempfile;
my $handle = $file->open('>');
binmode $handle or croak 'cannot set binary fixture mode';
for ( 1 .. $LARGE_FILE_MIB ) {
    print {$handle} ( 'v' x $mib ) or croak 'cannot write large fixture';
}
print {$handle} 'end' or croak 'cannot write fixture tail';
close $handle         or croak 'cannot close large fixture';
my $source = GPForum::Service::Attachment::Source->new(
    asset => Mojo::Asset::File->new( path => "$file" ) );
$storage->write_source( 'large-video', $source, $source->checksum );
is(
    $storage->object_info('large-video')->{byte_size},
    $LARGE_FILE_MIB * $mib + $EXPECTED_CHUNKS,
    'file larger than 100 MiB stored'
);
is( $storage->asset_for('large-video')->get_chunk( $LARGE_FILE_MIB * $mib ),
    'end', 'tail sought without loading video' );

my $ids = GPForum::Infrastructure::Id->new;
my ( $owner, $staff ) = ( $ids->uuid, $ids->uuid );
for my $pair ( [ $owner, 'owner' ], [ $staff, 'staff' ] ) {
    $dbh->do(
q{INSERT INTO users(id, username, display_name, email_normalized, password_hash, status) VALUES (?, ?, ?, ?, 'x', 'active')},
        undef,
        $pair->[0],
        $pair->[1],
        $pair->[1],
        $pair->[1] . '\@example.org'
    );
}
my $review =
  GPForum::Service::Attachment::ContentReview->new( schema => $schema );
my $store    = GPForum::Service::Attachment::Store->new( schema => $schema );
my $pipeline = GPForum::Service::Attachment::UploadPipeline->new(
    storage => $storage,
    store   => $store,
    review  => $review,
);
my $uploaded = $pipeline->upload_and_link(
    {
        actor_user_id     => $owner,
        original_filename => 'episode.mp3',
        content           => $ID3_HEADER . 'episode',
        source_kind       => 'original',
        rights_confirmed  => 1,
    }
);
ok( $uploaded->{ok}, 'attested episode accepted for review' );
my $id = $uploaded->{attachment}{attachment_id};
is(
    $dbh->selectrow_array(
        'SELECT state FROM attachments WHERE attachment_id = ?',
        undef, $id
    ),
    'quarantined',
    'clean scan alone cannot publish held media'
);
is(
    $review->decide(
        {
            attachment_id => $id,
            actor_user_id => $owner,
            decision      => 'approved',
            reason        => 'mine'
        }
    )->{status},
    'refused',
    'author cannot approve own upload'
);
is(
    $review->decide(
        {
            attachment_id => $id,
            actor_user_id => $staff,
            decision      => 'approved',
            reason        => 'Source and content reviewed'
        }
    )->{status},
    'ok',
    'independent staff approval'
);
is(
    $dbh->selectrow_array(
        'SELECT state FROM attachments WHERE attachment_id = ?',
        undef, $id
    ),
    'available',
    'only reviewed and clean content is public'
);
my $duplicate = $pipeline->upload_and_link(
    {
        actor_user_id     => $owner,
        original_filename => 'duplicate.mp3',
        content           => $ID3_HEADER . 'episode',
        source_kind       => 'original',
        rights_confirmed  => 1
    }
);
my $duplicate_id = $duplicate->{attachment}{attachment_id};
is(
    $review->decide(
        {
            attachment_id => $duplicate_id,
            actor_user_id => $staff,
            decision      => 'approved',
            reason        => 'Original verified'
        }
    )->{status},
    'ok',
    'second copy independently approved before a later rejection'
);

is(
    $review->decide(
        {
            attachment_id => $id,
            actor_user_id => $staff,
            decision      => 'rejected',
            reason        => 'Inappropriate content'
        }
    )->{status},
    'ok',
    'staff can withdraw published content'
);
is(
    $dbh->selectrow_array(
        'SELECT state FROM attachments WHERE attachment_id = ?', undef,
        $duplicate_id
    ),
    'quarantined',
    'withdrawal blocks every existing exact copy'
);
$dbh->do( q{UPDATE attachments SET state = 'available' WHERE attachment_id = ?},
    undef, $duplicate_id );
is(
    $dbh->selectrow_array(
        'SELECT state FROM attachments WHERE attachment_id = ?', undef,
        $duplicate_id
    ),
    'quarantined',
    'native guard prevents a stale approved copy reopening'
);

ok( !$review->validate_checksum( $uploaded->{attachment}{checksum} )->{ok},
    'rejected checksum blocks exact reupload' );
is(
    $review->decide(
        {
            attachment_id => $id,
            actor_user_id => $staff,
            decision      => 'approved',
            reason        => 'retry'
        }
    )->{status},
    'refused',
    'rejection cannot be reopened by a stale approval'
);
my $scan = $store->record_scan(
    {
        attachment_id => $id,
        actor_id      => 'scanner',
        scan_status   => 'clean',
        scan_engine   => 'test'
    }
);
is(
    $dbh->selectrow_array(
        'SELECT state FROM attachments WHERE attachment_id = ?',
        undef, $id
    ),
    'quarantined',
    'late clean scan cannot undo rejection'
);
is(
    $dbh->selectrow_array(
q{SELECT count(*) FROM audit_log WHERE target_id = ? AND action LIKE 'attachment.content.%'},
        undef,
        $id
    ),
    2,
    'approval and withdrawal both audited'
);
my $avatar_rows =
  GPForum::Service::Community::AvatarStore->new( schema => $schema );
my $image_tool = GPForum::Test::ImageTool->new;
my $avatars    = GPForum::Service::Community::Avatars->new(
    store       => $avatar_rows,
    attachments => $store,
    pipeline    => $pipeline,
    storage     => $storage,
    image_tool  => $image_tool,
);
is(
    $avatars->upload(
        {
            user_id          => $owner,
            content          => $image_tool->png( $PHOTO_SIDE, $PHOTO_SIDE ),
            source_kind      => 'original',
            rights_confirmed => 1
        }
    )->{status},
    'checking',
    'profile picture held until independent review'
);
my $avatar_id = $avatar_rows->status($owner)->{pending_attachment_id};
is(
    $review->decide(
        {
            attachment_id => $avatar_id,
            actor_user_id => $staff,
            decision      => 'approved',
            reason        => 'Original photo verified'
        }
    )->{status},
    'ok',
    'profile original approved'
);
is( $avatars->process($avatar_id)->{status},
    'shown', 'approved profile picture cropped and shown' );
my $avatar_key = $dbh->selectrow_array(
    'SELECT object_key FROM attachments WHERE attachment_id = ?',
    undef, $avatar_id );
ok( $storage->object_info($avatar_key),
    'profile original lives in PostgreSQL' );

for my $side ( $AVATAR_SMALL, $AVATAR_MIDDLE, $AVATAR_LARGE ) {
    my $key = $avatar_rows->image( $owner, $side )->{object_key};
    ok( $storage->object_info($key),
        "$side pixel profile variant lives in PostgreSQL" );
}

my $filesystem = GPForum::Service::Attachment::FilesystemStorage->new(
    root => tempdir( CLEANUP => 1 ) );
my $legacy_pipeline = GPForum::Service::Attachment::UploadPipeline->new(
    storage => $filesystem,
    store   => $store
);
my $legacy_file = $legacy_pipeline->upload_and_link(
    {
        actor_user_id     => $owner,
        original_filename => 'legacy.txt',
        content           => 'legacy original'
    }
);
my $legacy_id  = $legacy_file->{attachment}{attachment_id};
my $legacy_key = $legacy_file->{attachment}{object_key};
$filesystem->write_object( "$legacy_key-avatar-64", 'legacy variant' );
$store->add_variant(
    {
        attachment_id => $legacy_id,
        object_key    => "$legacy_key-avatar-64",
        media_type    => 'image/png',
        byte_size     => length('legacy variant'),
        variant_type  => 'avatar_64'
    }
);
my $import = GPForum::Service::Attachment::LegacyImport->new(
    storage    => $storage,
    filesystem => $filesystem
);
is( $import->run(0)->{checked},
    2, 'import checks legacy original and profile variant' );
ok( !$storage->object_info($legacy_key), 'validation alone writes no bytes' );
is( $import->run(1)->{imported}, 2, 'original and derived bytes imported' );
is(
    $storage->read_object($legacy_key),
    'legacy original',
    'import preserves original bytes'
);
is(
    $storage->read_object("$legacy_key-avatar-64"),
    'legacy variant',
    'import preserves profile variant'
);
is( $import->run(1)->{imported}, 0, 'completed import is safely repeatable' );
ok(
    $filesystem->exists_object($legacy_key),
    'legacy copy retained for recovery'
);

$dbh->do( 'DELETE FROM attachment_variants WHERE attachment_id = ?',
    undef, $legacy_id );
ok(
    !$storage->object_info("$legacy_key-avatar-64"),
    'deleting variant metadata removes its PostgreSQL bytes'
);
$dbh->do( 'DELETE FROM attachments WHERE attachment_id = ?', undef,
    $legacy_id );
ok( !$storage->object_info($legacy_key),
    'deleting attachment metadata cascades to original bytes' );

$storage->delete_object('binary');
is(
    $dbh->selectrow_array(
q{SELECT count(*) FROM attachment_object_chunks WHERE object_key = 'binary'}
    ),
    0,
    'object deletion cascades through all chunks'
);
done_testing();

1;
