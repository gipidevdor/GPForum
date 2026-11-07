# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use lib 'lib';
use lib 't/lib';
use GPForum::Command::AdminBootstrap;
use GPForum::Infrastructure::Id;
use GPForum::Test::ImageTool;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';
const my $PHOTO_SIDE          => 100;
const my $HTTP_OK             => 200;
const my $HTTP_CREATED        => 201;
const my $HTTP_PARTIAL        => 206;
const my $HTTP_NOT_MODIFIED   => 304;
const my $PNG_SIGNATURE_BYTES => 8;
const my $MP4_HEADER_BYTES    => 24;
const my $AVATAR_VARIANTS     => 3;
const my $HTTP_INVALID        => 400;
const my $HTTP_UNAUTHORIZED   => 401;
const my $HTTP_FORBIDDEN      => 403;
const my $HTTP_NOT_FOUND      => 404;
const my $HTTP_CONFLICT       => 409;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'requires PostgreSQL';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_ANTIVIRUS}                 = 'none';
local $ENV{GPFORUM_ATTACHMENT_ROOT}           = tempdir( CLEANUP => 1 );
local $ENV{GPFORUM_MEDIA_SOURCE_HOSTS}        = 'media.example.org';
my $dbh = $database->dbh;
my $ids = GPForum::Infrastructure::Id->new;
my ( $post, $owner ) = $dbh->selectrow_array(
    (
        join q{ },
        q{SELECT p.post_id, p.author_user_id FROM posts p},
        q{JOIN threads t USING(thread_id) JOIN categories c USING(category_id)},
q{JOIN spaces s USING(space_id) JOIN users u ON u.id = p.author_user_id},
        q{WHERE p.visibility = 'public' AND t.visibility = 'public'},
        q{AND c.visibility = 'public' AND s.visibility = 'public'},
        q{AND p.deleted_at IS NULL AND t.deleted_at IS NULL},
q{AND p.moderation_state = 'visible' AND t.moderation_state = 'visible'},
        q{AND u.status = 'active' AND u.deleted_at IS NULL LIMIT 1}
    )
);
ok( $post, 'public post fixture' );
my $staff = $ids->uuid;
$dbh->do(
    (
        join q{ },
        q{INSERT INTO users(id, username, display_name, email_normalized,},
q{password_hash, status, email_verified_at) VALUES (?, 'media_staff', 'Media Staff',},
        q{'media-staff@example.org', 'x', 'active', now())}
    ),
    undef, $staff
);
GPForum::Test::PostgresHarness::quietly(
    sub {
        return GPForum::Command::AdminBootstrap->new(
            schema => $database->schema )->run( 'grant', '--user-id', $staff );
    }
);
my $t = Test::Mojo->new('GPForum');
$t->app->helper(
    gp_image_tool => sub { return GPForum::Test::ImageTool->new; } );
isa_ok( $t->app->gp_attachment_storage,
    'GPForum::Service::Attachment::PostgresStorage' );
my $routes = $t->app->routes;
$routes->get('/__test/media-session/:id')->to(
    cb => sub ($c) {
        $c->session( user_id => $c->param('id') );
        return $c->render( json => { ok => 1 } );
    }
);
my $json = { Accept => 'application/json' };
$t->get_ok( '/moderation/media' => $json )->status_is($HTTP_UNAUTHORIZED);
my $owner_csrf = _session($owner);
$t->get_ok( '/moderation/media' => $json )->status_is($HTTP_FORBIDDEN);
my $mp4 =
    pack( 'N', $MP4_HEADER_BYTES )
  . 'ftypisom'
  . pack( 'N', 0 )
  . 'isommp42'
  . 'video payload';
_upload(
    $mp4,
    $owner_csrf,
    {
        source_kind      => 'authorized',
        rights_confirmed => 1,
        source_url       => 'https://media.example.org/clip.mp4',
    }
);
$t->status_is($HTTP_CREATED);
my $response   = $t->tx->res;
my $attachment = $response->json->{attachment}{attachment_id};
ok( $attachment, 'video stored for review' );
$t->get_ok( "/attachments/$attachment/download" => $json )
  ->status_is($HTTP_NOT_FOUND);
$t->get_ok( "/moderation/media/$attachment/preview" => $json )
  ->status_is($HTTP_FORBIDDEN);

# A moderator who contributed third-party content sees why review needs someone else.
# A forged native form must remain refused, with a usable HTML retry page.
GPForum::Test::PostgresHarness::quietly(
    sub {
        return GPForum::Command::AdminBootstrap->new(
            schema => $database->schema )->run( 'grant', '--user-id', $owner );
    }
);
$owner_csrf = _session($owner);
my $decision_path = "/moderation/media/$attachment/decision";
my $approval      = qq{form[action="$decision_path"] button[value="approved"]};
$t->get_ok('/moderation/media')
  ->status_is($HTTP_OK)
  ->element_exists( $approval . '[disabled]' );
$t->text_like( "#own-upload-$attachment",
    qr/(?:[Aa]nother[ ]moderator|altro[ ]moderatore)/msx );
