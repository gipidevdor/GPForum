# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Test::More;
use File::Temp qw(tempdir);
use Const::Fast;
use Mojo::Promise;
use lib 'lib';
use lib 't/lib';
use GPForum::Infrastructure::ImageTool;
use GPForum::Service::Attachment::MediaProcessor;
use GPForum::Service::Attachment::Delivery;
use GPForum::Service::Attachment::Lifecycle;
use GPForum::Service::Attachment::FilesystemStorage;
use GPForum::Test::AvatarDouble;
use GPForum::Test::CountingAttachmentStorage;
use GPForum::Test::ImageTool;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';
const my $WIDTH          => 2_560;
const my $HEIGHT         => 1_440;
const my $BOUND          => 1_280;
const my $PREVIEW_HEIGHT => 720;
const my $PAD            => 50_000;
my $image =
  GPForum::Test::ImageTool->png( $WIDTH, $HEIGHT, comment => 'x' x $PAD );
my $png        = GPForum::Test::ImageTool->png( $BOUND, $PREVIEW_HEIGHT );
my $attachment = {
    attachment_id => 'picture',
    object_key    => 'pictures/original',
    state         => 'available',
    media_type    => 'image/png',
    checksum      => 'original-digest',
};
my $storage = GPForum::Test::CountingAttachmentStorage->new(
    inner => GPForum::Service::Attachment::FilesystemStorage->new(
        root => tempdir( CLEANUP => 1 )
    ),
);
$storage->write_object( $attachment->{object_key}, $image );
my %variants;
my ( $conversions, $lookups ) = ( 0, 0 );
my $allowed = 1;
my $store   = GPForum::Test::AvatarDouble->new;
my $tool    = GPForum::Test::ImageTool->new;
with_replaced_subs(
    'GPForum::Test::ImageTool',
    {
        previews => sub ( $self, $source, $bounds ) {
            $conversions++;
            is_deeply( $bounds, [$BOUND],
                'conversion has a fixed output bound' );
            is( $source->{width}, $WIDTH,
                'already measured source passed to tool' );
            return {
                $BOUND => {
                    width   => $BOUND,
                    height  => $PREVIEW_HEIGHT,
                    content => $png
                }
            };
        },
    },
    sub {
        with_replaced_subs(
            'GPForum::Test::AvatarDouble',
            {
                lifecycle =>
                  sub { return GPForum::Service::Attachment::Lifecycle->new; },
                find_attachment => sub { return $attachment; },
                find_variant    => sub ( $self, $input ) {
                    $lookups++;
                    return $variants{ $input->{variant_type} };
                },
                add_variant => sub ( $self, $input ) {
                    return $variants{ $input->{variant_type} } = $input;
                },
                find_variant_p => sub ( $self, $input, @ ) {
                    return Mojo::Promise->resolve(
                        $self->find_variant($input) );
                },
                download_for_p => sub {
                    if ( !$allowed ) {
                        return Mojo::Promise->resolve(
                            { ok => 0, error => 'not_found' } );
                    }
                    return Mojo::Promise->resolve(
                        {
                            ok         => 1,
                            attachment => $attachment,
                            %{$attachment}, original_filename => 'Photo.png'
                        }
                    );
                },
            },
            sub {
                my $processor =
                  GPForum::Service::Attachment::MediaProcessor->new(
                    store      => $store,
                    storage    => $storage,
                    image_tool => $tool,
                  );
                ok(
                    $processor->process('picture')->{ok},
                    'worker produces thumbnail and preview'
                );
                is( scalar keys %variants, 2, 'both variants recorded' );
                is( scalar $storage->reads->@*,
                    1, 'source read once for both conversions' );
                my $preview = $variants{'preview-v1-1280'};
                ok(
                    $preview->{byte_size} < length $image,
                    'only smaller preview stored'
                );
                is( $storage->inner->read_object( $preview->{object_key} ),
                    $png, 'preview stored separately' );
                ok(
                    $processor->process('picture')->{skipped},
                    'replayed event reuses variants'
                );
                is( $conversions, 1, 'replay does not rerun converter' );
                is( scalar $storage->reads->@*,
                    1, 'replay does not read source' );
                my $delivery = GPForum::Service::Attachment::Delivery->new(
                    store   => $store,
                    storage => $storage
                );
                my $original =
                  $delivery->download( { attachment_id => 'picture' } );
                my $reduced = $delivery->download(
                    { attachment_id => 'picture', preview => $BOUND } );
                is(
                    $original->{object_key},
                    $attachment->{object_key},
                    'ordinary download remains original'
                );
                is(
                    $reduced->{object_key},
                    $preview->{object_key},
                    'inline request streams stored preview'
                );
                isnt(
                    $reduced->{checksum},
                    $attachment->{checksum},
                    'preview has a separate conditional validator'
                );
                is( scalar $storage->reads->@*,
                    1, 'delivery does not buffer source or preview' );
                my $before = $lookups;
                $allowed = 0;
                is( $delivery->download( { preview => $BOUND } )->{error},
                    'not_found', 'original denial denies preview' );
                is( $lookups, $before,
                    'denied requests never look up variants' );
                $allowed = 1;
                delete $variants{'preview-v1-1280'};
                is(
                    $delivery->download( { preview => $BOUND } )->{object_key},
                    $attachment->{object_key},
                    'old upload falls back to original'
                );
                $before = $lookups;
                is(
                    $delivery->download( { preview => '../../thumbnail' } )
                      ->{object_key},
                    $attachment->{object_key},
                    'unrecognized preview selector keeps original'
                );
                is( $lookups, $before,
                    'client cannot select arbitrary variants' );

                # Neither a small source nor a larger encoded output is persisted.
                my $preview_service = $processor->preview;
                my $small           = {
                    width      => 1,
                    height     => 1,
                    content    => 'x',
                    media_type => 'image/png'
                };
                $preview_service->process( $attachment, $small );
                is( $conversions, 1, 'small source is never enlarged' );
                $preview_service->process( $attachment,
                    { %{$small}, width => $WIDTH, height => $HEIGHT } );
                ok( !$variants{'preview-v1-1280'},
                    'unprofitable conversion is not stored' );
                my $before_animation = $conversions;
                $preview_service->process( $attachment,
                    { %{$small}, width => $WIDTH, content => 'acTL animation' }
                );
                is( $conversions, $before_animation,
                    'animated PNG keeps original playback' );
                with_replaced_subs(
                    'GPForum::Test::ImageTool',
                    {
                        engine => sub { return 'sips'; },
                    },
                    sub {
                        my $before_exif = $conversions;
                        $preview_service->process(
                            $attachment,
                            {
                                width      => $WIDTH,
                                height     => $HEIGHT,
                                media_type => 'image/jpeg',
                                content    => "Exif\0\0" . ( 'x' x $PAD ),
                            }
                        );
                        is( $conversions, $before_exif,
                            'sips keeps EXIF-oriented originals' );
                        return;
                    }
                );
                return;
            }
        );
        return;
    }
);

subtest 'native tool preserves proportions and strips metadata' => sub {
    my $native = GPForum::Infrastructure::ImageTool->system_tool;
    if ( !$native->available ) { plan skip_all => 'no system image tool'; }
    my $result = $native->previews(
        {
            content    => $image,
            width      => $WIDTH,
            height     => $HEIGHT,
            media_type => 'image/png'
        },
        [$BOUND]
    );
    ok( $result, 'native preview produced' );
    is_deeply(
        [ @{ $result->{$BOUND} }{qw(width height)} ],
        [ $BOUND, $PREVIEW_HEIGHT ],
        'full landscape retained'
    );
    unlike( $result->{$BOUND}{content}, qr/tEXt/msx,
        'source comments removed' );
    my $small = GPForum::Test::ImageTool->png( 2, 1 );
    my $kept  = $native->previews(
        {
            content    => $small,
            width      => 2,
            height     => 1,
            media_type => 'image/png'
        },
        [$BOUND]
    );
    is_deeply(
        [ @{ $kept->{$BOUND} }{qw(width height)} ],
        [ 2, 1 ],
        'native tool never enlarges'
    );
};
done_testing();
1;
