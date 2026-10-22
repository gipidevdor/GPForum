# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::Exception;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Admin::PermissionGate;
use GPForum::Service::Forum::ViewerResolver;
use GPForum::Service::Identity::SessionStore;
use GPForum::Service::Identity::Support;
use GPForum::Service::Moderation::SuspensionStore;
use GPForum::Service::Operations::RateLimiter::PostgreSQLStore;
use GPForum::Test::FixedClock;
use GPForum::Test::PgDatabase;
use GPForum::Test::ScriptedId;
use GPForum::Test::SessionToken;

our $VERSION = '0.001';

const my $ALICE          => '018f1000-0000-7000-8000-000000000001';
const my $BOB            => '018f1000-0000-7000-8000-000000000002';
const my $SID            => '018f1000-0000-7000-8000-000000000011';
const my $NEXT           => '018f1000-0000-7000-8000-000000000012';
const my $ROLE           => '018f1000-0000-7000-8000-000000000021';
const my $PERM           => '018f1000-0000-7000-8000-000000000022';
const my $SCOPE          => '018f1000-0000-7000-8000-000000000023';
const my $SPACE          => '018f1000-0000-7000-8000-000000000024';
const my $NOW            => '2026-05-23T12:00:00Z';
const my $BEFORE         => '2026-05-23T10:00:00Z';
const my $FUTURE         => '2026-05-24T12:00:00Z';
const my $EPOCH          => 1_779_537_600;
const my $RATE_CHECKS    => 4;
const my $PROLOGUE_CALLS => 5;
const my %TIME_KEY => map { $_ => 1 } qw(
  created_at last_seen_at expires_at revoked_at valid_from valid_to
);

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to compare the request prologue';
}

my $database = GPForum::Test::PgDatabase->fresh;
my $schema   = $database->schema;
my $dbh      = $database->dbh;
my $clock = GPForum::Test::FixedClock->new( iso8601 => $NOW, epoch => $EPOCH );
my $support = GPForum::Service::Identity::Support->new;

for my $user ( [ $ALICE, 'alice' ], [ $BOB, 'bob' ] ) {
    $dbh->do(
        q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{password_hash, status) VALUES (?, ?, ?, ?, 'unused', 'active')},
        undef,
        $user->[0],
        $user->[1],
        $user->[1],
        "$user->[1]\@example.test"
    );
}

# Same database, ids, token source and clock, first the retained Perl path
# and then the PostgreSQL function. Compare both the answer and every
# session row; successful reads also compare xmin to catch an extra write.
_session_cases();
_session_failures();
_policy();
_rate();
_calls();

done_testing();