my $reason = 'Original file checked; keep this explanation on refusal.';
$t->post_ok(
    $decision_path => form => {
        csrf_token => $owner_csrf,
        decision   => 'approved',
        reason     => $reason,
    }
  )
  ->status_is($HTTP_CONFLICT)
  ->header_like( 'Content-Type' => qr{\Atext/html}msx );
$t->element_exists('p[role="alert"]')
  ->text_is( qq{form[action="$decision_path"] textarea[name="reason"]},
    $reason );
is(
    $dbh->selectrow_array(
        'SELECT status FROM attachment_content_reviews WHERE attachment_id=?',
        undef, $attachment
    ),
    'pending',
    'refused self-approval leaves the saved file awaiting review'
);
$t->post_ok(
    $decision_path => $json => form => {
        csrf_token => $owner_csrf,
        decision   => 'approved',
        reason     => $reason,
    }
)->status_is($HTTP_CONFLICT)->json_is( '/status' => 'refused' );
my $staff_csrf = _session($staff);
$t->get_ok('/moderation/media')->status_is($HTTP_OK);
$t->element_exists('form textarea[name=reason]')
  ->element_exists( $approval . ':not([disabled])' )
  ->element_exists('video[controls]');
$t->get_ok("/moderation/media/$attachment/preview")->status_is($HTTP_OK);
$t->content_is($mp4)->header_is( 'Cache-Control' => 'private, no-store' );
$t->post_ok(
    "/moderation/media/$attachment/decision" => $json => form => {
        decision => 'approved',
        reason   => 'Verified original content',
    }
)->status_is($HTTP_FORBIDDEN);
$t->post_ok(
    "/moderation/media/$attachment/decision" => $json => form => {
        csrf_token => $staff_csrf,
        decision   => 'approved',
        reason     => 'Verified original content',
    }
)->status_is($HTTP_OK);
$t->json_is( '/status' => 'ok' );
$t->get_ok("/attachments/$attachment/download")->status_is($HTTP_OK);
$t->content_is($mp4)->header_like( 'Content-Disposition' => qr/\Ainline;/msx );
$t->get_ok( "/attachments/$attachment/download" => { Range => 'bytes=-7' } )
  ->status_is($HTTP_PARTIAL);
$t->content_is('payload');
$t->head_ok("/attachments/$attachment/download")->status_is($HTTP_OK);
$t->content_is(q{});
$t->post_ok(
    "/moderation/media/$attachment/decision" => $json => form => {
        csrf_token => $staff_csrf,
        decision   => 'rejected',
        reason     => 'Inappropriate material discovered',
    }
)->status_is($HTTP_OK);
$t->get_ok( "/attachments/$attachment/download" => $json )
  ->status_is($HTTP_NOT_FOUND);
$t->get_ok( "/moderation/media/$attachment/preview" => $json )
  ->status_is($HTTP_NOT_FOUND);
$owner_csrf = _session($owner);
_upload( $mp4, $owner_csrf,
    { source_kind => 'original', rights_confirmed => 1 } );
$t->status_is($HTTP_INVALID);
$t->json_is( '/errors/attachment' => 'this content has been rejected' );
_upload(
    $mp4 . 'new',
    $owner_csrf,
    {
        source_kind      => 'authorized',
        rights_confirmed => 1,
        source_url       => 'https://media.example.org.attacker.test/file'
    }
);
$t->status_is($HTTP_INVALID);
$t->json_is( '/errors/source_url' => 'an authorized HTTPS source is required' );
_upload(
    $mp4 . 'new',
    $owner_csrf,
    {
        source_kind      => 'authorized',
        rights_confirmed => 1,
        source_url       => 'https://media.example.org/file'
    }
);
$t->status_is($HTTP_CREATED);

_image_preview();

$t->post_ok(
    '/settings/avatar' => $json => form => {
        csrf_token       => $owner_csrf,
        source_kind      => 'original',
        rights_confirmed => 1,
        avatar           => {
            content =>
              GPForum::Test::ImageTool->png( $PHOTO_SIDE, $PHOTO_SIDE ),
            filename     => 'profile.png',
            content_type => 'image/png'
        },
    }
)->status_is($HTTP_OK);
$t->json_is( '/status' => 'shown' );
my ( $profile_id, $profile_key ) = $dbh->selectrow_array(
    (
        join q{ },
        q{SELECT a.attachment_id, a.object_key FROM member_avatars m},
q{JOIN attachments a ON a.attachment_id = m.attachment_id WHERE m.user_id = ?}
    ),
    undef, $owner
);
ok( $t->app->gp_attachment_storage->object_info($profile_key),
    'HTTP profile original stored in PostgreSQL' );
my $profile_service = $t->app->gp_avatars;
ok(
    !defined $profile_service->status($owner)->{pending_state},
    'an original profile picture is published without waiting for staff'
);
my $review = $t->app->gp_attachment_content_review;
is( $review->find($profile_id)->{status},
    'approved', 'the original attestation satisfies content policy' );
