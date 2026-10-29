# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use English    qw(-no_match_vars);
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Config;
use GPForum::Infrastructure::ImageBytes;
use GPForum::Infrastructure::ImageTool;
use GPForum::Infrastructure::ImageTool::Sips;
use GPForum::Infrastructure::ImageTool::Vips;
use GPForum::Service::Attachment::MediaProcessor;
use GPForum::Service::Community::AvatarStore;
use GPForum::Service::Community::Avatars;
use GPForum::Test::AvatarDouble;
use GPForum::Test::ImageTool;
use GPForum::Test::RecordingFunctions;
use GPForum::Web::ForumAccess;

our $VERSION = '0.001';

const my $USER          => '6f1c2f1e-0f6a-4d55-9d3a-2b0d7f9a1c11';
const my $ATTACHMENT    => '7a2d3e4f-1b2c-4d5e-8f90-a1b2c3d4e5f6';
const my $WIDTH         => 300;
const my $HEIGHT        => 200;
const my $WEBP_WIDTH    => 1_000;
const my $WEBP_HEIGHT   => 750;
const my $SMALL         => 64;
const my $MIDDLE        => 128;
const my $LARGE         => 256;
const my $NOT_A_SIDE    => 99;
const my $TOO_WIDE      => 8_001;
const my $CHURN         => 10;
const my $LONG_REASON   => 501;
const my $EXECUTABLE    => oct '755';
const my $MEGABYTE      => 1_024 * 1_024;
const my $FIVE_MB       => 5 * $MEGABYTE;
const my $SIX_MB        => 6 * $MEGABYTE;
const my $TIMEOUT       => 1;
const my $BASELINE      => 0xc0;
const my $PROGRESSIVE   => 0xc2;
const my $HUFFMAN_TABLE => 0xc4;
const my $IN_A_CHUNK    => 18;
const my $IEND_LENGTH   => 12;
const my $FOURTEEN      => 14;
const my $BYTE          => 8;
const my $SECOND_BYTE   => 16;
const my $LOW_BYTE      => 0xff;
const my $PNG           => pack 'H*', '89504e470d0a1a0a';
const my $ZEROS         => pack 'x8';
const my $VP8_START     => pack 'H*', '0000009d012a';
const my $VP8L_SIGN     => pack 'H*', '2f';
const my $VP8X_FLAGS    => pack 'x4';
const my @SIDES         => ( $SMALL, $MIDDLE, $LARGE );

# A fake vipsthumbnail: SOURCE --size NxN --smartcrop centre -o OUT, which
# behaves as its name says.
const my $FAKE_PROGRAM => <<'PERL';
use v5.40;
use Compress::Zlib ();
my $behaviour = '__BEHAVIOUR__';
my ($side) = $ARGV[2] =~ /\A(\d+)x/;
my $out = $ARGV[-1];
exit 1 if $behaviour eq 'fails';
exit 0 if $behaviour eq 'nothing';
kill 'KILL', $$ if $behaviour eq 'crashes';
sleep 5 if $behaviour eq 'sleeps';
$side += 1 if $behaviour eq 'wrong_size';
sub chunk ($type, $data) {
    return pack('N', length $data) . $type . $data
      . pack('N', Compress::Zlib::crc32($type . $data));
}
my $row = "\0" . ("\x10\x20\x30" x $side);
open my $fh, '>:raw', $out or exit 2;
print {$fh} "\x89PNG\x0d\x0a\x1a\x0a",
  chunk('IHDR', pack('N N C C C C C', $side, $side, 8, 2, 0, 0, 0)),
  chunk('tEXt', "Software\0kept by the tool"),
  chunk('IDAT', Compress::Zlib::compress($row x $side)), chunk('IEND', '');
close $fh;
exit 0;
PERL

my $bytes = GPForum::Infrastructure::ImageBytes->new;

