# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use utf8;
use Test::More;
use Test::Mojo;
use Const::Fast;
use File::Temp qw(tempdir);
use Mojo::URL;
use lib 'lib';
use lib 't/lib';
use GPForum::Infrastructure::Id;
use GPForum::Test::PgDatabase;
our $VERSION = '0.001';
const my $HTTP_OK         => 200;
const my $HTTP_FOUND      => 302;
const my $HTTP_INVALID    => 400;
const my $HTTP_FORBIDDEN  => 403;
const my $HTTP_MISSING    => 404;
const my $AT_CODE         => 64;
const my $CHECKSUM_LENGTH => 64;
const my $MP4_HEADER      => 24;
const my $FIRST_PAGE      => 50;
const my $SECOND_PAGE     => 5;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'requires PostgreSQL';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_ANTIVIRUS}                 = 'none';
local $ENV{GPFORUM_ATTACHMENT_ROOT}           = tempdir( CLEANUP => 1 );
my $dbh = $database->dbh;
my $ids = GPForum::Infrastructure::Id->new;
my ( $source_post, $owner, $category ) = $dbh->selectrow_array(
q{SELECT p.post_id,p.author_user_id,t.category_id FROM posts p JOIN threads t USING(thread_id) JOIN categories c USING(category_id) JOIN spaces s USING(space_id) JOIN users u ON u.id=p.author_user_id WHERE p.visibility='public' AND p.moderation_state='visible' AND p.deleted_at IS NULL AND t.visibility='public' AND t.moderation_state='visible' AND t.deleted_at IS NULL AND c.visibility='public' AND s.visibility='public' AND u.status='active' AND u.deleted_at IS NULL LIMIT 1}
);
my ( $other, $other_name ) = $dbh->selectrow_array(
q{SELECT id,username FROM users WHERE id<>? AND status='active' AND deleted_at IS NULL AND email_verified_at IS NOT NULL LIMIT 1},
    undef, $owner
);
my $t      = Test::Mojo->new('GPForum');
my $routes = $t->app->routes;
$routes->get('/__test/gui/session/:id')->to(
    cb => sub ($c) {
        $c->session( user_id => $c->param('id') );
        return $c->render( text => 'ready' );
    }
);
$t->get_ok("/p/$source_post/attachments")->status_is($HTTP_FOUND);
_signin($owner);
$t->get_ok('/menu')->status_is($HTTP_OK);
$t->element_exists('a[href="/new-media"]');
$t->element_exists('a[href="/messages/new"]');
$t->get_ok('/messages')->status_is($HTTP_OK);
$t->element_exists('a[href="/messages/new"]');
$t->get_ok('/messages/new')->status_is($HTTP_OK);
$t->element_exists('form[method="get"] input[name="username"]');
$t->get_ok( Mojo::URL->new('/messages/new')
      ->query( username => chr($AT_CODE) . $other_name ) )->status_is($HTTP_OK);
$t->element_exists(
    'form[action="/messages/new/' . $other_name . '"] textarea[name="body"]' );
$t->get_ok('/messages/new?username=unknown_gui_member')
  ->status_is($HTTP_MISSING);
$t->element_exists('form input[name="username"][value="unknown_gui_member"]');
$t->get_ok('/new-media')->status_is($HTTP_OK);
$t->text_is( 'h1' => 'Photos, video, audio and podcasts' );
$t->element_exists('input[name="after_publish"][checked]');
my $create = _fields('form[action="/threads"]');
$t->post_ok(
    '/threads' => form => {
        %{$create},
        category_id   => $category,
        title         => 'Una prova: è à é ì ò ù',
        body_source   => q{è},
        after_publish => 'attachment'
    }
)->status_is($HTTP_FOUND);
my $create_response = $t->tx->res;
my $upload_path     = $create_response->headers->location;
like(
    $upload_path,
    qr{\A /p/[[:xdigit:]-]+/attachments \z}msx,
    'media creation continues directly to the upload screen'
);
my ($post_id) = $upload_path =~ m{/p/([^/]+)/attachments}msx;
ok( $post_id, 'created post id' );
my ( $thread_id, $stored_title, $stored_body ) = $dbh->selectrow_array(
q{SELECT p.thread_id,t.title,b.body_source FROM posts p JOIN threads t USING(thread_id) JOIN post_bodies b USING(post_id) WHERE p.post_id=?},
    undef, $post_id
);
is( $stored_title, 'Una prova: è à é ì ò ù',
    'accented title survives storage' );
is( $stored_body, q{è}, 'accented body survives storage' );
$t->get_ok("/t/$thread_id")->status_is($HTTP_OK);
$t->text_is( "#post-$post_id .forum-post-body p", q{è} );
$t->get_ok($upload_path)->status_is($HTTP_OK);
$t->header_is( 'Cache-Control' => 'private, no-store' );
$t->element_exists(
    'form[enctype="multipart/form-data"] input[type="file"][name="attachment"]'
);
$t->element_exists('input[name="rights_confirmed"][required]');
$t->element_exists('select[name="source_kind"]');
my $first = _fields('form[enctype="multipart/form-data"]');
$t->post_ok( $upload_path => form =>
      { %{$first}, source_kind => 'original', rights_confirmed => 1 } )
  ->status_is($HTTP_INVALID);
