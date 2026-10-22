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
use GPForum::Command::AdminBootstrap;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Moderation::AutomodStore;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';

const my $HTTP_OK        => 200;
const my $HTTP_CREATED   => 201;
const my $HTTP_FOUND     => 302;
const my $HTTP_INVALID   => 400;
const my $HTTP_FORBIDDEN => 403;
const my $HTTP_CONFLICT  => 409;
const my $MAXIMUM        => 500;
const my $JSON           => { Accept => 'application/json' };

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for watched words and automod';
}

# ADR 0133 on a migrated, seeded PostgreSQL: the rules' functions and their
# audit, the system's reports, the screening of threads, replies and edits,
# and the admin console's page and forms.
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $schema    = $database->schema;
my $dbh       = $database->dbh;
my $ids       = GPForum::Infrastructure::Id->new;
my $functions = GPForum::Infrastructure::SqlFunction->new( schema => $schema );
my $store     = GPForum::Service::Moderation::AutomodStore->new(
    schema    => $schema,
    functions => $functions
);
my $member      = seed_id( user => 2 );
my $admin       = _administrator();
my ($thread_id) = $dbh->selectrow_array(
        q{SELECT t.thread_id FROM threads t WHERE t.deleted_at IS NULL}
      . q{ AND t.locked_at IS NULL AND t.moderation_state = 'visible'}
      . q{ ORDER BY t.thread_id LIMIT 1} );

subtest 'staff keep the list and the link rule, every change audited' => sub {
    my $added = $store->add_word(
        { actor_user_id => $admin, phrase => '  Spam* ', action => 'flag' } );
    is_deeply(
        [ @{$added}{qw(ok status)}, $added->{word}{phrase} ],
        [ 1, 'ok', 'spam*' ],
        'a word is added as kept'
    );
    is(
        $store->add_word(
            { actor_user_id => $admin, phrase => 'SPAM*', action => 'block' }
        )->{status},
        'duplicate',
        'the same phrase twice is a duplicate'
    );
    is_deeply(
        $store->add_word(
            { actor_user_id => $admin, phrase => 'a*b', action => 'flag' }
        ),
        { ok => 0, status => 'invalid', field => 'phrase' },
        'a star inside a phrase is not one'
    );
    is(
        $store->add_word(
            { actor_user_id => $admin, phrase => 'x', action => 'ban' }
        )->{field},
        'action',
        'an unknown action is invalid'
    );
    is(
        $functions->row(
            'moderation_watched_word_add',
            {
                word_id       => $ids->uuid,
                phrase        => 'x',
                action        => 'ban',
                replacement   => q{},
                actor_user_id => $admin,
                now           => '2026-10-15T00:00:00Z',
                audit         => {},
            }
        )->{status},
        'invalid',
        'and the function refuses it as well'
    );
    my $gone = $store->add_word(
        { actor_user_id => $admin, phrase => 'gone', action => 'block' } );
    is_deeply(
        [ map { $_->{phrase} } @{ $store->words } ],
        [ 'gone', 'spam*' ],
        'the list is in phrase order'
    );
    is( $store->words->[0]{created_by_username},
        'automod_admin', 'and names who added each word' );
    is(
        $store->remove_word(
            { actor_user_id => $admin, word_id => $gone->{word}{word_id} }
        )->{removed},
        1,
        'a word is removed'
    );
    is(
        $store->remove_word(
            { actor_user_id => $admin, word_id => $gone->{word}{word_id} }
        )->{removed},
        0,
        'removing it again removes nothing'
    );
    is( _audits('automod.word_added'),   2, 'each addition is audited' );
    is( _audits('automod.word_removed'), 1, 'and the one removal' );
    is(
        $dbh->selectrow_array(
                q{SELECT metadata->>'phrase' FROM audit_log}
              . q{ WHERE action = 'automod.word_removed'}
        ),
        'gone',
        'with the phrase removed'
    );

    is_deeply(
        $store->set_link_rule(
            {
                actor_user_id    => $admin,
                link_limit       => '1',
                link_trust_below => '1',
                link_action      => 'block'
            }
        ),
        { ok => 1, status => 'ok' },
        'the link rule is set'
    );
    is(
        $store->set_link_rule(
            {
                actor_user_id    => $admin,
                link_limit       => '1',
                link_trust_below => '1',
                link_action      => 'block'
            }
        )->{status},
        'unchanged',
        'setting it again changes nothing'
    );
    is(
        $store->set_link_rule(
            {
                actor_user_id    => $admin,
                link_limit       => '101',
                link_trust_below => '1',
                link_action      => 'block'
            }
        )->{field},
        'link_limit',
        'a limit above 100 is invalid'
    );
    is( _audits('automod.link_rule_set'), 1, 'the change is audited once' );
    my $rules = $store->rules_for($member);
    is_deeply(
        [ @{$rules}{qw(link_limit link_trust_below link_action)} ],
        [ 1, 1, 'block' ],
        'the rules carry the link rule'
    );
    ok( defined $rules->{trust_level}, 'and the author\'s trust level' );
    is( $store->rules_for(undef)->{trust_level},
        undef, 'which is unknown for nobody' );
    $store->set_link_rule(
        {
            actor_user_id    => $admin,
            link_limit       => q{},
            link_trust_below => '1',
            link_action      => 'block'
        }
    );
    is( $store->rules_for($member)->{link_limit},
        undef, 'an empty limit turns the rule off' );
};