subtest 'an image\'s size, from its header alone'  => \&_dimensions;
subtest 'a PNG keeps only its picture'             => \&_plain_png;
subtest 'the tools\' commands'                     => \&_commands;
subtest 'the tool the system installed'            => \&_system_tool;
subtest 'squares through a program'                => \&_squares;
subtest 'macOS\'s sips crops for real'             => \&_sips;
subtest 'an upload is refused before it is stored' => \&_refusals;
subtest 'the media pipeline hands a picture over'  => \&_media_pipeline;
subtest 'the store refuses before the database'    => \&_store_refusals;
subtest 'avatar writes are limited like churn'     => \&_limits;

done_testing();

sub _dimensions {
    my $size = { width => $WIDTH, height => $HEIGHT };
    is_deeply(
        $bytes->dimensions(
            GPForum::Test::ImageTool->png( $WIDTH, $HEIGHT ), 'image/png'
        ),
        $size, 'a PNG'
    );
    is_deeply(
        $bytes->dimensions(
            'GIF89a' . pack( 'v v', $WIDTH, $HEIGHT ) . $ZEROS, 'image/gif'
        ),
        $size, 'a GIF'
    );
    is_deeply(
        $bytes->dimensions(
            GPForum::Test::ImageTool->jpeg( $BASELINE, $WIDTH, $HEIGHT ),
            'image/jpeg'
        ),
        $size,
        'a baseline JPEG'
    );
    is_deeply(
        $bytes->dimensions(
            GPForum::Test::ImageTool->jpeg( $PROGRESSIVE, $WIDTH, $HEIGHT ),
            'image/jpeg'
        ),
        $size,
        'a progressive JPEG'
    );
    is(
        $bytes->dimensions(
            GPForum::Test::ImageTool->jpeg( $HUFFMAN_TABLE, $WIDTH, $HEIGHT ),
            'image/jpeg'
        ),
        undef,
        'a Huffman table is not a frame'
    );
    my $webp = { width => $WEBP_WIDTH, height => $WEBP_HEIGHT };
    for my $case (
        [ 'a lossy WebP',     _webp_lossy( $WEBP_WIDTH, $WEBP_HEIGHT ) ],
        [ 'a lossless WebP',  _webp_lossless( $WEBP_WIDTH, $WEBP_HEIGHT ) ],
        [ 'an extended WebP', _webp_extended( $WEBP_WIDTH, $WEBP_HEIGHT ) ],
      )
    {
        is_deeply( $bytes->dimensions( $case->[1], 'image/webp' ),
            $webp, $case->[0] );
    }
    is( $bytes->dimensions( "$PNG short", 'image/png' ),
        undef, 'a truncated header' );
    is(
        $bytes->dimensions(
            GPForum::Test::ImageTool->png( 1, 1 ), 'image/gif'
        ),
        undef,
        'bytes that are not the type named'
    );
    is( $bytes->dimensions( 'hello', 'text/plain' ), undef, 'not an image' );
    is( $bytes->dimensions( undef,   'image/png' ),  undef, 'nothing' );

    return;
}

sub _plain_png {
    my $tagged = GPForum::Test::ImageTool->png( 2, 2, comment => 'secret' );
    my $plain  = $bytes->plain_png($tagged);
    ok( $plain, 'a well-formed PNG is rewritten' );
    unlike( $plain, qr/secret/msx, 'without its text chunk' );
    is(
        $plain,
        GPForum::Test::ImageTool->png( 2, 2 ),
        'and with every chunk that draws it'
    );
    my $corrupt = $tagged;
    substr $corrupt, $IN_A_CHUNK, 1, 'X';
    is( $bytes->plain_png($corrupt), undef, 'a chunk that fails its CRC' );
    is( $bytes->plain_png( substr $tagged, 0, -$IEND_LENGTH ),
        undef, 'no IEND' );
    is( $bytes->plain_png('GIF89a'), undef, 'not a PNG' );

    return;
}

