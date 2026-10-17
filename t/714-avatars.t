# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Compress::Zlib ();
use Const::Fast;
use English qw(-no_match_vars);
use File::Temp qw(tempdir);
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
use GPForum::Test::ImageTool;
use GPForum::Test::RecordingFunctions;
use GPForum::Web::ForumAccess;

our $VERSION = '0.001';

const my $USER         => '6f1c2f1e-0f6a-4d55-9d3a-2b0d7f9a1c11';
const my $ATTACHMENT   => '7a2d3e4f-1b2c-4d5e-8f90-a1b2c3d4e5f6';
const my $WIDTH        => 300;
const my $HEIGHT       => 200;
const my $WEBP_WIDTH   => 1_000;
const my $WEBP_HEIGHT  => 750;
const my $SMALL        => 64;
const my $MIDDLE       => 128;
const my $LARGE        => 256;
const my $TOO_WIDE     => 8_001;
const my $CHURN        => 10;
const my $LONG_REASON  => 501;
const my $EXECUTABLE   => oct '755';
const my $SIX_MB       => 6 * 1_024 * 1_024;
const my $TIMEOUT      => 1;
const my $PNG          => "\x89PNG\x0d\x0a\x1a\x0a";
const my @SIDES        => ( $SMALL, $MIDDLE, $LARGE );

# The doubles, defined before the tests run their attributes.
package _OS {
    use Mojo::Base -base, -signatures;

    has packaging => sub { return {} };

    sub image_tool_packaging ($self) { return $self->packaging; }
}

package _Recorder {
    use Mojo::Base -base, -signatures;

    has calls => sub { return [] };

    sub upload_and_link ( $self, $input ) {
        push @{ $self->calls }, $input;
        return { ok => 0, errors => {} };
    }
}

package _Upload {
    use Mojo::Base -base, -signatures;

    has size => 0;

    sub asset ($self) { die 'a file over the limit is never read'; }
}

package _Avatars {
    use Mojo::Base -base, -signatures;

    has 'answer';

    sub process ( $self, $attachment_id ) { return $self->answer; }
}

package _Storage {
    use Mojo::Base -base, -signatures;

    sub read_object ( $self, $key ) { return 'bytes'; }

    sub exists_object ( $self, $key ) { return 0; }

    sub write_object ( $self, $key, $content ) { return; }
}

package _Attachments {
    use Mojo::Base -base, -signatures;

    has variants => sub { return [] };

    sub find_attachment ( $self, $attachment_id ) {
        return {
            attachment_id => $attachment_id,
            media_type    => 'image/png',
            object_key    => 'key',
            state         => 'available',
        };
    }

    sub find_variant ( $self, $input ) { return undef; }

    sub add_variant ( $self, $input ) {
        push @{ $self->variants }, $input;
        return $input;
    }
}

package main;

my $bytes = GPForum::Infrastructure::ImageBytes->new;

subtest 'an image\'s size, from its header alone' => sub {
    is_deeply(
        $bytes->dimensions( GPForum::Test::ImageTool->png( $WIDTH, $HEIGHT ),
            'image/png' ),
        { width => $WIDTH, height => $HEIGHT },
        'a PNG'
    );
    is_deeply(
        $bytes->dimensions( 'GIF89a' . pack( 'v v', $WIDTH, $HEIGHT ) . "\0" x 8,
            'image/gif' ),
        { width => $WIDTH, height => $HEIGHT },
        'a GIF'
    );
    is_deeply( $bytes->dimensions( _jpeg( 0xc0, $WIDTH, $HEIGHT ), 'image/jpeg' ),
        { width => $WIDTH, height => $HEIGHT }, 'a baseline JPEG' );
    is_deeply( $bytes->dimensions( _jpeg( 0xc2, $WIDTH, $HEIGHT ), 'image/jpeg' ),
        { width => $WIDTH, height => $HEIGHT }, 'a progressive JPEG' );
    is( $bytes->dimensions( _jpeg( 0xc4, $WIDTH, $HEIGHT ), 'image/jpeg' ),
        undef, 'a Huffman table is not a frame' );
    is_deeply(
        $bytes->dimensions( _webp_lossy( $WEBP_WIDTH, $WEBP_HEIGHT ),
            'image/webp' ),
        { width => $WEBP_WIDTH, height => $WEBP_HEIGHT },
        'a lossy WebP'
    );
    is_deeply(
        $bytes->dimensions( _webp_lossless( $WEBP_WIDTH, $WEBP_HEIGHT ),
            'image/webp' ),
        { width => $WEBP_WIDTH, height => $WEBP_HEIGHT },
        'a lossless WebP'
    );
    is_deeply(
        $bytes->dimensions( _webp_extended( $WEBP_WIDTH, $WEBP_HEIGHT ),
            'image/webp' ),
        { width => $WEBP_WIDTH, height => $WEBP_HEIGHT },
        'an extended WebP'
    );
    is( $bytes->dimensions( "$PNG short", 'image/png' ),
        undef, 'a truncated header' );
    is( $bytes->dimensions( GPForum::Test::ImageTool->png( 1, 1 ), 'image/gif' ),
        undef, 'bytes that are not the type named' );
    is( $bytes->dimensions( 'hello', 'text/plain' ), undef, 'not an image' );
    is( $bytes->dimensions( undef, 'image/png' ), undef, 'nothing' );
};

