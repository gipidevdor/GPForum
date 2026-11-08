# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

# The admin console's writes and reads as the web worker runs them. Without
# a METHOD_p call_p ran each one in a forked child that opened a PostgreSQL
# connection of its own, one child at a time per worker. Each promise here
# runs on its own fixture beside its blocking method and must answer the
# same, write the same rows, and never reach the fork fallback.
package main;
use v5.40;
use Const::Fast;
use Digest::SHA qw(sha256_hex);
use Test::More;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Command::AdminBootstrap;
use GPForum::Config;
use GPForum::Infrastructure::AsyncWork;
use GPForum::Infrastructure::Id;
use GPForum::Service::Identity::Admission;
use GPForum::Service::Integration::Announcements;
use GPForum::Service::Integration::Syndication;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;
use GPForum::Test::Forks        qw(children_during);
use GPForum::Test::Promise      qw(await_result);
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';
const my $SOURCE => 'https://feeds.example.org/news.xml';
const my $UUID =>
  qr/[[:xdigit:]]{8} (?: - [[:xdigit:]]{4} ){3} - [[:xdigit:]]{12}/msx;
const my $TIME => qr/\A \d{4} - \d\d - \d\d [T ] \d\d : \d\d/msx;

# Two rejected, two published, one whose decision is refused.
const my $FEED_ITEMS => 5;

# What tells the two ways' fixtures apart.
const my %OTHER_SLUG =>
  ( blocking => 'category-promise', promise => 'category-blocking' );
const my %RANGE => ( blocking => '203.0.113.0/24', promise => '192.0.2.0/24' );
const my %MODE  => ( blocking => 'invite',         promise => 'open' );
const my %ENABLED => ( blocking => 1, promise => 0 );

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to compare admin write promises';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
my $dbh   = $database->dbh;
my $owner = seed_id( user => 1 );
GPForum::Test::PostgresHarness::quietly(
    sub {
        return GPForum::Command::AdminBootstrap->new(
            schema => $database->schema )->run( 'grant', '--user-id', $owner );
    }
);

my $t = Test::Mojo->new('GPForum');
my $c = $t->app->build_controller;
$c->session( user_id => $owner );
my $ids = GPForum::Infrastructure::Id->new;

# Every promise below runs with the children AsyncWork starts recorded.
my @forked;

subtest 'catalog, binding and category commands' => sub {
    my $workflow = $c->gp_admin_workflow;
    my %role     = same_effect( $workflow, 'create_role',
        command( name => 'role-blocking', description => 'fixture' ) );
    my %permission = same_effect(
        $workflow,
        'create_permission',
        command(
            name          => 'perm-blocking',
            resource_type => 'kind_blocking',
            action        => 'read'
        )
    );
    for my $way (qw(blocking promise)) {
        my $answer = run_way(
            $way,
            $workflow,
            'attach_permission',
            command(
                role_id       => $role{$way}{stored}{role_id},
                permission_id => $permission{$way}{stored}{permission_id},
            )
        );
        is( $answer->{status}, 'ok', "attach_permission ($way)" );
        is(
            audits( 'role_permission.attached', $role{$way}{stored}{role_id} ),
            1,
            "attach_permission ($way) audited once"
        );
    }

    my $repeat = command( name => 'role-repeat' );
    my $first  = run_way( 'promise', $workflow, 'create_role', $repeat );
    is_deeply( run_way( 'promise', $workflow, 'create_role', $repeat ),
        $first, 'a repeated command id answers the first answer' );
    is( commands( $repeat->{command_id} ),
        'handled', 'the command log holds the handled command' );
    is_deeply(
        run_way( 'promise', $workflow, 'create_role', command() ),
        $workflow->create_role( command() ),
        'a role without a name is refused alike'
    );

    my $member = seed_id( user => 3 );
    for my $way (qw(blocking promise)) {
        my $bound = run_way(
            $way,
            $workflow,
            'bind_role',
            command(
                user_id       => $member,
                role_id       => $role{$way}{stored}{role_id},
                resource_type => 'global',
            )
        );
        is( $bound->{status}, 'ok', "bind_role ($way)" );
        my $binding = $bound->{stored}{binding}{binding_id};
        my $revoked =
          run_way( $way, $workflow, 'revoke_binding',
            command( binding_id => $binding ) );
        is( $revoked->{status}, 'ok', "revoke_binding ($way)" );
        is(
            $dbh->selectrow_array(
                'SELECT count(*) FROM role_bindings'
                  . ' WHERE binding_id = ? AND revoked_at IS NOT NULL',
                undef,
                $binding
            ),
            1,
            "revoke_binding ($way) revoked the binding"
        );
        is( audits( 'role_binding.revoked', $binding ),
            1, "revoke_binding ($way) audited once" );
    }

    my %category = same_effect( $workflow, 'create_category',
        command( title => 'Category blocking', slug => 'category-blocking' ) );
    for my $way (qw(blocking promise)) {
        my $updated = run_way(
            $way,
            $workflow,
            'update_category',
            command(
                category_id => $category{$way}{stored}{category_id},
                title       => "Renamed $way",
            )
        );
        is(
            $updated->{stored}{title},
            "Renamed $way",
            "update_category ($way)"
        );
        my $taken = run_way(
            $way,
            $workflow,
            'update_category',
            command(
                category_id => $category{$way}{stored}{category_id},
                slug        => $OTHER_SLUG{$way},
            )
        );
        is_deeply(
            $taken->{errors},
            { slug => 'slug is taken' },
            "update_category ($way) refuses a taken slug"
        );
    }
};

