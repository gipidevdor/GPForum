# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Carp qw(croak);
use Const::Fast;
use Digest::SHA;
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Test::More;
use Test::Mojo;
use lib 'lib', 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Command::AdminBootstrap;
use GPForum::Test::GuiDriver;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;
our $VERSION = '0.001';
const my $SHA_BITS            => 256;
const my $WAV_CONTAINER_BYTES => 16;
const my $WAV_DATA_BYTES      => 16_000;
const my $WAV_SAMPLE_RATE     => 8_000;
const my $WAV_BITS_PER_SAMPLE => 16;
const my $WAV_RIFF_OVERHEAD   => 36;
const my $MIB                 => 1_048_576;
const my $VIDEO_MIB           => 100;
const my $MP4_HEADER          => 24;
const my $HTTP_OK             => 200;
const my $HTTP_PARTIAL        => 206;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'requires PostgreSQL';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_ANTIVIRUS}                 = 'none';
my $dbh   = $database->dbh;
my $staff = seed_id( user => 2 );
GPForum::Test::PostgresHarness::quietly(
    sub {
        return GPForum::Command::AdminBootstrap->new(
            schema => $database->schema )->run( 'grant', '--user-id', $staff );
    }
);
my ( $post, $owner, $thread ) = $dbh->selectrow_array(
q{SELECT p.post_id,p.author_user_id,p.thread_id FROM posts p JOIN threads t USING(thread_id) JOIN categories c USING(category_id) JOIN spaces s USING(space_id) WHERE p.deleted_at IS NULL AND p.moderation_state='visible' AND t.moderation_state='visible' AND t.visibility='public' AND c.visibility='public' AND s.visibility='public' AND p.author_user_id<>? LIMIT 1},
    undef, $staff
);
my $t   = Test::Mojo->new('GPForum');
my $gui = GPForum::Test::GuiDriver->new( test => $t );
$gui->install_session;
my $upload = '/p/' . $post . '/attachments';
my $root   = path( tempdir( CLEANUP => 1 ) );
my $video  = $root->child('hundred-mib.mp4');
open my $handle, '>:raw', "$video"
  or croak 'cannot create bounded video fixture';
print {$handle} pack( 'N', $MP4_HEADER )
  . 'ftypisom'
  . pack( 'N', 0 )
  . 'isommp42'
  or croak 'cannot write fixture header';
truncate $handle, $VIDEO_MIB * $MIB or croak 'cannot size fixture';
close $handle or croak 'cannot close video fixture';
open my $digest_input, '<:raw', "$video" or croak 'cannot hash fixture';
my $digest = Digest::SHA->new($SHA_BITS)->addfile($digest_input)->hexdigest;
close $digest_input or croak 'cannot close digest input';
$gui->actor($owner)->visit($upload)->submit(
    'form[enctype="multipart/form-data"]',
    {
        source_kind      => 'original',
        rights_confirmed => '1',
        attachment       => {
            file         => "$video",
            filename     => 'hundred-mib.mp4',
            content_type => 'video/mp4'
        }
    }
);
my $stored = $dbh->selectrow_hashref(
q{SELECT a.attachment_id,a.object_key,o.byte_size,o.checksum,o.complete FROM attachments a JOIN attachment_objects o USING(object_key) WHERE a.owner_user_id=? AND a.original_filename='hundred-mib.mp4'},
    undef, $owner
);
ok( $stored, 'GUI accepts a real 100 MiB multipart upload into PostgreSQL' );
is(
    $stored->{byte_size},
    $VIDEO_MIB * $MIB,
    'PostgreSQL retains the complete 100 MiB object'
);
is( $stored->{checksum}, $digest,
    'the stored object digest matches the uploaded file' );
is(
    $dbh->selectrow_array(
'SELECT sum(octet_length(data)) FROM attachment_object_chunks WHERE object_key=?',
        undef,
        $stored->{object_key}
    ),
    $VIDEO_MIB * $MIB,
    'all 100 MiB are stored as database chunks'
);
ok( $stored->{complete},
    'the object becomes complete after its chunks are stored' );
$t->head_ok( '/attachments/' . $stored->{attachment_id} . '/download' )
  ->status_is($HTTP_OK);

# A prerecorded WAV container, sufficient to exercise the upload policy and
# native player. Codec playback itself belongs to browser/device testing.
my $audio = $root->child('recorded-podcast.wav');
$audio->spew(
        'RIFF'
      . pack( 'V', $WAV_DATA_BYTES + $WAV_RIFF_OVERHEAD )
      . 'WAVEfmt '
      . pack( 'VvvVVvv',
        $WAV_CONTAINER_BYTES, 1,               1,
        $WAV_SAMPLE_RATE,     $WAV_DATA_BYTES, 2,
        $WAV_BITS_PER_SAMPLE )
      . 'data'
      . pack( 'V', $WAV_DATA_BYTES )
      . ( "\0" x $WAV_DATA_BYTES )
);
$gui->visit($upload)->submit(
    'form[enctype="multipart/form-data"]',
    {
        source_kind      => 'original',
        rights_confirmed => '1',
        attachment       => {
            file         => "$audio",
            filename     => 'recorded-podcast.wav',
            content_type => 'audio/wav'
        }
    }
);
my ($episode) = $dbh->selectrow_array(
q{SELECT attachment_id FROM attachments WHERE owner_user_id=? AND original_filename='recorded-podcast.wav'},
    undef, $owner
);
ok( $episode, 'GUI stores a prerecorded internal podcast episode' );
$gui->visit( '/t/' . $thread );
$t->element_exists('audio[controls] source[type="audio/wav"]');
$t->get_ok( '/attachments/' . $episode . '/download' )
  ->status_is($HTTP_OK)
  ->content_is( $audio->slurp );
$t->get_ok( '/attachments/'
      . $stored->{attachment_id}
      . '/download' => { Range => 'bytes=0-23' } )
  ->status_is($HTTP_PARTIAL)
  ->content_is(
    pack( 'N', $MP4_HEADER ) . 'ftypisom' . pack( 'N', 0 ) . 'isommp42' );
$gui->visit( '/t/' . $thread );
$t->element_exists('video[controls] source[type="video/mp4"]');
done_testing;
1;