ok(
    !defined $dbh->selectrow_array(
'SELECT reviewed_by FROM attachment_content_reviews WHERE attachment_id=?',
        undef,
        $profile_id
    ),
    'automatic publication fabricates no staff reviewer'
);
my $processor = $t->app->gp_media_processor;
is( $processor->process($profile_id)->{avatar},
    1, 'approved event processes profile variants' );
is(
    $dbh->selectrow_array(
        (
            join q{ },
            q{SELECT count(*) FROM attachment_variants v},
q{JOIN attachment_objects o USING(object_key) WHERE v.attachment_id = ? AND o.complete}
        ),
        undef,
        $profile_id
    ),
    $AVATAR_VARIANTS,
    'all three cropped profile variants stored in PostgreSQL'
);
$t->get_ok("/avatars/$owner/$profile_id/64")->status_is($HTTP_OK);
$t->header_is( 'Cache-Control' => 'public, no-cache, must-revalidate' );
is(
    $review->decide(
        {
            attachment_id => $profile_id,
            actor_user_id => $staff,
            decision      => 'rejected',
            reason        => 'Picture withdrawn after review'
        }
    )->{status},
    'ok',
    'profile picture can be withdrawn'
);
$t->get_ok( "/avatars/$owner/$profile_id/64" =>
      { 'If-None-Match' => qq{"$profile_id-64"} } )->status_is($HTTP_NOT_FOUND);
done_testing();

sub _image_preview {
    my $photo = GPForum::Test::ImageTool->png( $PHOTO_SIDE, $PHOTO_SIDE,
        comment => 'post image' );
    $t->post_ok(
        "/p/$post/attachments" => $json => form => {
            command_id       => $ids->uuid,
            csrf_token       => $owner_csrf,
            source_kind      => 'authorized',
            source_url       => 'https://media.example.org/image',
            rights_confirmed => 1,
            attachment       => {
                content      => $photo,
                filename     => 'photo.png',
                content_type => 'image/png'
            },
        }
    )->status_is($HTTP_CREATED);
    my $upload_response = $t->tx->res;
    my $id              = $upload_response->json->{attachment}{attachment_id};
    my $key             = "previews/$id";
    my $preview         = GPForum::Test::ImageTool->png( 2, 1 );
    $t->app->gp_attachment_storage->write_object( $key, $preview );
    $t->app->gp_attachment_store->add_variant(
        {
            attachment_id => $id,
            variant_type  => 'preview-v1-1280',
            object_key    => $key,
            byte_size     => length($preview),
            media_type    => 'image/png',
        }
    );
    my $url = "/attachments/$id/download?preview=1280";
    $t->get_ok($url)->status_is($HTTP_NOT_FOUND);
    my $image_review = $t->app->gp_attachment_content_review;
    is(
        $image_review->decide(
            {
                attachment_id => $id,
                actor_user_id => $staff,
                decision      => 'approved',
                reason        => 'Original source and photo checked'
            }
        )->{status},
        'ok',
        'image approved through review'
    );
    $t->get_ok("/attachments/$id/download")
      ->status_is($HTTP_OK)
      ->content_is($photo);
    my $original_response = $t->tx->res;
    my $original_etag     = $original_response->headers->etag;
    $t->get_ok($url)->status_is($HTTP_OK)->content_is($preview);
    $t->header_is( 'Content-Type'  => 'image/png' )
      ->header_is( 'Cache-Control' => 'private, no-store' );
    my $preview_response = $t->tx->res;
    my $preview_etag     = $preview_response->headers->etag;
    isnt( $preview_etag, $original_etag,
        'preview and original have distinct ETags' );
    $t->get_ok( $url => { 'If-None-Match' => $original_etag } )
      ->status_is($HTTP_OK)
      ->content_is($preview);
    $t->get_ok( $url => { 'If-None-Match' => $preview_etag } )
      ->status_is($HTTP_NOT_MODIFIED);
    $t->get_ok( $url => { Range => 'bytes=0-7' } )
      ->status_is($HTTP_PARTIAL)
      ->content_is( substr $preview, 0, $PNG_SIGNATURE_BYTES );
    $t->head_ok($url)->status_is($HTTP_OK)->content_is(q{});
    $t->header_is( 'Content-Length' => length $preview );
    is(
        $image_review->decide(
            {
                attachment_id => $id,
                actor_user_id => $staff,
                decision      => 'rejected',
                reason        => 'Image withdrawn after review'
            }
        )->{status},
        'ok',
        'preview source withdrawn'
    );
    $t->get_ok( $url => { 'If-None-Match' => $preview_etag } )
      ->status_is($HTTP_NOT_FOUND);
    return;
}

sub _session ($user) {
    $t->get_ok("/__test/media-session/$user")->status_is($HTTP_OK);
    $t->get_ok('/settings')->status_is($HTTP_OK);
    return $t->tx->res->dom->at('input[name=csrf_token]')->attr('value');
}

sub _upload ( $content, $csrf, $provenance ) {
    $t->post_ok(
        "/p/$post/attachments" => $json => form => {
            command_id => $ids->uuid,
            csrf_token => $csrf,
            %{$provenance},
            attachment => {
                content      => $content,
                filename     => 'clip.mp4',
                content_type => 'video/mp4'
            },
        }
    );
    return;
}

1;