subtest 'announcements, maintenance, diagnostics and replays' => sub {
    my $workflow  = $c->gp_admin_workflow;
    my %published = same_effect( $workflow, 'create_announcement',
        command( message => 'Notice blocking', tone => 'notice' ) );
    for my $way (qw(blocking promise)) {
        my $retired = run_way(
            $way,
            $workflow,
            'retire_announcement',
            command(
                announcement_id => $published{$way}{stored}{announcement_id}
            )
        );
        ok( $retired->{stored}{retired_at}, "retire_announcement ($way)" );
    }
    for my $method (
        qw(purge_public_cache request_search_rebuild send_test_mail
        check_antivirus)
      )
    {
        same_effect( $workflow, $method, command() );
    }
    same_effect( $workflow, 'replay_dead_letter',
        command( dead_letter_id => $ids->uuid ) );
};

subtest 'address bans, admission, configuration and two-step policy' => sub {
    my $bans = $c->gp_address_bans;
    for my $way (qw(blocking promise)) {
        my $range  = $RANGE{$way};
        my $placed = run_way(
            $way, $bans, 'place',
            {
                actor_user_id => $owner,
                actor_address => '198.18.0.1',
                command_id    => $ids->uuid,
                range         => $range,
                scope         => 'writes',
                reason        => 'fixture',
                duration      => '1d',
            }
        );
        is( $placed->{status}, 'ok', "place ($way)" );
        my $edited = run_way(
            $way, $bans, 'edit',
            {
                actor_user_id => $owner,
                actor_address => '198.18.0.1',
                ban_id        => $placed->{ban_id},
                scope         => 'sign_in',
                reason        => 'edited',
            }
        );
        is( $edited->{status}, 'ok', "edit ($way)" );
        my $lifted = run_way( $way, $bans, 'lift',
            { actor_user_id => $owner, ban_id => $placed->{ban_id} } );
        is( $lifted->{status}, 'ok', "lift ($way)" );
    }
    same_answer(
        $bans, 'place',
        [ { range => 'nonsense' } ],
        'place refuses a range'
    );

    my $admission =
      GPForum::Service::Identity::Admission->new( schema => $c->gp_schema );
    for my $way (qw(blocking promise)) {
        my $changed = run_way(
            $way,
            $admission,
            'change',
            {
                actor             => $owner,
                command           => $ids->uuid,
                operation         => 'policy',
                mode              => $MODE{$way},
                approval_required => 0,
            }
        );
        is( $changed->{status}, 'ok', "admission change ($way)" );
    }

    my $configuration = $c->gp_configuration;
    same_answer( $configuration, 'fields', [], 'configuration fields' );
    for my $way (qw(blocking promise)) {
        my $saved = run_way(
            $way,
            fresh_configuration(),
            'save_general',
            {
                actor    => $owner,
                command  => $ids->uuid,
                expected => revision(),
                values   => { GPFORUM_SITE_NAME => "Forum $way" },
            }
        );
        is( $saved->{status}, 'ok', "save_general ($way)" );
        my $reset = run_way(
            $way,
            fresh_configuration(),
            'reset_general',
            {
                actor    => $owner,
                command  => $ids->uuid,
                expected => revision(),
                key      => 'GPFORUM_SITE_NAME',
            }
        );
        is( $reset->{status}, 'ok', "reset_general ($way)" );
        my $plugin = run_way(
            $way,
            fresh_configuration(),
            'save_plugin',
            {
                actor    => $owner,
                command  => $ids->uuid,
                expected => revision(),
                plugin   => 'youtube',
                enabled  => $ENABLED{$way},
                mode     => 'link',
            }
        );
        is( $plugin->{status}, 'ok', "save_plugin ($way)" );
    }

    my $second_factor = $c->gp_second_factor;
    same_answer(
        $second_factor, 'set_policy',
        [ 1, $owner ],
        'set_policy without an own second factor'
    );
    same_answer(
        $second_factor,           'member_summary',
        [ seed_id( user => 3 ) ], 'member_summary'
    );
    is_deeply(
        await_promise(
            $second_factor, 'reset_member', seed_id( user => 4 ), $owner
        ),
        $second_factor->reset_member( seed_id( user => 5 ), $owner ),
        'reset_member answers alike'
    );
};