subtest 'the list holds at most 500 words' => sub {
    my $insert = $dbh->prepare(
            q{INSERT INTO watched_words (word_id, phrase, action, created_at)}
          . q{ VALUES (?, ?, 'flag', now())} );
    my $listed = scalar @{ $store->words };
    for my $number ( 1 .. $MAXIMUM - $listed ) {
        $insert->execute( $ids->uuid, "filler$number" );
    }
    is(
        $store->add_word(
            { actor_user_id => $admin, phrase => 'one more', action => 'flag' }
        )->{status},
        'limit',
        'the 501st is refused'
    );
    $dbh->do(q{DELETE FROM watched_words WHERE phrase LIKE 'filler%'});
};

subtest 'a flag is one open system report per target' => sub {
    my ($post_id) = $dbh->selectrow_array(
        q{SELECT post_id FROM posts WHERE thread_id = ? LIMIT 1},
        undef, $thread_id );
    my $flag = {
        target_type => 'post',
        target_id   => $post_id,
        reason      => 'automod.watched_word',
        details     => '"spam*"'
    };
    my $audit = {
        action      => 'automod.flagged',
        actor_id    => undef,
        target_type => 'post',
        target_id   => $post_id,
        metadata    => {},
    };
    my $first =
      $store->record_decisions( { report => $flag, audits => [$audit] } );
    ok( $first->{flagged}, 'the first flag opens a report' );
    my $again =
      $store->record_decisions( { report => $flag, audits => [$audit] } );
    is_deeply(
        [ $again->{flagged}, $again->{report_id} ],
        [ 0,                 $first->{report_id} ],
        'a second flag reuses it'
    );
    my $report =
      $dbh->selectrow_hashref( q{SELECT * FROM reports WHERE report_id = ?},
        undef, $first->{report_id} );
    is_deeply(
        [ @{$report}{qw(reporter_user_id status reason)} ],
        [ undef, 'open', 'automod.watched_word' ],
        'the system reports it, open, naming the rule'
    );
    is(
        $dbh->selectrow_array(
q{SELECT count(*) FROM event_log WHERE event_type = 'report.created'}
              . q{ AND aggregate_id = ?},
            undef,
            $first->{report_id}
        ),
        1,
        'its report.created event is recorded once'
    );
    is( _audits('automod.flagged'), 2, 'every decision is audited' );
    $dbh->do(
        q{UPDATE reports SET status = 'resolved', resolved_at = now()}
          . q{ WHERE report_id = ?},
        undef, $first->{report_id}
    );
};