subtest 'a PNG keeps only its picture' => sub {
    my $tagged = GPForum::Test::ImageTool->png( 2, 2, comment => 'secret' );
    my $plain  = $bytes->plain_png($tagged);
    ok( $plain, 'a well-formed PNG is rewritten' );
    unlike( $plain, qr/secret/msx, 'without its text chunk' );
    is( $plain, GPForum::Test::ImageTool->png( 2, 2 ),
        'and with every chunk that draws it' );
    my $corrupt = $tagged;
    substr( $corrupt, length($PNG) + 10, 1 ) = 'X';
    is( $bytes->plain_png($corrupt), undef, 'a chunk that fails its CRC' );
    is( $bytes->plain_png( substr $tagged, 0, -12 ), undef, 'no IEND' );
    is( $bytes->plain_png('GIF89a'), undef, 'not a PNG' );
};

subtest 'the tools\' commands' => sub {
    my $vips =
      GPForum::Infrastructure::ImageTool::Vips->new( program => '/bin/vt' );
    is_deeply(
        [ $vips->commands( '/d/source.png', '/d', {}, [ $SMALL, $MIDDLE ] ) ],
        [
            [
                '/bin/vt', '/d/source.png', '--size', '64x64', '--smartcrop',
                'centre', '-o', '/d/avatar-64.png'
            ],
            [
                '/bin/vt', '/d/source.png', '--size', '128x128',
                '--smartcrop', 'centre', '-o', '/d/avatar-128.png'
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
                '/d/source.jpg', '/d', { width => $WIDTH, height => $HEIGHT },
                [$SMALL]
            )
        ],
        [
            [
                '/usr/bin/s', '-s', 'format', 'png', '-c', $HEIGHT, $HEIGHT,
                '/d/source.jpg', '--out', '/d/square.png'
            ],
            [ '/usr/bin/s', '-z', $SMALL, $SMALL, '/d/square.png', '--out',
                '/d/avatar-64.png' ],
        ],
        'sips crops the largest centred square, then resamples it'
    );
    is( $sips->engine, 'sips', 'named sips' );
};

subtest 'the tool the system installed' => sub {
    my $missing = GPForum::Infrastructure::ImageTool->system_tool(
        _os( { vips => ['/nonexistent/vipsthumbnail'], sips => undef } ) );
    is( $missing->engine, 'vips', 'without one, an unavailable vips' );
    ok( !$missing->available, 'that is not available' );
    eval { $missing->squares( { media_type => 'image/png' }, [$SMALL] ); 1 }
      and fail('an unavailable tool squares nothing');
    isa_ok( $EVAL_ERROR, 'GPForum::X::Unavailable', 'it throws' );

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
    is( GPForum::Config->from_environment( {} )->image_tool,
        'system', 'elsewhere the system\'s is used' );
    is(
        GPForum::Config->from_environment(
            { GPFORUM_ENV => 'test', GPFORUM_IMAGE_TOOL => 'system' }
        )->image_tool,
        'system',
        'and the operator may name it'
    );
};

subtest 'squares through a program, checked and cleaned' => sub {
    my $image = {
        content    => GPForum::Test::ImageTool->png( $WIDTH, $HEIGHT ),
        media_type => 'image/png',
        width      => $WIDTH,
        height     => $HEIGHT,
    };
    my $tool = GPForum::Infrastructure::ImageTool::Vips->new(
        program => _program('ok') );
    my $squares = $tool->squares( $image, [@SIDES] );
    is_deeply( [ sort { $a <=> $b } keys %{$squares} ],
        [@SIDES], 'one square a side' );
    is_deeply( $bytes->dimensions( $squares->{$MIDDLE}, 'image/png' ),
        { width => $MIDDLE, height => $MIDDLE }, 'of the side asked for' );
    unlike( $squares->{$SMALL}, qr/kept[ ]by[ ]the[ ]tool/msx,
        'with the tool\'s metadata stripped' );

    for my $case (
        [ 'wrong_size', 'a square of another size' ],
        [ 'fails',      'a tool that exits with an error' ],
        [ 'nothing',    'a tool that writes nothing' ],
        [ 'crashes',    'a tool killed by a signal' ],
      )
    {
        my ( $behaviour, $label ) = @{$case};
        is(
            GPForum::Infrastructure::ImageTool::Vips->new(
                program => _program($behaviour)
            )->squares( $image, [$SMALL] ),
            undef,
            "$label reads nothing"
        );
    }
    my $slow = GPForum::Infrastructure::ImageTool::Vips->new(
        program         => _program('sleeps'),
        timeout_seconds => $TIMEOUT
    );
    eval { $slow->squares( $image, [$SMALL] ); 1 }
      and fail('a slow tool answers');
    isa_ok( $EVAL_ERROR, 'GPForum::X::Unavailable',
        'a tool that outruns its time' );
    eval { $tool->squares( { %{$image}, media_type => 'text/plain' }, [$SMALL] );
        1 } and fail('text is squared');
    isa_ok( $EVAL_ERROR, 'GPForum::X::Unavailable', 'not an image' );
};