subtest 'console reads' => sub {
    same_answer(
        $c->gp_permission_review,    'roles_for_user',
        [ $owner, { limit => 10 } ], 'roles_for_user'
    );
    same_answer( $c->gp_admin_maintenance, 'search_status', [],
        'search_status' );
    my $reader = $c->gp_admin_console_reader;
    my $promised =
      shape( await_promise( $reader, 'dashboard_summary', { limit => 5 } ) );
    my $blocking = shape( $reader->dashboard_summary( { limit => 5 } ) );

    # Readiness and metrics are their services' own reports, measured
    # afresh each time (collect is compared below); here only their place.
    ok(
        exists $promised->{health}{readiness}{status},
        'dashboard_summary: readiness has its place'
    );
    is_deeply(
        [ sort keys %{ $promised->{health}{metrics} } ],
        [ sort keys %{ $blocking->{health}{metrics} } ],
        'dashboard_summary: the same metrics'
    );
    for my $summary ( $promised, $blocking ) {
        delete @{ $summary->{health} }{qw(readiness metrics)};
    }
    is_deeply( $promised, $blocking, 'dashboard_summary: same sections' );
    is_deeply(
        [ sort keys %{ await_promise( $c->gp_metrics_snapshot, 'collect' ) } ],
        [ sort keys %{ $c->gp_metrics_snapshot->collect } ],
        'collect: same sections'
    );
    is(
        await_promise( $c->gp_metrics_snapshot, 'collect' )->{database}{status},
        'ok',
        'collect reads the database'
    );
};

