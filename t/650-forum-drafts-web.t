# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use Test::Mojo;
use Test::More;
use lib 'lib';
use lib 't/lib';
use GPForum::Service::Forum::BodyRenderer;
use GPForum::Test::DraftWebStore;
use GPForum::Test::ForumWebServices;

our $VERSION = '0.001';

const my $HTTP_OK           => 200;
const my $HTTP_FOUND        => 302;
const my $HTTP_UNAUTHORIZED => 401;
const my $HTTP_FORBIDDEN    => 403;
const my $HTTP_NOT_FOUND    => 404;
const my $HTTP_CONFLICT     => 409;

my $test     = Test::Mojo->new('GPForum');
my $services = GPForum::Test::ForumWebServices->new;
my $drafts   = GPForum::Test::DraftWebStore->new;
for my $helper (
    qw(gp_category_reader gp_thread_reader gp_thread_detail_reader
    gp_post_reader gp_thread_read_state gp_attachment_store gp_rate_limiter
    gp_suspension_store gp_bookmark_store gp_like_store gp_reaction_store gp_reply_links gp_subscription_store)
  )
{
    $test->app->helper( $helper => sub { return $services; } );
}
$test->app->helper( gp_draft_store => sub { return $drafts; } );
my $routes = $test->app->routes;
$routes->get('/__test/session/:user_id')->to(
    cb => sub ($c) {
        $c->session( user_id => $c->param('user_id') );
        return $c->render( json => { ok => 1 } );
    }
);

my $json = { Accept => 'application/json' };
$test->get_ok( '/drafts' => $json )->status_is($HTTP_UNAUTHORIZED);
$test->header_is( 'Cache-Control' => 'private, no-store' );
$test->get_ok('/__test/session/user-1')->status_is($HTTP_OK);
$test->get_ok('/new-thread')->status_is($HTTP_OK);
my $page = $test->tx->res->dom;
my $form = $page->at('form[data-composer]');
ok( $form, 'authenticated composer has draft controls' );
my %input = map { $_->attr('name') => $_->attr('value') }
  @{ $form->find('input[name]')->to_array };
$input{title}         = q{};
$input{category_id}   = q{};
$input{body_source}   = "  unfinished\n\n";
$input{owner_user_id} = 'user-2';
$test->post_ok( '/drafts' => $json => form => { %input, csrf_token => 'bad' } )
  ->status_is($HTTP_FORBIDDEN);
is( scalar @{ $drafts->saves }, 0, 'CSRF failure never reaches draft storage' );
$test->post_ok( '/drafts' => $json => form => \%input )->status_is($HTTP_OK);
$test->json_is( '/draft/draft_revision' => 1 );
is( $drafts->saves->[0]{owner_user_id}, 'user-1', 'owner comes from session' );
is(
    $drafts->saves->[0]{body_source},
    "  unfinished\n\n",
    'save preserves incomplete source'
);
$test->header_is( 'Cache-Control' => 'private, no-store' );
my $id = $input{draft_id};
$test->get_ok('/drafts')->status_is($HTTP_OK);
$test->element_exists(qq{a[href="/drafts/$id"]});
$test->get_ok("/drafts/$id")->status_is($HTTP_OK);
$test->text_is( '#thread-body' => "  unfinished\n\n" );
$test->element_exists('button[formnovalidate][formaction="/composer/preview"]');

# Canonical renderer, no database write, and source remains escaped in its field.
my $source = '<script>alert(1)</script> **strong**';
$input{body_source} = $source;
my $before = scalar @{ $drafts->saves };
$test->post_ok( '/composer/preview' => $json => form => \%input )
  ->status_is($HTTP_OK);
$test->json_is(
    '/html' => GPForum::Service::Forum::BodyRenderer->new->render_safe($source)
);
is( scalar @{ $drafts->saves }, $before, 'preview never saves the draft' );
$test->post_ok( '/composer/preview' => form => \%input )->status_is($HTTP_OK);
$test->element_exists('[data-composer-preview]:not([hidden])');
$test->element_exists_not('[data-preview-body] script');
$test->text_is( '#thread-body' => $source );

# Lists use the same renderer in JSON and native previews; previewing does
# not persist source or trust embedded HTML.
$input{body_source} = "- **first**\n- <script>x</script>\n\n3. third";
$test->post_ok( '/composer/preview' => $json => form => \%input )
  ->status_is($HTTP_OK);
$test->json_is( '/html' =>
'<ul><li><strong>first</strong></li><li>&lt;script&gt;x&lt;/script&gt;</li></ul>'
      . "\n"
      . '<ol start="3"><li>third</li></ol>' );
$test->post_ok( '/composer/preview' => form => \%input )->status_is($HTTP_OK);
$test->element_exists('[data-preview-body] ul li strong');
$test->element_exists('[data-preview-body] ol[start="3"]');
$test->element_exists_not('[data-preview-body] script');
is( scalar @{ $drafts->saves }, $before, 'list previews never save the draft' );

$drafts->refusal('conflict');
$input{body_source} = 'keep this newer text';
$test->post_ok( '/drafts' => form => \%input )->status_is($HTTP_CONFLICT);
$test->text_is( '#thread-body' => 'keep this newer text' );
$test->post_ok( "/drafts/$id/delete" => form => \%input )
  ->status_is($HTTP_CONFLICT);
$drafts->refusal(undef);

# A reply resumes directly as a standalone native composer.
my $reply_id = '018f1006-0010-7000-8000-000000000001';
$drafts->entries->{$reply_id} = {
    %input,
    draft_id       => $reply_id,
    draft_revision => 1,
    kind           => 'reply',
    owner_user_id  => 'user-1',
    thread_id      => 'thread-1',
    body_source    => 'reply draft',
};
$test->get_ok("/drafts/$reply_id")->status_is($HTTP_OK);
$test->text_is( '#reply-body' => 'reply draft' );
$test->element_exists_not('form[data-composer][hx-post]');
$test->get_ok('/__test/session/user-2')->status_is($HTTP_OK);
$test->get_ok( "/drafts/$id"       => $json )->status_is($HTTP_NOT_FOUND);
$test->get_ok( "/drafts/$reply_id" => $json )->status_is($HTTP_NOT_FOUND);
$test->get_ok( '/drafts'           => $json )
  ->status_is($HTTP_OK)
  ->json_is( '/drafts' => [] );
$test->get_ok('/__test/session/user-1')->status_is($HTTP_OK);
$test->post_ok( "/drafts/$id/delete" => form => \%input )
  ->status_is($HTTP_FOUND);
ok( !$drafts->entries->{$id}, 'native delete removes owned draft' );

done_testing;

1;