sub _commands {
    my $vips =
      GPForum::Infrastructure::ImageTool::Vips->new( program => '/bin/vt' );
    is_deeply(
        [ $vips->commands( '/d/source.png', '/d', {}, [ $SMALL, $MIDDLE ] ) ],
        [
            [
                '/bin/vt',     '/d/source.png',
                '--size',      '64x64',
                '--smartcrop', 'centre',
                '-o',          '/d/avatar-64.png'
            ],
            [
                '/bin/vt',     '/d/source.png',
                '--size',      '128x128',
                '--smartcrop', 'centre',
                '-o',          '/d/avatar-128.png'
            ],
        ],
        'vipsthumbnail crops each side about the centre'
    );
    is( $vips->engine, 'vips', 'named vips' );
    my $sips =
      GPForum::Infrastructure::ImageTool::Sips->new( program => '/usr/bin/s' );
    is_deeply(
        [
            $sips->commands(
                '/d/source.jpg',                        '/d',
                { width => $WIDTH, height => $HEIGHT }, [$SMALL]
            )
        ],
        [
            [
                '/usr/bin/s', '-s',    'format', 'png',
                '-c',         $HEIGHT, $HEIGHT,  '/d/source.jpg',
                '--out',      '/d/square.png'
            ],
            [
                '/usr/bin/s',    '-z',    $SMALL, $SMALL,
                '/d/square.png', '--out', '/d/avatar-64.png'
            ],
        ],
        'sips crops the largest centred square, then resamples it'
    );
    is( $sips->engine, 'sips', 'named sips' );

    return;
}

sub _system_tool {
    my $missing = GPForum::Infrastructure::ImageTool->system_tool(
        _os( { vips => ['/nonexistent/vipsthumbnail'], sips => undef } ) );
    is( $missing->engine, 'vips', 'without one, an unavailable vips' );
    ok( !$missing->available, 'that is not available' );
    _throws_unavailable(
        sub { $missing->squares( { media_type => 'image/png' }, [$SMALL] ) },
        'it squares nothing' );

    my $program = _program('ok');
    my $found   = GPForum::Infrastructure::ImageTool->system_tool(
        _os( { vips => [ '/nonexistent/vipsthumbnail', $program ] } ) );
    is( $found->program, $program, 'the first one installed is taken' );
    my $sips = GPForum::Infrastructure::ImageTool->system_tool(
        _os( { vips => [], sips => $program } ) );
    is( $sips->engine, 'sips', 'macOS\'s sips when vips is missing' );

    is(
        GPForum::Infrastructure::ImageTool->from_config(
            GPForum::Config->from_environment( { GPFORUM_ENV => 'test' } )
        ),
        undef,
        'the test environment assumes no tool'
    );
    is(
        GPForum::Config->from_environment( {} )->image_tool,
        'system',
        'elsewhere the system\'s is used'
    );
    is(
        GPForum::Config->from_environment(
            { GPFORUM_ENV => 'test', GPFORUM_IMAGE_TOOL => 'system' }
        )->image_tool,
        'system',
        'and the operator may name it'
    );

    return;
}

sub _squares {
    my $image = _image();
    my $tool  = GPForum::Infrastructure::ImageTool::Vips->new(
        program => _program('ok') );
    my $squares = $tool->squares( $image, [@SIDES] );
    is_deeply( [ sort { $a <=> $b } keys %{$squares} ],
        [@SIDES], 'one square a side' );
    is_deeply(
        $bytes->dimensions( $squares->{$MIDDLE}, 'image/png' ),
        { width => $MIDDLE, height => $MIDDLE },
        'of the side asked for'
    );
    unlike(
        $squares->{$SMALL},
        qr/kept[ ]by[ ]the[ ]tool/msx,
        'with the tool\'s metadata stripped'
    );

    for my $case (
        [ 'wrong_size', 'a square of another size' ],
        [ 'fails',      'a tool that exits with an error' ],
        [ 'nothing',    'a tool that writes nothing' ],
        [ 'crashes',    'a tool killed by a signal' ],
      )
    {
        my ( $behaviour, $label ) = @{$case};
        my $failing = GPForum::Infrastructure::ImageTool::Vips->new(
            program => _program($behaviour) );
        is( $failing->squares( $image, [$SMALL] ),
            undef, "$label reads nothing" );
    }
    my $slow = GPForum::Infrastructure::ImageTool::Vips->new(
        program         => _program('sleeps'),
        timeout_seconds => $TIMEOUT
    );
    _throws_unavailable( sub { $slow->squares( $image, [$SMALL] ) },
        'a tool that outruns its time' );
    _throws_unavailable(
        sub {
            $tool->squares( { %{$image}, media_type => 'text/plain' },
                [$SMALL] );
        },
        'text is no image'
    );

    return;
}