subtest 'integrations' => sub {
    my %input = (
        schema           => $c->gp_schema,
        policy_available => 1,
        config           => GPForum::Config->from_environment(
            {
                %{ $c->gp_configuration->environment },
                GPFORUM_SYNDICATION_SOURCES => $SOURCE
            }
        ),
    );
    my $announcements =
      GPForum::Service::Integration::Announcements->new( %input,
        config => $c->gp_config );
    same_answer(
        $announcements, 'retry_checked',
        [ { actor_user_id => $owner, checked => 0, reason => q{} } ],
        'retry_checked refuses an unchecked retry'
    );
    my $feeds = GPForum::Service::Integration::Syndication->new(%input);
    is_deeply(
        shape( await_promise( $feeds, 'request', $owner, $SOURCE ) ),
        shape( $feeds->request( $owner, $SOURCE ) ),
        'request: the poll is queued alike'
    );
    my @items = feed_items($FEED_ITEMS);
    for my $way (qw(blocking promise)) {
        my $item   = shift @items;
        my $answer = run_way(
            $way, $feeds,
            'decide_with_posting',
            {
                actor_user_id => $owner,
                item_id       => $item,
                decision      => 'rejected',
            },
            $c->gp_posting_workflow,
            $c->gp_forum_viewer
        );
        is( $answer->{status}, 'ok', "decide_with_posting ($way)" );
        is( audits( 'integration.feed.rejected', $item ),
            1, "decide_with_posting ($way) audited once" );
    }
    is(
        await_promise(
            $feeds,
            'decide_with_posting',
            {
                actor_user_id => $owner,
                item_id       => $ids->uuid,
                decision      => 'rejected',
            },
            $c->gp_posting_workflow,
            $c->gp_forum_viewer
        )->{status},
        'not_found',
        'decide_with_posting of no item'
    );

    feed_publication( $feeds, @items );
};

subtest 'no promise reached the fork fallback' => sub {
    is_deeply( \@forked, [], 'no admin write forked a child' );
};

done_testing;

sub command (%fields) {
    return {
        actor_user_id => $owner,
        command_id    => $ids->uuid,
        %fields,
    };
}

# The method run blocking, or as its promise.
sub run_way ( $way, $service, $method, @arguments ) {
    return $service->$method(@arguments) if $way eq 'blocking';
    return await_promise( $service, $method, @arguments );
}

sub await_promise ( $service, $method, @arguments ) {
    my $async = $method . '_p';
    my $answer;
    my $children = children_during(
        sub { $answer = await_result( $service->$async( @arguments, undef ) ); }
    );
    push @forked, @{ $children->{other} };
    return $answer;
}

# Each way on its own command, the promise's with "promise" where the
# blocking one says "blocking": the answers alike but for ids and times,
# and each command logged alike. Answers both.
sub same_effect ( $service, $method, $blocking_command ) {
    my $blocking = $service->$method($blocking_command);
    my $command  = { %{$blocking_command}, command_id => $ids->uuid };
    for my $key ( keys %{$command} ) {
        next if !defined $command->{$key} || $command->{$key} !~ /blocking/msx;
        $command->{$key} =~ s/blocking/promise/gmsx;
    }
    my $promised = await_promise( $service, $method, $command );
    is_deeply( shape($promised), shape($blocking),
        "$method: promise = blocking" );
    is(
        commands( $command->{command_id} ),
        commands( $blocking_command->{command_id} ),
        "$method: the promise's command is logged as the blocking one's"
    );
    return ( blocking => $blocking, promise => $promised );
}

sub same_answer ( $service, $method, $arguments, $name ) {
    my $blocking = $service->$method( @{$arguments} );
    my $promised = await_promise( $service, $method, @{$arguments} );
    is_deeply( plain($promised), plain($blocking),
        "$name: promise = blocking" );
    return $promised;
}

# A value with its ids, times and the words that tell the fixtures apart
# replaced: what is left is the shape both ways must share.
sub shape ($value) {
    my $type = ref $value;
    return [ map { shape($_) } @{$value} ] if $type eq 'ARRAY';
    return { map { $_ => shape( $value->{$_} ) } keys %{$value} }
      if $type eq 'HASH' || ( $type && $value->isa('HASH') );
    return $type  if $type;
    return $value if !defined $value;
    return 'TIME' if $value =~ $TIME;
    return $value =~ s/$UUID/UUID/grmsx =~ s/blocking|promise/WAY/grmsx;
}

sub plain ($value) {
    my $type = ref $value;
    return $value                          if !$type;
    return [ map { plain($_) } @{$value} ] if $type eq 'ARRAY';
    return { map { $_ => plain( $value->{$_} ) } keys %{$value} }
      if $type eq 'HASH' || $value->isa('HASH');
    return "$type";
}

