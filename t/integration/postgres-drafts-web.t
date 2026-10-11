# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use Test::Mojo;
use Test::More;
use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

const my $HTTP_OK        => 200;
const my $HTTP_CREATED   => 201;
const my $HTTP_FOUND     => 302;
const my $HTTP_INVALID   => 400;
const my $HTTP_NOT_FOUND => 404;
const my $JSON           => { Accept => 'application/json' };

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all =>
      'set GPFORUM_TEST_DSN for the complete draft composer flow';
}
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $test   = Test::Mojo->new('GPForum');
my $routes = $test->app->routes;
$routes->get('/__test/draft-session')->to(
    cb => sub ($c) {
        $c->session( user_id => seed_id( user => 2 ) );
        return $c->render( json => { ok => 1 } );
    }
);
$test->get_ok('/__test/draft-session')->status_is($HTTP_OK);
$test->get_ok('/new-thread')->status_is($HTTP_OK);
my $page   = $test->tx->res->dom;
my %thread = _fields( $page->at('form[data-composer]') );
$thread{category_id} = seed_id( category => 1 );
$thread{title}       = q{};
$thread{body_source} = "  body survives invalid publication\n";
$test->post_ok( '/drafts' => $JSON => form => \%thread )->status_is($HTTP_OK);
my $draft = _json($test)->{draft};
$thread{draft_revision} = $draft->{draft_revision};
$thread{command_id}     = $draft->{command_id};

# Native validation failures retain a saved draft and its raw source. A save
# after the recorded refusal rotates the publish command before the next try.
$test->post_ok( '/threads' => $JSON => form => \%thread )
  ->status_is($HTTP_INVALID);
$test->get_ok("/drafts/$thread{draft_id}")->status_is($HTTP_OK);
$test->text_is( '#thread-body' => $thread{body_source} );
$thread{title} = 'Draft publication through PostgreSQL';
$test->post_ok( '/drafts' => $JSON => form => \%thread )->status_is($HTTP_OK);
$draft = _json($test)->{draft};
isnt( $draft->{command_id}, $thread{command_id},
    'a refused command is replaced for the corrected draft' );
$thread{draft_revision} = $draft->{draft_revision};
$thread{command_id}     = $draft->{command_id};
$test->post_ok( '/threads' => $JSON => form => \%thread )
  ->status_is($HTTP_CREATED);
my $created   = $test->tx->res->json;
my $thread_id = $created->{thread_id};
ok( $thread_id, 'publication returns a thread' );
$test->get_ok( "/drafts/$thread{draft_id}" => $JSON )
  ->status_is($HTTP_NOT_FOUND);
$test->post_ok( '/threads' => $JSON => form => \%thread )
  ->status_is($HTTP_CREATED);
$test->json_is( '/thread_id' => $thread_id );

# A restored reply posts through the same atomic routine and then disappears.
$test->get_ok("/t/$thread_id")->status_is($HTTP_OK);
$page = $test->tx->res->dom;
my %reply = _fields( $page->at('form[data-composer]') );
$reply{body_source} = 'Restored private reply';
$test->post_ok( '/drafts' => $JSON => form => \%reply )->status_is($HTTP_OK);
$draft                 = _json($test)->{draft};
$reply{draft_revision} = $draft->{draft_revision};
$reply{command_id}     = $draft->{command_id};
$test->get_ok("/drafts/$reply{draft_id}")->status_is($HTTP_OK);
$test->text_is( '#reply-body' => $reply{body_source} );
$test->post_ok( "/t/$thread_id/replies" => $JSON => form => \%reply )
  ->status_is($HTTP_CREATED);
my $post_id = _json($test)->{post_id};
ok( $post_id, 'reply publication returns a post' );
$test->get_ok( "/drafts/$reply{draft_id}" => $JSON )
  ->status_is($HTTP_NOT_FOUND);
$test->post_ok( "/t/$thread_id/replies" => $JSON => form => \%reply )
  ->status_is($HTTP_CREATED);
$test->json_is( '/post_id' => $post_id );

# A native fresh form never receives a saved revision before publication.
# Reposting its original revision-zero fields must resolve the same command.
$test->get_ok('/new-thread')->status_is($HTTP_OK);
$page = $test->tx->res->dom;
my %native = _fields( $page->at('form[data-composer]') );
$native{category_id} = seed_id( category => 1 );
$native{title}       = 'Native draft publication';
$native{body_source} = 'Native body';
$test->post_ok( '/threads' => form => \%native )->status_is($HTTP_FOUND);
my $native_url = _location($test);
$test->post_ok( '/threads' => form => \%native )->status_is($HTTP_FOUND);
$test->header_is( Location => $native_url );
$test->get_ok($native_url)->status_is($HTTP_OK);
$page = $test->tx->res->dom;
my %native_reply = _fields( $page->at('form[data-composer]') );
$native_reply{body_source} = 'Native reply body';
my $reply_url = $page->at('form[data-composer]')->attr('action');
$test->post_ok( $reply_url => form => \%native_reply )->status_is($HTTP_FOUND);
my $native_post_url = _location($test);
$test->post_ok( $reply_url => form => \%native_reply )->status_is($HTTP_FOUND);
$test->header_is( Location => $native_post_url );

# Native publication may itself save an edit to the acknowledged revision.
# The original POST's pre-save revision must also replay after consumption.
$test->get_ok('/new-thread')->status_is($HTTP_OK);
$page = $test->tx->res->dom;
my %edited = _fields( $page->at('form[data-composer]') );
$edited{category_id} = seed_id( category => 1 );
$edited{title}       = 'Before native edit';
$edited{body_source} = 'Before native edit';
$test->post_ok( '/drafts' => $JSON => form => \%edited )->status_is($HTTP_OK);
$draft                  = _json($test)->{draft};
$edited{draft_revision} = $draft->{draft_revision};
$edited{command_id}     = $draft->{command_id};
$edited{title}          = 'After native edit';
$edited{body_source}    = 'After native edit';
$test->post_ok( '/threads' => form => \%edited )->status_is($HTTP_FOUND);
my $edited_url = _location($test);
$test->post_ok( '/threads' => form => \%edited )->status_is($HTTP_FOUND);
$test->header_is( Location => $edited_url );
my $app_schema = $test->app->gp_schema;
$app_schema->storage->disconnect;
done_testing;

sub _location ($client) {
    my $response = $client->tx->res;
    return $response->headers->location;
}

sub _json ($client) {
    return $client->tx->res->json;
}

sub _fields ($form) {
    return
      map { $_->attr('name') => $_->attr('value') }
      @{ $form->find('input[name]')->to_array };
}

1;