sub _sips {
    if ( !-x '/usr/bin/sips' ) {
        plan skip_all => 'no sips on this system';
    }

    my $tool = GPForum::Infrastructure::ImageTool::Sips->new(
        program => '/usr/bin/sips' );
    my $squares = $tool->squares( _image(), [@SIDES] );
    for my $side (@SIDES) {
        is_deeply(
            $bytes->dimensions( $squares->{$side}, 'image/png' ),
            { width => $side, height => $side },
            "a $side pixel square"
        );
    }
    is(
        $tool->squares(
            {
                content    => "$PNG not really",
                media_type => 'image/png',
                width      => 1,
                height     => 1,
            },
            [$SMALL]
        ),
        undef,
        'and nothing from bytes that are no picture'
    );

    return;
}

sub _refusals {
    my $pipeline = GPForum::Test::AvatarDouble->new;
    my $avatars  = _avatars( $pipeline, GPForum::Test::ImageTool->new );
    my @cases    = (
        [ 'missing', { user_id => $USER } ],
        [ 'missing', { user_id => $USER, content => q{} } ],
        [
            'too_large', { user_id => $USER, content => $PNG . pack "x$SIX_MB" }
        ],
        [
            'too_large',
            {
                user_id => $USER,
                upload  => GPForum::Test::AvatarDouble->new( size => $SIX_MB )
            }
        ],
        [ 'not_image',  { user_id => $USER, content => "%PDF-1.4\n" } ],
        [ 'not_image',  { user_id => $USER, content => "words\n" } ],
        [ 'unreadable', { user_id => $USER, content => "$PNG broken" } ],
        [
            'too_many_pixels',
            {
                user_id => $USER,
                content => GPForum::Test::ImageTool->png_start( $TOO_WIDE, 1 )
            }
        ],
    );
    for my $case (@cases) {
        my ( $status, $input ) = @{$case};
        is( $avatars->upload($input)->{status}, $status, "refused: $status" );
    }
    is( scalar @{ $pipeline->calls }, 0, 'the pipeline was never asked' );
    my $uninstalled =
      _avatars( $pipeline, GPForum::Test::ImageTool->new( installed => 0 ) );
    is(
        $uninstalled->upload(
            {
                user_id => $USER,
                content => GPForum::Test::ImageTool->png( 1, 1 )
            }
        )->{status},
        'unavailable',
        'no installed tool, no picture'
    );
    is( _avatars( $pipeline, undef )->available, 0, 'nor without one' );
    is( $avatars->maximum_bytes, $FIVE_MB,          'five megabytes at most' );

    return;
}

sub _media_pipeline {
    my $attachments = GPForum::Test::AvatarDouble->new;
    my $processor   = GPForum::Service::Attachment::MediaProcessor->new(
        avatars => GPForum::Test::AvatarDouble->new(
            answer => { ok => 1, status => 'shown' }
        ),
        storage => GPForum::Test::AvatarDouble->new,
        store   => $attachments,
    );
    is_deeply(
        $processor->process($ATTACHMENT),
        { ok => 1, status => 'shown', avatar => 1 },
        'a picture is the avatars\''
    );
    is( scalar @{ $attachments->variants }, 0, 'and gets no thumbnail' );

    my $other = GPForum::Service::Attachment::MediaProcessor->new(
        avatars    => GPForum::Test::AvatarDouble->new,
        image_tool => GPForum::Test::ImageTool->new,
        storage    => GPForum::Test::AvatarDouble->new,
        store      => $attachments,
    );
    ok(
        $other->process($ATTACHMENT)->{variant},
        'any other image gets its thumbnail'
    );
    is( $attachments->variants->[0]{variant_type}, 'thumbnail', 'as it did' );

    return;
}