$t->element_exists('.ui-alert');
$t->element_exists('input[type="file"]');
my $retry = _fields('form[enctype="multipart/form-data"]');
isnt( $retry->{command_id}, $first->{command_id},
    'retry receives a fresh command after a refused file' );
my $mp4 =
    pack( 'N', $MP4_HEADER )
  . 'ftypisom'
  . pack( 'N', 0 )
  . 'isommp42'
  . 'recorded episode';
$t->post_ok(
    $upload_path => form => {
        %{$retry},
        source_kind      => 'original',
        rights_confirmed => 1,
        attachment       => {
            content      => $mp4,
            filename     => 'episode.mp4',
            content_type => 'video/mp4'
        }
    }
)->status_is($HTTP_FOUND);
my ($attachment) = $dbh->selectrow_array(
q{SELECT attachment_id FROM attachment_links WHERE target_type='post' AND target_id=?},
    undef, $post_id
);
ok( $attachment, 'the file is linked to the newly created post' );
$t->get_ok($upload_path)->status_is($HTTP_OK);
$t->content_like(qr/episode[.]mp4/msx);
$t->element_exists( 'a[href="/attachments/' . $attachment . '/download"]' );
my $remove =
  _fields( 'form[action="/p/'
      . $post_id
      . '/attachments/'
      . $attachment
      . '/delete"]' );
$t->get_ok( '/attachments/' . $attachment . '/download' )
  ->status_is($HTTP_OK)
  ->content_is($mp4);
_signin($other);
$t->get_ok($upload_path)->status_is($HTTP_FORBIDDEN);
_signin($owner);
$t->get_ok($upload_path)->status_is($HTTP_OK);
$remove =
  _fields( 'form[action="/p/'
      . $post_id
      . '/attachments/'
      . $attachment
      . '/delete"]' );
$t->post_ok( "/p/$post_id/attachments/$attachment/delete" => form => $remove )
  ->status_is($HTTP_FOUND);
$t->get_ok($upload_path)->status_is($HTTP_OK);
$t->element_exists_not( 'form[action="/p/'
      . $post_id
      . '/attachments/'
      . $attachment
      . '/delete"]' );
ok(
    $dbh->selectrow_array(
        q{SELECT deleted_at IS NOT NULL FROM attachments WHERE attachment_id=?},
        undef,
        $attachment
    ),
    'an unpublished upload can be removed through its GUI'
);

for my $number ( 1 .. $FIRST_PAGE + $SECOND_PAGE ) {
    my $file = $ids->uuid;
    $dbh->do(
q{INSERT INTO attachments(attachment_id,owner_user_id,object_key,original_filename,media_type,byte_size,checksum) VALUES (?,?,?,?,'audio/mpeg',1,?)},
        undef,
        $file,
        $owner,
        'gui-meta/' . $file,
        "episode-$number.mp3",
        'a' x $CHECKSUM_LENGTH
    );
    $dbh->do(
q{INSERT INTO attachment_links(attachment_link_id,attachment_id,target_type,target_id) VALUES (?,?,'post',?)},
        undef, $ids->uuid, $file, $post_id
    );
}
$t->get_ok($upload_path)->status_is($HTTP_OK);
my $page_response = $t->tx->res;
my $page_dom      = $page_response->dom;
is( $page_dom->find('section[aria-labelledby="post-files-heading"] li')->size,
    $FIRST_PAGE, 'the first private upload page is bounded' );
my $older = $page_dom->at('a[href*="?after="]')->attr('href');
$t->get_ok($older)->status_is($HTTP_OK);
my $older_response = $t->tx->res;
my $older_dom      = $older_response->dom;
is(
    $older_dom->find('section[aria-labelledby="post-files-heading"] li')->size,
    $SECOND_PAGE, 'the continuation uses the next keyset page'
);
$t->element_exists_not('a[href*="?after="]');
$t->get_ok( $upload_path . '?after=bad' )->status_is($HTTP_INVALID);
my ($foreign_rows) = $dbh->selectrow_array(
    q{SELECT count(*) FROM api.attachment_owned_post_files_v2(?,?,NULL)},
    undef, $post_id, $other );
is( $foreign_rows, 0, 'the fixed metadata function also enforces ownership' );
my $guest = Test::Mojo->new('GPForum');
$guest->get_ok("/p/$post_id/verification")->status_is($HTTP_OK);
$guest->element_exists( 'a[href="/p/' . $post_id . '/signature"][download]' );
$guest->element_exists('a[href="/.well-known/gpforum-signing-keys"][download]');
$guest->get_ok("/p/$post_id/signature")->status_is($HTTP_OK);
$guest->json_is( '/post_id' => $post_id );
$dbh->do( q{UPDATE posts SET visibility='private' WHERE post_id=?},
    undef, $post_id );
$guest->get_ok("/p/$post_id/verification")->status_is($HTTP_MISSING);
$t->get_ok("/p/$post_id/verification")->status_is($HTTP_OK);
done_testing();

sub _signin($account) {
    $t->get_ok("/__test/gui/session/$account")->status_is($HTTP_OK);
    return;
}

sub _fields($selector) {
    my $response = $t->tx->res;
    my $form_dom = $response->dom;
    my $form     = $form_dom->at($selector);
    die "Missing GUI form: $selector\n" if !$form;
    return { map { $_->attr('name') => $_->attr('value') // q{} }
          @{ $form->find('input[type="hidden"][name]')->to_array } };
}
1;
