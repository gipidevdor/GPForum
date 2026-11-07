# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use Test::More;
use lib 'lib';
use GPForum::Config;
use GPForum::Service::Attachment::ContentReview;
use GPForum::Service::Attachment::Validator;

our $VERSION = '0.001';
const my $ID3_HEADER         => pack 'H*', '49443304000000000000';
const my $NUL_BYTE           => pack 'C',  0;
const my $MIN_MEDIA_MIB      => 100;
const my $OVER_MIN_MEDIA_MIB => 101;
const my $KIB                => 1_024;
const my $MP4_HEADER_BYTES   => 24;
const my $FILE_LIMIT_MIB     => 25;
const my $MAX_MEDIA_MIB      => 250;
const my $OVERSIZE_MEDIA_MIB => 251;
const my $OVERSIZE_FILE_MIB  => 26;
const my $BELOW_MEDIA_MIB    => 99;
my $validator = GPForum::Service::Attachment::Validator->new;
my $mib       = $KIB * $KIB;
my $mp4 =
  pack( 'N', $MP4_HEADER_BYTES ) . 'ftypisom' . pack( 'N', 0 ) . 'isommp42';
my $m4a =
  pack( 'N', $MP4_HEADER_BYTES ) . 'ftypM4A ' . pack( 'N', 0 ) . 'M4A mp42';
is( $validator->sniff_media_type($mp4),
    'video/mp4', 'MP4 identified from bytes' );
is( $validator->sniff_media_type($m4a), 'audio/mp4',
    'M4A identified as audio' );
is( $validator->sniff_media_type($ID3_HEADER),
    'audio/mpeg', 'MP3 ID3 header recognized' );
is(
    $validator->sniff_media_type(
        'OggS' . $NUL_BYTE x $MP4_HEADER_BYTES . 'OpusHead'
    ),
    'audio/ogg',
    'Opus podcast recognized'
);
is( $validator->sniff_media_type( pack( 'N', $MIN_MEDIA_MIB ) . 'ftypisom' ),
    'application/octet-stream', 'truncated MP4 refused' );

is(
    $validator->sniff_media_type(
            pack( 'N', $MP4_HEADER_BYTES )
          . 'ftypXXXX'
          . pack( 'N', 0 )
          . 'M4AXXXXX'
    ),
    'application/octet-stream',
    'a brand prefix cannot claim MP4 audio'
);
is(
    $validator->sniff_media_type(
        pack( 'N', $MP4_HEADER_BYTES ) . 'ftypisom' . 'M4A ' . 'isommp42'
    ),
    'video/mp4',
    'minor-version bytes are not interpreted as a media brand'
);

for my $case (
    [ 'video/mp4',       $MIN_MEDIA_MIB,      1 ],
    [ 'video/mp4',       $MAX_MEDIA_MIB,      1 ],
    [ 'audio/mpeg',      $MAX_MEDIA_MIB,      1 ],
    [ 'video/mp4',       $OVERSIZE_MEDIA_MIB, 0 ],
    [ 'image/png',       $FILE_LIMIT_MIB,     1 ],
    [ 'image/png',       $OVERSIZE_FILE_MIB,  0 ],
    [ 'application/pdf', $OVERSIZE_FILE_MIB,  0 ],
  )
{
    my ( $type, $size, $expected ) = @{$case};
    my $result = $validator->validate_upload(
        {
            owner_user_id     => 'owner',
            original_filename => 'media.bin',
            media_type        => $type,
            byte_size         => $size * $mib,
            checksum          => 'abcd',
        }
    );
    is( $result->{ok}, $expected, "$type at $size MiB" );
}
my $limited =
  GPForum::Service::Attachment::Validator->new(
    media_max_bytes => $MIN_MEDIA_MIB * $mib );
ok(
    !$limited->validate_upload(
        {
            owner_user_id     => 'owner',
            original_filename => 'clip.mp4',
            media_type        => 'video/mp4',
            byte_size         => $OVER_MIN_MEDIA_MIB * $mib,
            checksum          => 'abcd',
        }
    )->{ok},
    'configured 100 MiB media limit enforced'
);
ok( GPForum::Config->new( media_max_mib => $BELOW_MEDIA_MIB )->problems->@*,
    'configuration rejects a smaller limit' );
ok(
    GPForum::Config->new( media_max_mib => $OVERSIZE_MEDIA_MIB )->problems->@*,
    'configuration rejects above storage limit'
);

my $review = GPForum::Service::Attachment::ContentReview->new(
    schema       => bless( {}, 'TestSchema' ),
    source_hosts => ['media.example.org'],
);
for my $case (
    [
        { source_kind => 'original', rights_confirmed => 1 },
        1, 'attested original'
    ],
    [ { source_kind      => 'original' }, 0, 'missing rights confirmation' ],
    [ { rights_confirmed => 1 },          0, 'missing source' ],
    [
        {
            source_kind      => 'authorized',
            rights_confirmed => 1,
            source_url       => 'https://media.example.org/clip'
        },
        1,
        'authorized exact host'
    ],
    [
        {
            source_kind      => 'authorized',
            rights_confirmed => 1,
            source_url       => 'https://media.example.org.attacker.test/clip'
        },
        0,
        'host suffix spoof'
    ],
    [
        {
            source_kind      => 'authorized',
            rights_confirmed => 1,
            source_url       => 'https://media.example.org@attacker.test/clip'
        },
        0,
        'userinfo spoof'
    ],
    [
        {
            source_kind      => 'authorized',
            rights_confirmed => 1,
            source_url       => 'http://media.example.org/clip'
        },
        0,
        'unencrypted source'
    ],
    [
        {
            source_kind      => 'authorized',
            rights_confirmed => 1,
            source_url       => 'https://media.example.org:8443/clip'
        },
        0,
        'unauthorized port'
    ],
  )
{
    is( $review->validate_source( $case->[0] )->{ok}, $case->[1], $case->[2] );
}
done_testing();

1;