SKIP: {
    skip 'no sips on this system', 1 if !-x '/usr/bin/sips';

    subtest 'macOS\'s sips crops for real' => sub {
        my $tool = GPForum::Infrastructure::ImageTool::Sips->new(
            program => '/usr/bin/sips' );
        my $squares = $tool->squares(
            {
                content    => GPForum::Test::ImageTool->png( $WIDTH, $HEIGHT ),
                media_type => 'image/png',
                width      => $WIDTH,
                height     => $HEIGHT,
            },
            [@SIDES]
        );
        for my $side (@SIDES) {
            is_deeply( $bytes->dimensions( $squares->{$side}, 'image/png' ),
                { width => $side, height => $side }, "a $side pixel square" );
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
            'and reads nothing from bytes that are no picture'
        );
    };
}

subtest 'an upload is refused before anything is stored' => sub {
    my $pipeline = _Recorder->new;
    my $avatars  = _avatars( $pipeline, GPForum::Test::ImageTool->new );
    my @cases    = (
        [ 'missing',   { user_id => $USER } ],
        [ 'missing',   { user_id => $USER, content => q{} } ],
        [ 'too_large', { user_id => $USER, content => $PNG . "\0" x $SIX_MB } ],
        [
            'too_large',
            { user_id => $USER, upload => _Upload->new( size => $SIX_MB ) }
        ],
        [ 'not_image',  { user_id => $USER, content => "%PDF-1.4\n" } ],
        [ 'not_image',  { user_id => $USER, content => "words\n" } ],
        [ 'unreadable', { user_id => $USER, content => "$PNG broken" } ],
        [
            'too_many_pixels',
            {
                user_id => $USER,
                content => GPForum::Test::ImageTool->png( $TOO_WIDE, 1 )
            }
        ],
    );
    for my $case (@cases) {
        my ( $status, $input ) = @{$case};
        is( $avatars->upload($input)->{status}, $status, "refused: $status" );
    }
    is( scalar @{ $pipeline->calls }, 0, 'the pipeline was never asked' );
    is(
        _avatars( $pipeline, GPForum::Test::ImageTool->new( installed => 0 ) )
          ->upload(
            { user_id => $USER, content => GPForum::Test::ImageTool->png( 1, 1 ) }
          )->{status},
        'unavailable',
        'no installed tool, no picture'
    );
    is( _avatars( $pipeline, undef )->available, 0, 'nor without one' );
    is( $avatars->maximum_bytes, 5 * 1_024 * 1_024, 'five megabytes at most' );
};

subtest 'the media pipeline hands a waiting picture over' => sub {
    my $attachments = _Attachments->new;
    my $processor   = GPForum::Service::Attachment::MediaProcessor->new(
        avatars => _Avatars->new( answer => { ok => 1, status => 'shown' } ),
        storage => _Recorder->new,
        store   => $attachments,
    );
    is_deeply(
        $processor->process($ATTACHMENT),
        { ok => 1, status => 'shown', avatar => 1 },
        'a picture is the avatars\''
    );
    is( scalar @{ $attachments->variants }, 0, 'and gets no thumbnail' );

    my $other = GPForum::Service::Attachment::MediaProcessor->new(
        avatars => _Avatars->new( answer => undef ),
        storage => _Storage->new,
        store   => $attachments,
    );
    ok( $other->process($ATTACHMENT)->{variant},
        'any other image gets its thumbnail' );
    is( $attachments->variants->[0]{variant_type},
        'thumbnail', 'as it did' );
};