subtest 'threads, replies and edits are screened' => sub {
    my $test = _session($member);
    $dbh->do( q{UPDATE users SET trust_level = 0 WHERE id = ?}, undef,
        $member );
    $store->add_word(
        { actor_user_id => $admin, phrase => 'forbidden', action => 'block' } );
    $store->add_word(
        {
            actor_user_id => $admin,
            phrase        => 'darn',
            action        => 'replace',
            replacement   => 'gosh'
        }
    );
    my $before = _posts();
    my $reply  = sub ($body) {
        $test->get_ok("/t/$thread_id")->status_is($HTTP_OK);
        my %form = _composer($test);
        $form{body_source} = $body;
        $test->post_ok( "/t/$thread_id/replies" => $JSON => form => \%form );
        return $test->tx->res->json // {};
    };

    my $blocked = $reply->('This is FORBIDDEN talk');
    $test->status_is($HTTP_INVALID);
    like( $blocked->{errors}{body_source},
        qr/forbidden/msx, 'a blocked reply names the word' );
    is( _posts(),                   $before, 'and nothing is stored' );
    is( _audits('automod.blocked'), 1,       'the block is audited' );

    my $replaced = $reply->('Well, darn it.');
    $test->status_is($HTTP_CREATED);
    is(
        _body( $replaced->{post_id} ),
        'Well, gosh it.',
        'a replaced word is stored replaced'
    );
    is( _audits('automod.replaced'), 1, 'and the replacement audited' );

    my $flagged = $reply->('Spammers everywhere');
    $test->status_is($HTTP_CREATED);
    my $report = $dbh->selectrow_hashref(
        q{SELECT * FROM reports WHERE target_id = ? AND status = 'open'},
        undef, $flagged->{post_id} );
    is_deeply(
        [ @{ $report // {} }{qw(reporter_user_id target_type reason)} ],
        [ undef, 'post', 'automod.watched_word' ],
        'a flagged reply is stored and put in the queue'
    );

    $store->set_link_rule(
        {
            actor_user_id    => $admin,
            link_limit       => '1',
            link_trust_below => '1',
            link_action      => 'block'
        }
    );
    my $links = $reply->('See https://a.example and www.b.example');
    $test->status_is($HTTP_INVALID);
    like( $links->{errors}{body_source},
        qr/\b1\b/msx, 'too many links from a new member are refused' );
    $dbh->do( q{UPDATE users SET trust_level = 1 WHERE id = ?}, undef,
        $member );
    $reply->('See https://a.example and www.b.example');
    $test->status_is( $HTTP_CREATED, 'a trusted member posts them' );
    $dbh->do( q{UPDATE users SET trust_level = 0 WHERE id = ?}, undef,
        $member );

    $test->post_ok(
        "/p/$replaced->{post_id}" => $JSON => form => {
            csrf_token  => _csrf($test),
            command_id  => $ids->uuid,
            body_source => 'Edited to say forbidden',
        }
    )->status_is($HTTP_INVALID);
    is(
        _body( $replaced->{post_id} ),
        'Well, gosh it.',
        'an edit is screened as well'
    );

    $test->get_ok('/new-thread')->status_is($HTTP_OK);
    my %thread = _composer($test);
    $test->post_ok(
        '/threads' => form => {
            %thread,
            category_id => seed_id( category => 1 ),
            title       => 'A forbidden title',
            body_source => 'An ordinary body',
        }
    )->status_is($HTTP_INVALID);
    $test->content_like( qr/not [ ] allowed [ ] here: [ ] forbidden/msx,
        'the form comes back saying why' );
    $test->element_exists( 'input[name=title][value="A forbidden title"]',
        'with the title kept' );

    my $staff = _session($admin);
    $staff->get_ok("/t/$thread_id")->status_is($HTTP_OK);
    my %form = _composer($staff);
    $staff->post_ok(
        "/t/$thread_id/replies" => $JSON => form => {
            %form, body_source => 'Quoting: forbidden'
        }
    )->status_is( $HTTP_CREATED, 'staff who moderate are not screened' );
};

subtest 'the admin console page and forms' => sub {
    my $test = _session($admin);
    $test->get_ok('/admin/automod')->status_is($HTTP_OK);
    $test->element_exists('form[action="/admin/automod/words"]');
    $test->element_exists('form[action="/admin/automod/links"]');
    $test->text_like( 'table code' => qr/darn|forbidden|spam/msx );
    my $csrf = _csrf($test);

    $test->post_ok( '/admin/automod/words' => form => { phrase => 'nope' } )
      ->status_is($HTTP_FORBIDDEN);
    $test->post_ok(
        '/admin/automod/words' => form => {
            csrf_token => $csrf,
            phrase     => 'Casino',
            action     => 'flag'
        }
    )->status_is($HTTP_FOUND);
    $test->get_ok('/admin/automod')
      ->content_like(qr/Watched [ ] word [ ] added/msx);
    $test->post_ok(
        '/admin/automod/words' => $JSON => form => {
            csrf_token => $csrf,
            phrase     => 'casino',
            action     => 'flag'
        }
    )->status_is($HTTP_CONFLICT)->json_is( '/status' => 'duplicate' );
    my ($casino) =
      grep { $_->{phrase} eq 'casino' } @{ $store->words };
    $test->post_ok( "/admin/automod/words/$casino->{word_id}/remove" => form =>
          { csrf_token => $csrf } )->status_is($HTTP_FOUND);
    ok( !grep( { $_->{phrase} eq 'casino' } @{ $store->words } ),
        'the form removes it' );
    $test->post_ok(
        '/admin/automod/links' => $JSON => form => {
            csrf_token       => $csrf,
            link_limit       => '3',
            link_trust_below => '2',
            link_action      => 'flag'
        }
    )->status_is($HTTP_OK)->json_is( '/status' => 'ok' );
    is( $store->rules_for(undef)->{link_action}, 'flag', 'and sets the rule' );

    $test->get_ok('/moderation/reports')->status_is($HTTP_OK);
    $test->content_like( qr/Automod/msx,
        'the queue names the system as the reporter' );

    my $reader = _session($member);
    $reader->get_ok('/admin/automod')->status_is($HTTP_FORBIDDEN);
    $reader->post_ok(
        '/admin/automod/words' => form => {
            csrf_token => _csrf($reader),
            phrase     => 'mine',
            action     => 'flag'
        }
    )->status_is( $HTTP_FORBIDDEN, 'a member changes nothing' );
};

done_testing();

sub _audits ($action) {
    return
      scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM audit_log WHERE action = ?},
        undef, $action );
}