sub audits ( $action, $target ) {
    return
      scalar $dbh->selectrow_array(
        'SELECT count(*) FROM audit_log WHERE action = ? AND target_id = ?',
        undef, $action, $target );
}

sub commands ($key) {
    return
      scalar $dbh->selectrow_array(
        'SELECT status FROM command_log WHERE idempotency_key = ?',
        undef, $key );
}

sub revision {
    return fresh_configuration()->load->{revision};
}

# A configuration service with no state loaded yet, as a request has.
sub fresh_configuration {
    return GPForum::Service::Admin::Configuration->new(
        schema      => $c->gp_schema,
        base_config => $c->gp_base_config,
    );
}

# The publication of feed items: the thread commits with the decision.
sub feed_publication ( $feeds, @items ) {

    # A published item's thread is written in the decision's transaction.
    for my $way (qw(blocking promise)) {
        my $item   = shift @items;
        my $answer = run_way( $way, $feeds, 'decide_with_posting',
            published($item), $c->gp_posting_workflow, $c->gp_forum_viewer );
        is( $answer->{status},        'ok', "publishing ($way)" );
        is( published_threads($item), 1, "publishing ($way) wrote its thread" );
        is( audits( 'integration.feed.published', $item ),
            1, "publishing ($way) audited once" );
    }

    # The decision refused once the thread is written: the thread goes with
    # it, as the blocking path's one transaction takes it back.
    my $refused = shift @items;
    my $title   = $dbh->selectrow_array(
        'SELECT title FROM integration_feed_items WHERE item_id = ?',
        undef, $refused );
    my $error;
    with_replaced_subs(
        'GPForum::Service::Integration::Syndication',
        {
            _decide_call => sub ( $input, $thread ) {
                return (
                    'integration_feed_decide',
                    {
                        actor  => $input->{actor_user_id},
                        item   => $input->{item_id},
                        status => 'withdrawn',
                        thread => $thread
                    }
                );
            },
        },
        sub {
            try {
                await_promise( $feeds, 'decide_with_posting',
                    published($refused), $c->gp_posting_workflow,
                    $c->gp_forum_viewer );
            }
            catch ($caught) { $error = $caught; };
            return;
        }
    );
    like(
        "$error",
        qr/lost [ ] its [ ] review [ ] authority/msx,
        'a decision refused after publishing fails'
    );
    is(
        scalar $dbh->selectrow_array(
            'SELECT count(*) FROM threads WHERE title = ?',
            undef, $title
        ),
        0,
        'and leaves no thread behind'
    );
    is(
        scalar $dbh->selectrow_array(
            'SELECT status FROM integration_feed_items WHERE item_id = ?',
            undef, $refused
        ),
        'pending',
        'and the item still pending'
    );
    return;
}

sub published ($item) {
    return {
        actor_user_id => $owner,
        item_id       => $item,
        decision      => 'published',
        category_id   => seed_id( category => 1 ),
    };
}

sub published_threads ($item) {
    return scalar $dbh->selectrow_array( <<'SQL', undef, $item );
SELECT count(*) FROM threads t JOIN integration_feed_items i
  ON i.thread_id = t.thread_id WHERE i.item_id = ?
SQL
}

sub feed_items ($count) {
    my $source = sha256_hex($SOURCE);
    $dbh->do(
        'INSERT INTO integration_feed_sources (source_hash, source_url)'
          . ' VALUES (?, ?)',
        undef, $source, $SOURCE
    );
    my @items;
    for my $n ( 1 .. $count ) {
        my $item = $ids->uuid;
        $dbh->do(
            'INSERT INTO integration_feed_items'
              . ' (item_id, source_hash, identity_hash, url_hash, title, url)'
              . ' VALUES (?, ?, ?, ?, ?, ?)',
            undef,
            $item,
            $source,
            sha256_hex("identity $n"),
            sha256_hex("url $n"),
            "Item $n",
            "https://feeds.example.org/$n"
        );
        push @items, $item;
    }
    return @items;
}

1;