sub _store_refusals {
    my $functions = GPForum::Test::RecordingFunctions->new;
    my $store     = GPForum::Service::Community::AvatarStore->new(
        schema    => {},
        functions => $functions,
    );
    is( $store->offer( 'nope', $ATTACHMENT )->{status},
        'invalid', 'an offer by nobody' );
    is( $store->settle( $USER, 'nope', 'ready' )->{status},
        'invalid', 'a settlement of nothing' );
    is( $store->remove_own('nope')->{status},
        'not_found', 'a removal by nobody' );
    is_deeply(
        $store->remove_by_staff(
            {
                subject_user_id => $USER,
                attachment_id   => $ATTACHMENT,
                reason          => 'r' x $LONG_REASON,
            }
        ),
        { status => 'invalid', field => 'reason', attachment_ids => [] },
        'a reason over 500 characters'
    );
    is( $store->image( $USER, $NOT_A_SIDE ), undef, 'a side not kept' );
    is_deeply( $store->objects('nope'), [], 'objects of nobody' );
    is_deeply( $store->status('nope'),  {}, 'the status of nobody' );
    is( scalar @{ $functions->calls }, 0,     'nothing reached the database' );
    is( $store->reason("  why \n"),    'why', 'a reason is trimmed' );
    is_deeply( $store->sides, [@SIDES], 'three sides' );
    is( $store->variant_type($SMALL), 'avatar_64', 'kept as variants' );

    return;
}

sub _limits {
    my $access = GPForum::Web::ForumAccess->new;
    is( $access->write_limit_for('avatar.upload'), $CHURN, 'uploads' );
    is( $access->write_limit_for('avatar.remove'), $CHURN, 'removals' );
    ok( $access->requires_participation('avatar.upload'),
        'a suspended member uploads none' );
    ok( !$access->requires_participation('avatar.remove'),
        'but may remove theirs' );

    return;
}

sub _throws_unavailable ( $code, $label ) {
    my $thrown;
    try {
        $code->();
    }
    catch ($error) {
        $thrown = $error;
    };
    isa_ok( $thrown, 'GPForum::X::Unavailable', $label );

    return;
}

sub _image {
    return {
        content    => GPForum::Test::ImageTool->png( $WIDTH, $HEIGHT ),
        media_type => 'image/png',
        width      => $WIDTH,
        height     => $HEIGHT,
    };
}

sub _avatars ( $pipeline, $tool ) {
    return GPForum::Service::Community::Avatars->new(
        attachments => GPForum::Test::AvatarDouble->new,
        image_tool  => $tool,
        pipeline    => $pipeline,
        storage     => GPForum::Test::AvatarDouble->new,
        store       => GPForum::Test::AvatarDouble->new,
    );
}

sub _os ($packaging) {
    return GPForum::Test::AvatarDouble->new( packaging => $packaging );
}

sub _program ($behaviour) {
    my $program = path( tempdir( CLEANUP => 1 ), 'vipsthumbnail' );
    $program->spew( "#!$EXECUTABLE_NAME\n"
          . ( $FAKE_PROGRAM =~ s/__BEHAVIOUR__/$behaviour/rmsx ) );
    $program->chmod($EXECUTABLE);

    return "$program";
}

sub _webp ( $kind, $payload ) {
    my $chunk = $kind . pack( 'V', length $payload ) . $payload;

    return
        'RIFF'
      . pack( 'V', length($chunk) + length 'WEBP' ) . 'WEBP'
      . $chunk;
}

sub _webp_lossy ( $width, $height ) {
    return _webp( 'VP8 ',
        $VP8_START . pack( 'v v', $width, $height ) . $ZEROS );
}

sub _webp_lossless ( $width, $height ) {
    return _webp( 'VP8L',
            $VP8L_SIGN
          . pack( 'V', ( $width - 1 ) | ( ( $height - 1 ) << $FOURTEEN ) )
          . $ZEROS );
}

sub _webp_extended ( $width, $height ) {
    return _webp( 'VP8X',
        $VP8X_FLAGS . _three( $width - 1 ) . _three( $height - 1 ) . $ZEROS );
}

sub _three ($number) {
    return pack 'C3', $number & $LOW_BYTE, ( $number >> $BYTE ) & $LOW_BYTE,
      ( $number >> $SECOND_BYTE ) & $LOW_BYTE;
}

1;
