# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Forum::BodyLength;
use GPForum::Service::Forum::DraftStore;
use GPForum::Service::Forum::PostComposer;
use GPForum::Service::Forum::ThreadComposer;
use GPForum::Test::DraftWebStore;
use GPForum::Test::ForumWebServices;
use GPForum::Test::RecordingFunctions;
use GPForum::Test::ScriptedWorkflow;

our $VERSION = '0.001';

# ADR 0140: one maximum length for a post body, whatever writes it -- a new
# thread, a reply, an edit, a preview or a draft -- refused in the reader's
# language. Before it only drafts had one, and a reply could be any length.

const my $MAXIMUM         => 50_000;
const my $HTTP_BAD        => 400;
const my $TOO_LONG        => 'body is too long';
const my $ENGLISH_REFUSAL => qr/at[ ]most[ ]50000[ ]characters/msx;
const my $ITALIAN_REFUSAL => qr/al[ ]massimo[ ]50000[ ]caratteri/msx;

my $longest   = 'x' x $MAXIMUM;
my $too_long  = $longest . 'x';
my $body_hash = 'hash-1';

is( GPForum::Service::Forum::BodyLength->maximum, $MAXIMUM, 'the one limit' );
is( GPForum::Service::Forum::BodyLength->error($longest),
    undef, 'the longest body is accepted' );
is( GPForum::Service::Forum::BodyLength->error($too_long),
    $TOO_LONG, 'one character more is refused' );
is(
    GPForum::Service::Forum::BodyLength->error(q{}),
    'body is required',
    'an empty body is refused'
);
is(
    GPForum::Service::Forum::BodyLength->error(undef),
    'body is required',
    'no body is refused'
);

subtest 'a reply and an edit' => sub {
    my $composer = GPForum::Service::Forum::PostComposer->new;
    my %reply    = (
        allocate_position => 1,
        author_user_id    => 'user-1',
        body_hash         => $body_hash,
        idempotency_key   => 'command-1',
        thread_id         => 'thread-1',
    );
    ok( $composer->prepare( { %reply, body_source => $longest } )->{ok},
        'a reply at the limit is prepared' );
    my $refused = $composer->prepare( { %reply, body_source => $too_long } );
    ok( !$refused->{ok}, 'a reply past the limit is refused' );
    is( $refused->{errors}{body_source}, $TOO_LONG, 'on the body' );

    my %edit = (
        body_hash       => $body_hash,
        editor_user_id  => 'user-1',
        idempotency_key => 'command-2',
        post_id         => 'post-1',
        thread_id       => 'thread-1',
    );
    ok(
        $composer->prepare_revision( { %edit, body_source => $longest } )->{ok},
        'an edit at the limit is prepared'
    );
    is(
        $composer->prepare_revision( { %edit, body_source => $too_long } )
          ->{errors}{body_source},
        $TOO_LONG,
        'an edit past the limit is refused'
    );
};

subtest 'a thread' => sub {
    my $composer = GPForum::Service::Forum::ThreadComposer->new;
    my %thread   = (
        author_user_id  => 'user-1',
        body_hash       => $body_hash,
        category_id     => 'category-1',
        idempotency_key => 'command-3',
        title           => 'A long thread',
    );
    ok( $composer->prepare( { %thread, body_source => $longest } )->{ok},
        'a thread at the limit is prepared' );
    is(
        $composer->prepare( { %thread, body_source => $too_long } )
          ->{errors}{body_source},
        $TOO_LONG,
        'a thread past the limit is refused'
    );
};

subtest 'a draft' => sub {
    my $functions = GPForum::Test::RecordingFunctions->new;
    my $store     = GPForum::Service::Forum::DraftStore->new(
        functions => $functions,
        schema    => {},
    );
    my $saved = $store->save(
        {
            body_source    => $too_long,
            command_id     => 'command-4',
            draft_id       => '018f1006-0010-7000-8000-000000000009',
            draft_revision => 0,
            kind           => 'reply',
            owner_user_id  => '018f1006-0010-7000-8000-000000000001',
            thread_id      => '018f1006-0010-7000-8000-000000000002',
        }
    );
    is( $saved->{errors}{body_source},
        $TOO_LONG, 'a draft past the limit is refused' );
    is( scalar @{ $functions->calls }, 0, 'before the database is asked' );
};

subtest 'the reader is told in their language' => sub {
    my $test     = Test::Mojo->new('GPForum');
    my $services = GPForum::Test::ForumWebServices->new;
    for my $helper (
        qw(gp_category_reader gp_thread_reader gp_thread_detail_reader
        gp_post_reader gp_thread_read_state gp_attachment_store gp_rate_limiter
        gp_suspension_store gp_bookmark_store gp_like_store gp_reaction_store gp_reply_links
        gp_subscription_store)
      )
    {
        $test->app->helper( $helper => sub { return $services; } );
    }
    $test->app->helper(
        gp_draft_store => sub { return GPForum::Test::DraftWebStore->new; } );

    # The posting workflow's answer for a reply its composer refuses.
    my $workflow = GPForum::Test::ScriptedWorkflow->new(
        answer => {
            ok       => 0,
            prepared => GPForum::Service::Forum::PostComposer->new->prepare(
                {
                    allocate_position => 1,
                    author_user_id    => 'user-1',
                    body_hash         => $body_hash,
                    body_source       => $too_long,
                    idempotency_key   => 'command-5',
                    thread_id         => 'thread-1',
                }
            ),
            status => 'invalid',
        }
    );
    $test->app->helper( gp_posting_workflow => sub { return $workflow; } );
    my $routes = $test->app->routes;
    $routes->get('/__test/session/:user_id')->to(
        cb => sub ($c) {
            $c->session( user_id => $c->param('user_id') );
            return $c->render( json => { ok => 1 } );
        }
    );
    $test->get_ok('/__test/session/user-1');
    $test->get_ok('/new-thread');
    my $page  = $test->tx->res->dom;
    my $form  = $page->at('form[data-composer]');
    my %input = map { $_->attr('name') => $_->attr('value') }
      @{ $form->find('input[name]')->to_array };
    $input{body_source} = $too_long;
    my %english = ( Accept => 'application/json', 'Accept-Language' => 'en' );
    my %italian = ( Accept => 'application/json', 'Accept-Language' => 'it' );

    $test->post_ok( '/composer/preview' => \%english => form => \%input )
      ->status_is($HTTP_BAD)
      ->json_like( '/error' => $ENGLISH_REFUSAL );
    $test->post_ok( '/composer/preview' => \%italian => form => \%input )
      ->status_is($HTTP_BAD)
      ->json_like( '/error' => $ITALIAN_REFUSAL );

    my %reply = (
        body_source => $too_long,
        command_id  => $input{command_id},
        csrf_token  => $input{csrf_token},
    );
    $test->post_ok( '/t/thread-1/replies' => \%italian => form => \%reply )
      ->status_is($HTTP_BAD)
      ->json_like( '/errors/body_source' => $ITALIAN_REFUSAL );
};

done_testing();

1;