sub _session_cases {
    for my $case (
        [ normal => sub { }, {} ],
        [
            id_retry =>
              sub { _session( { user_id => $BOB, session_hash => 'other' } ); },
            {}
        ],
        [
            token_retry =>
              sub { _session( { session_id => $NEXT, user_id => $BOB } ); },
            {}
        ],
        [ reused => sub { _session( {} ); }, {} ],
      )
    {
        _differential(
            "session create $case->[0]",
            $case->[1],
            sub ($old) {
                return _sessions($old)->create_session(
                    { id => $ALICE },
                    {
                        request_address => '198.51.100.7',
                        user_agent      => 'probe'
                    }
                );
            }
        );
    }

    for my $case (
        [ fresh           => {},                                           {} ],
        [ touched         => { last_seen_at => $BEFORE },                  {} ],
        [ touch_boundary  => { last_seen_at => '2026-05-23T11:55:00.9Z' }, {} ],
        [ expired         => { expires_at => $NOW },                       {} ],
        [ expiry_fraction => { expires_at => '2026-05-23T12:00:00.9Z' },   {} ],
        [ revoked         => { revoked_at => $BEFORE },                    {} ],
        [ bad_token       => {}, { session_token => 'wrong-token' } ],
        [ empty_token     => {}, { session_token => q{} } ],
        [
            token_before_revocation => { revoked_at => $BEFORE },
            { session_token => 'wrong-token' }
        ],
        [ wrong_member => {}, { user_id    => $BOB } ],
        [ absent       => {}, { session_id => $NEXT } ],
        [ malformed    => {}, { session_id => 'not-a-uuid' } ],
      )
    {
        _differential(
            "session validate $case->[0]",
            sub { _session( $case->[1] ); },
            sub ($old) {
                my $before = $dbh->selectrow_array(
                    'SELECT xmin::text FROM sessions WHERE session_id = ?',
                    undef, $SID );
                my $result = _sessions($old)->validate_session(
                    {
                        session_id    => $SID,
                        user_id       => $ALICE,
                        session_token => 'token-1',
                        $case->[2]->%*
                    }
                );
                my $after = $dbh->selectrow_array(
                    'SELECT xmin::text FROM sessions WHERE session_id = ?',
                    undef, $SID );
                return {
                    answer => _normal($result),
                    wrote  => $before ne $after ? 1 : 0
                };
            }
        );
    }

    for my $case (
        [ single         => {}, {} ],
        [ scoped         => {}, { user_id => $ALICE } ],
        [ wrong_member   => {}, { user_id => $BOB } ],
        [ revoked        => { revoked_at => $BEFORE },                {} ],
        [ future_created => { created_at => '2026-05-23T12:00:01Z' }, {} ],
        [ absent         => {}, { session_id => $NEXT } ],
      )
    {
        _differential(
            "session revoke $case->[0]",
            sub { _session( $case->[1] ); },
            sub ($old) {
                return _sessions($old)
                  ->revoke_session( { session_id => $SID, $case->[2]->%* } );
            }
        );
    }

    for my $keep ( undef, $SID, 'not-a-uuid' ) {
        _differential(
            'revoke user, keep ' . ( $keep // 'none' ),
            sub {
                _session( {} );
                _session(
                    {
                        session_id   => $NEXT,
                        session_hash => 'hash:token-2',
                        created_at   => '2026-05-23T12:00:01Z'
                    }
                );
            },
            sub ($old) {
                return _sessions($old)
                  ->revoke_user_sessions( $ALICE, $NOW, $keep );
            }
        );
    }

    return;
}

sub _session_failures {
    subtest
      'session call joins the caller transaction and propagates retry failure'
      => sub {
        _clear();
        throws_ok {
            $schema->txn_do(
                sub {
                    _sessions(0)->create_session( { id => $ALICE }, {} );
                    die "roll back the caller\n";
                }
            );
        }
        qr/roll [ ] back [ ] the [ ] caller/msx, 'the caller fails';
        is( $dbh->selectrow_array('SELECT count(*) FROM sessions'),
            0, 'the function insert rolls back with it' );
        _session( { user_id => $BOB, session_hash => 'taken-1' } );
        _session(
            { session_id => $NEXT, user_id => $BOB, session_hash => 'taken-2' }
        );
        throws_ok {
            _sessions(0)->create_session( { id => $ALICE }, {} );
        }
        'GPForum::X::Conflict', 'a second collision raises the same conflict';
        is(
            $dbh->selectrow_array(
                'SELECT count(*) FROM sessions WHERE user_id = ?', undef,
                $ALICE
            ),
            0,
            'neither failed insert survives'
        );
      };

    return;
}

sub _policy {
    subtest 'viewer, participation and permission keep their policy' => sub {
        $dbh->do( q{INSERT INTO roles (role_id, name) VALUES (?, 'reader')},
            undef, $ROLE );
        $dbh->do(
q{INSERT INTO permissions (permission_id, name, resource_type, action) VALUES (?, 'category.read', 'category', 'read')},
            undef, $PERM
        );
        $dbh->do(
'INSERT INTO role_permissions (role_id, permission_id) VALUES (?, ?)',
            undef, $ROLE, $PERM
        );
        _account_policy();
        _grant_policy();
        _suspension_policy();
    };
    return;
}

sub _account_policy {
    for my $status (qw(active pending suspended deleted)) {
        $dbh->do( 'UPDATE users SET status = ? WHERE id = ?',
            undef, $status, $ALICE );
        my @results;
        for my $old ( 1, 0 ) {
            my $resolver = GPForum::Service::Forum::ViewerResolver->new(
                schema => $schema,
                ( $old ? ( functions => undef ) : () )
            );
            my $viewer = $resolver->resolve($ALICE);
            my $store  = GPForum::Service::Moderation::SuspensionStore->new(
                schema => $schema,
                clock  => $clock,
                ( $old ? ( functions => undef ) : () )
            );
            push @results,
              {
                member        => $viewer->member,
                participation => $store->can_participate($ALICE)
              };
        }
        is_deeply( $results[1], $results[0], "$status account" );
    }
    return;
}

sub _grant_policy {
    $dbh->do( q{UPDATE users SET status = 'active' WHERE id = ?},
        undef, $ALICE );
    for my $scope (
        [ undef,  undef ],
        [ $SCOPE, undef ],
        [ undef,  $SPACE ],
        [ $SCOPE, $SPACE ]
      )
    {
        $dbh->do('DELETE FROM role_bindings');
        $dbh->do(
'INSERT INTO role_bindings (binding_id, user_id, role_id, resource_type, resource_id, space_id) VALUES (gen_random_uuid(), ?, ?, ?, ?, ?)',
            undef, $ALICE, $ROLE, 'category', @{$scope}
        );
        my @viewers;
        for my $old ( 1, 0 ) {
            my $resolver = GPForum::Service::Forum::ViewerResolver->new(
                schema => $schema,
                ( $old ? ( functions => undef ) : () )
            );
            my $viewer = $resolver->resolve($ALICE);
            push @viewers,
              {
                global_read  => $viewer->global_read,
                category_ids => $viewer->category_ids,
                space_ids    => $viewer->space_ids
              };
        }
        is_deeply( $viewers[1], $viewers[0], 'viewer grant scope preserved' );
        for my $requested (
            [ undef,  undef ],
            [ $SCOPE, undef ],
            [ undef,  $SPACE ],
            [ $SCOPE, $SPACE ],
            [ $BOB,   $SPACE ]
          )
        {
            my @allowed;
            for my $old ( 1, 0 ) {
                my $gate = GPForum::Service::Admin::PermissionGate->new(
                    schema => $schema,
                    ( $old ? ( functions => undef ) : () )
                );
                push @allowed,
                  $gate->allowed(
                    $ALICE,
                    {
                        resource_type => 'category',
                        action        => 'read',
                        resource_id   => $requested->[0],
                        space_id      => $requested->[1]
                    }
                  );
            }
            is( $allowed[1], $allowed[0],
                'permission matches the entire requested scope' );
        }
    }
    return;
}

sub _suspension_policy {
    for my $until ( undef, '2026-05-22T12:00:00Z', $NOW,
        '2026-05-23T13:00:00Z', '9999-12-31T12:00:00Z' )
    {
        $dbh->do('DELETE FROM suspensions');
        $dbh->do(
'INSERT INTO suspensions (suspension_id, user_id, actor_user_id, reason, valid_from, valid_to) VALUES (?, ?, ?, ?, ?, ?)',
            undef,
            $SID,
            $ALICE,
            $BOB,
            'probe',
            '2020-01-01T00:00:00Z',
            $until
        );
        my @results;
        for my $old ( 1, 0 ) {
            my $store = GPForum::Service::Moderation::SuspensionStore->new(
                schema => $schema,
                clock  => $clock,
                ( $old ? ( functions => undef ) : () )
            );
            push @results,
              {
                active        => _normal( $store->active_for_user($ALICE) ),
                participation => $store->can_participate($ALICE),
              };
        }
        is_deeply( $results[1], $results[0],
            'suspension boundary ' . ( $until // 'unlimited' ) );
    }
    return;
}

sub _rate {
    subtest 'rate limit increments and expiry are differential and atomic' =>
      sub {
        my @runs;
        for my $old ( 1, 0 ) {
            $dbh->do('DELETE FROM rate_limit_buckets');
            my $store =
              GPForum::Service::Operations::RateLimiter::PostgreSQLStore->new(
                schema => $schema,
                clock  => $clock,
                ( $old ? ( functions => undef ) : () )
              );
            my @checks;
            for ( 1 .. $RATE_CHECKS ) {
                push @checks,
                  $store->check(
                    {
                        scope    => 'forum',
                        action   => 'reply',
                        actor_id => $ALICE,
                        limit    => 2
                    }
                  );
            }
            push @runs,
              {
                checks   => \@checks,
                snapshot => $store->snapshot,
                rows     => $dbh->selectall_arrayref(
                    'SELECT * FROM rate_limit_buckets',
                    { Slice => {} }
                )
              };
        }
        is_deeply( $runs[1], $runs[0],
            'allowed, blocked counters, windows, timestamps and snapshot match'
        );
        is( $runs[1]{checks}[-1]{observed_count},
            $RATE_CHECKS, 'the increment happens on every request' );
        is( $runs[1]{rows}[0]{blocked_count},
            2, 'every refused request is counted' );
      };

    return;
}

sub _calls {
    subtest 'normal request operations send function calls only' => sub {
        _clear();
        _session( {} );
        my @sql;
        $schema->storage->debug(1);
        $schema->storage->debugcb(
            sub ( $, $message ) { push @sql, $message; } );
        my $store = _sessions(0);
        $store->validate_session(
            {
                session_id    => $SID,
                user_id       => $ALICE,
                session_token => 'token-1'
            }
        );
        GPForum::Service::Forum::ViewerResolver->new( schema => $schema )
          ->resolve($ALICE);
        GPForum::Service::Moderation::SuspensionStore->new(
            schema => $schema,
            clock  => $clock
        )->can_participate($ALICE);
        GPForum::Service::Admin::PermissionGate->new( schema => $schema )
          ->allowed( $ALICE,
            { resource_type => 'category', action => 'read' } );
        GPForum::Service::Operations::RateLimiter::PostgreSQLStore->new(
            schema => $schema,
            clock  => $clock
          )
          ->check(
            { scope => 'forum', action => 'reply', actor_id => $ALICE } );
        $schema->storage->debug(0);
        is( scalar @sql, $PROLOGUE_CALLS,
            'one statement for each prologue operation' );

        for my $statement (@sql) {
            like(
                $statement,
                qr/\A SELECT [ ] [*] [ ] FROM [ ] api [.] /msx,
                'a prepared call from the catalogue'
            );
        }
    };

    return;
}

sub _sessions ($old) {
    return GPForum::Service::Identity::SessionStore->new(
        schema     => $schema,
        clock      => $clock,
        id_service =>
          GPForum::Test::ScriptedId->new( next_ids => [ $SID, $NEXT ] ),
        session_tokens => GPForum::Test::SessionToken->new,
        ( $old ? ( functions => undef ) : () )
    );
}

sub _session ($changes) {
    my %values = (
        session_id   => $SID,
        user_id      => $ALICE,
        session_hash => 'hash:token-1',
        created_at   => $BEFORE,
        last_seen_at => '2026-05-23T11:59:00Z',
        expires_at   => $FUTURE,
        revoked_at   => undef,
        $changes->%*,
    );
    $dbh->do(
'INSERT INTO sessions (session_id, user_id, session_hash, created_at, last_seen_at, expires_at, revoked_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        undef,
        @values{
            qw(session_id user_id session_hash created_at last_seen_at expires_at revoked_at)
        }
    );
    return;
}

sub _clear {
    $dbh->do('DELETE FROM sessions');
    return;
}

sub _normal ($value) {
    return $value                            if !ref $value;
    return [ map { _normal($_) } @{$value} ] if ref $value eq 'ARRAY';
    my $hash = ref $value eq 'HASH' ? $value : { $value->get_columns };
    my %copy;
    for my $key ( keys %{$hash} ) {
        my $held = $hash->{$key};
        if ( defined $held
            && exists $TIME_KEY{$key} )
        {
            my $epoch = $support->epoch_from_timestamp($held);
            if ( defined $epoch ) {
                $held = $support->iso8601_from_epoch($epoch);
            }
        }
        $copy{$key} = _normal($held);
    }
    return \%copy;
}

sub _differential ( $label, $seed, $run ) {
    subtest $label => sub {
        my @results;
        for my $old ( 1, 0 ) {
            _clear();
            $seed->();
            push @results,
              {
                answer => _normal( $run->($old) ),
                stored => _normal(
                    $dbh->selectall_arrayref(
                        'SELECT * FROM sessions ORDER BY session_id',
                        { Slice => {} }
                    )
                )
              };
        }
        is_deeply( $results[1], $results[0],
            'answer and stored rows match the retained path' );
    };
    return;
}

1;