sub _posts {
    return
      scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM posts WHERE thread_id = ?},
        undef, $thread_id );
}

sub _body ($post_id) {
    return scalar $dbh->selectrow_array(
        q{SELECT b.body_source FROM posts p JOIN post_bodies b}
          . q{ ON b.body_id = p.current_body_id WHERE p.post_id = ?},
        undef, $post_id
    );
}

sub _composer ($test) {
    my $dom = $test->tx->res->dom;

    return _fields( $dom->at('form[data-composer]') );
}

sub _fields ($form) {
    return
      map { $_->attr('name') => $_->attr('value') }
      @{ $form->find('input[name]')->to_array };
}

sub _csrf ($test) {
    $test->get_ok('/settings');
    my $dom   = $test->tx->res->dom;
    my $input = $dom->at('input[name=csrf_token]');

    return $input ? $input->attr('value') : q{};
}

# A browser signed in as the user.
sub _session ($user_id) {
    my $test   = Test::Mojo->new('GPForum');
    my $routes = $test->app->routes;
    $routes->get('/__test/automod-session')->to(
        cb => sub ($c) {
            $c->session( user_id => $user_id );
            return $c->render( json => { ok => 1 } );
        }
    );
    $test->get_ok('/__test/automod-session')->status_is($HTTP_OK);

    return $test;
}

# A user given the bootstrap administration role.
sub _administrator {
    my ($id) = $dbh->selectrow_array(
            q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{ password_hash, status) VALUES (gen_random_uuid(),}
          . q{ 'automod_admin', 'Automod admin', 'automod-admin@example.test',}
          . q{ 'x', 'active') RETURNING id} );
    GPForum::Test::PostgresHarness::quietly(
        sub {
            return GPForum::Command::AdminBootstrap->new->run( 'grant',
                '--user-id', $id );
        }
    );

    return $id;
}

1;