subtest 'the store refuses before it asks the database' => sub {
    my $functions = GPForum::Test::RecordingFunctions->new;
    my $store     = GPForum::Service::Community::AvatarStore->new(
        schema    => {},
        functions => $functions,
    );
    is( $store->offer( 'nope', $ATTACHMENT )->{status}, 'invalid' );
    is( $store->settle( $USER, 'nope', 'ready' )->{status}, 'invalid' );
    is( $store->remove_own('nope')->{status}, 'not_found' );
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
    is( $store->image( $USER, 99 ), undef, 'a side not kept' );
    is_deeply( $store->objects('nope'), [], 'objects of nobody' );
    is_deeply( $store->status('nope'), {}, 'the status of nobody' );
    is( scalar @{ $functions->calls }, 0, 'nothing reached the database' );
    is( $store->reason("  why \n"), 'why', 'a reason is trimmed' );
    is_deeply( $store->sides, [@SIDES], 'three sides' );
    is( $store->variant_type($SMALL), 'avatar_64', 'kept as variants' );
};

subtest 'avatar writes are limited like the other churn' => sub {
    my $access = GPForum::Web::ForumAccess->new;
    is( $access->write_limit_for('avatar.upload'), $CHURN, 'uploads' );
    is( $access->write_limit_for('avatar.remove'), $CHURN, 'removals' );
    ok( $access->requires_participation('avatar.upload'),
        'a suspended member uploads none' );
    ok( !$access->requires_participation('avatar.remove'),
        'but may remove theirs' );
};

done_testing();

sub _avatars ( $pipeline, $tool ) {
    return GPForum::Service::Community::Avatars->new(
        attachments => _Recorder->new,
        image_tool  => $tool,
        pipeline    => $pipeline,
        storage     => _Recorder->new,
        store       => _Recorder->new,
    );
}

sub _os ($packaging) {
    return _OS->new( packaging => $packaging );
}

# A fake vipsthumbnail: SOURCE --size NxN --smartcrop centre -o OUT, which
# behaves as named.
sub _program ($behaviour) {
    my $directory = tempdir( CLEANUP => 1 );
    my $path      = "$directory/vipsthumbnail";
    open my $script, '>', $path or die "open $path: $OS_ERROR";
    print {$script} <<"PERL" or die "write $path: $OS_ERROR";
#!$EXECUTABLE_NAME
use strict;
use warnings;
use Compress::Zlib ();
my \$behaviour = '$behaviour';
my (\$side) = \$ARGV[2] =~ /\\A(\\d+)x/;
my \$out = \$ARGV[-1];
exit 1 if \$behaviour eq 'fails';
exit 0 if \$behaviour eq 'nothing';
kill 'KILL', \$\$ if \$behaviour eq 'crashes';
sleep 5 if \$behaviour eq 'sleeps';
\$side += 1 if \$behaviour eq 'wrong_size';
sub chunk { my (\$t, \$d) = \@_; pack('N', length \$d) . \$t . \$d . pack('N', Compress::Zlib::crc32(\$t . \$d)) }
my \$row = "\\0" . ("\\x10\\x20\\x30" x \$side);
open my \$fh, '>:raw', \$out or exit 2;
print {\$fh} "\\x89PNG\\x0d\\x0a\\x1a\\x0a", chunk('IHDR', pack('N N C C C C C', \$side, \$side, 8, 2, 0, 0, 0)),
  chunk('tEXt', "Software\\0kept by the tool"), chunk('IDAT', Compress::Zlib::compress(\$row x \$side)), chunk('IEND', '');
close \$fh;
exit 0;
PERL
    close $script or die "close $path: $OS_ERROR";
    chmod $EXECUTABLE, $path or die "chmod $path: $OS_ERROR";

    return $path;
}

sub _jpeg ( $marker, $width, $height ) {
    return "\xff\xd8\xff\xe0"
      . pack( 'n', 16 )
      . "JFIF\0\x01\x01\0\0\x01\0\x01\0\0"
      . pack( 'C C', 0xff, $marker )
      . pack( 'n C n n C', 11, 8, $height, $width, 1 )
      . "\x01\x11\0\xff\xd9";
}

sub _webp ( $kind, $payload ) {
    my $chunk = $kind . pack( 'V', length $payload ) . $payload;
    return 'RIFF' . pack( 'V', 4 + length $chunk ) . 'WEBP' . $chunk;
}

sub _webp_lossy ( $width, $height ) {
    return _webp( 'VP8 ',
        "\0\0\0" . "\x9d\x01\x2a" . pack( 'v v', $width, $height ) . "\0" x 8 );
}

sub _webp_lossless ( $width, $height ) {
    return _webp( 'VP8L',
        "\x2f" . pack( 'V', ( $width - 1 ) | ( ( $height - 1 ) << 14 ) )
          . "\0" x 8 );
}

sub _webp_extended ( $width, $height ) {
    my $w = $width - 1;
    my $h = $height - 1;
    return _webp(
        'VP8X',
        "\0\0\0\0"
          . pack( 'C3', $w & 0xff, ( $w >> 8 ) & 0xff, ( $w >> 16 ) & 0xff )
          . pack( 'C3', $h & 0xff, ( $h >> 8 ) & 0xff, ( $h >> 16 ) & 0xff )
          . "\0" x 4
    );
}

1;
