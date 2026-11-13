# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use List::Util qw(uniq);
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
const my %NAME => (
    $ALICE => 'alice',
    $BOB   => 'bob',
    $SID   => 'sid',
    $NEXT  => 'next',
);

# The session rows the cases leave, one line each (_lines).
const my $CREATED_TAIL =>
  ' alice hash:token-1 05-23T12:00:00 05-23T12:00:00 06-22T12:00:00 -';
const my $CREATED => "sid$CREATED_TAIL";
const my $CREATED_TOKEN_2 =>
  'sid alice hash:token-2 05-23T12:00:00 05-23T12:00:00 06-22T12:00:00 -';
const my $BOBS_OTHER =>
  'sid bob other 05-23T10:00:00 05-23T11:59:00 05-24T12:00:00 -';
const my $BOBS_NEXT =>
  'next bob hash:token-1 05-23T10:00:00 05-23T11:59:00 05-24T12:00:00 -';
const my $SEEDED_TIMES => '05-23T10:00:00 05-23T11:59:00 05-24T12:00:00';
const my $SEEDED       => "sid alice hash:token-1 $SEEDED_TIMES -";
const my $TOUCHED =>
  'sid alice hash:token-1 05-23T10:00:00 05-23T12:00:00 05-24T12:00:00 -';
const my $EXPIRED => 'sid alice hash:token-1 05-23T10:00:00 05-23T11:59:00'
  . ' 05-23T12:00:00 05-23T12:00:00';
const my $REVOKED_BEFORE =>
  "sid alice hash:token-1 $SEEDED_TIMES 05-23T10:00:00";
const my $REVOKED_NOW => "sid alice hash:token-1 $SEEDED_TIMES 05-23T12:00:00";
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

# The session store is written once (ADR 0177): each session case states
# the answer and every session row it leaves, and a read compares xmin to
# catch an extra write. The permission gate and the rate limiter still
# compare the PostgreSQL function with their retained Perl path.
_session_cases();
_session_failures();
_policy();
_rate();
_calls();

done_testing();

sub _session_cases {
    for my $case (
        [
            normal => sub { },
            { session => $CREATED, session_token => 'token-1' }, [$CREATED]
        ],
        [
            id_retry =>
              sub { _session( { user_id => $BOB, session_hash => 'other' } ); },
            { session => "next$CREATED_TAIL", session_token => 'token-1' },
            [ $BOBS_OTHER, "next$CREATED_TAIL" ]
        ],
        [
            token_retry => sub {
                _session( { session_id => $NEXT, user_id => $BOB } );
            },
            {
                session       => $CREATED_TOKEN_2,
                session_token => 'token-2'
            },
            [ $CREATED_TOKEN_2, $BOBS_NEXT ]
        ],
        [
            reused => sub { _session( {} ); },
            { session => $SEEDED, session_token => 'token-1', skipped => 1 },
            [$SEEDED]
        ],
      )
    {
        my ( $name, $seed, $answer, $stored ) = @{$case};
        _stated(
            "session create $name",
            $seed,
            sub {
                return _sessions()->create_session(
                    { id => $ALICE },
                    {
                        request_address => '198.51.100.7',
                        user_agent      => 'probe'
                    }
                );
            },
            { answer => $answer, stored => $stored }
        );
    }

    _validation_cases();
    _revocation_cases();

    return;
}

# What a validation answers, whether it wrote the row, and the row after.
sub _validation_cases {
    my $not_found = { ok => 0, error => 'not_found' };
    my $invalid   = { ok => 0, error => 'invalid_token' };
    for my $case (
        [ fresh => {}, {}, { ok => 1, session => $SEEDED }, 0, $SEEDED ],
        [
            touched => { last_seen_at => $BEFORE },
            {}, { ok => 1, session => $TOUCHED }, 1, $TOUCHED
        ],
        [
            touch_boundary => { last_seen_at => '2026-05-23T11:55:00.9Z' },
            {}, { ok => 1, session => $TOUCHED }, 1, $TOUCHED
        ],
        [
            expired => { expires_at => $NOW },
            {}, { ok => 0, error => 'expired', session => $EXPIRED }, 1,
            $EXPIRED
        ],
        [
            expiry_fraction => { expires_at => '2026-05-23T12:00:00.9Z' },
            {}, { ok => 0, error => 'expired', session => $EXPIRED }, 1,
            $EXPIRED
        ],
        [
            revoked => { revoked_at => $BEFORE },
            {}, { ok => 0, error => 'revoked' }, 0, $REVOKED_BEFORE
        ],
        [
            bad_token => {},
            { session_token => 'wrong-token' }, $invalid, 0, $SEEDED
        ],
        [ empty_token => {}, { session_token => q{} }, $invalid, 0, $SEEDED ],
        [
            token_before_revocation => { revoked_at => $BEFORE },
            { session_token => 'wrong-token' }, $invalid, 0, $REVOKED_BEFORE
        ],
        [ wrong_member => {}, { user_id    => $BOB },  $not_found, 0, $SEEDED ],
        [ absent       => {}, { session_id => $NEXT }, $not_found, 0, $SEEDED ],
        [
            malformed => {},
            { session_id => 'not-a-uuid' }, $not_found, 0, $SEEDED
        ],
      )
    {
        my ( $name, $row, $input, $answer, $wrote, $stored ) = @{$case};
        _stated(
            "session validate $name",
            sub { _session($row); },
            sub {
                my $before = _version();
                my $result = _sessions()->validate_session(
                    {
                        session_id    => $SID,
                        user_id       => $ALICE,
                        session_token => 'token-1',
                        $input->%*
                    }
                );
                return {
                    answer => $result,
                    wrote  => $before ne _version() ? 1 : 0
                };
            },
            {
                answer => { answer => $answer, wrote => $wrote },
                stored => [$stored]
            }
        );
    }
    return;
}

# A revocation is stamped at the clock, or at the session's creation when
# that is later; a second one keeps the first's time.
sub _revocation_cases {
    my $not_found = { ok => 0, error => 'not_found' };
    my $future    = 'sid alice hash:token-1 05-23T12:00:01 05-23T11:59:00'
      . ' 05-24T12:00:00';
    for my $case (
        [
            single => {},
            {}, { ok => 1, session => $SEEDED }, $REVOKED_NOW
        ],
        [
            scoped => {},
            { user_id => $ALICE }, { ok => 1, session => $SEEDED },
            $REVOKED_NOW
        ],
        [ wrong_member => {}, { user_id => $BOB }, $not_found, $SEEDED ],
        [
            revoked => { revoked_at => $BEFORE },
            {}, { ok => 1, session => $REVOKED_BEFORE, skipped => 1 },
            $REVOKED_BEFORE
        ],
        [
            future_created => { created_at => '2026-05-23T12:00:01Z' },
            {}, { ok => 1, session => "$future -" }, "$future 05-23T12:00:01"
        ],
        [ absent => {}, { session_id => $NEXT }, $not_found, $SEEDED ],
      )
    {
        my ( $name, $row, $input, $answer, $stored ) = @{$case};
        _stated(
            "session revoke $name",
            sub { _session($row); },
            sub {
                return _sessions()
                  ->revoke_session( { session_id => $SID, $input->%* } );
            },
            { answer => $answer, stored => [$stored] }
        );
    }

    my $next_session = 'next alice hash:token-2 05-23T12:00:01 05-23T11:59:00'
      . ' 05-24T12:00:00 05-23T12:00:01';
    for my $keep (
        [ undef,        2, $REVOKED_NOW ],
        [ $SID,         1, $SEEDED ],
        [ 'not-a-uuid', 2, $REVOKED_NOW ]
      )
    {
        _stated(
            'revoke user, keep ' . ( $keep->[0] // 'none' ),
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
            sub {
                return _sessions()
                  ->revoke_user_sessions( $ALICE, $NOW, $keep->[0] );
            },
            { answer => $keep->[1], stored => [ $keep->[2], $next_session ] }
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
                    _sessions()->create_session( { id => $ALICE }, {} );
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
            _sessions()->create_session( { id => $ALICE }, {} );
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

# What each account status answers, stated: the viewer and the suspension
# store are written once (ADR 0177), with no Perl path to compare with.
# Only an active account is a member.
sub _account_policy {
    my %member = ( active => 1, pending => 0, suspended => 0, deleted => 0 );
    my %participation = (
        active    => { ok => 1 },
        pending   => { ok => 1 },
        suspended => { ok => 0, reason => 'suspended' },
        deleted   => { ok => 0, reason => 'user_deleted' },
    );
    for my $status (qw(active pending suspended deleted)) {
        $dbh->do( 'UPDATE users SET status = ? WHERE id = ?',
            undef, $status, $ALICE );
        is(
            GPForum::Service::Forum::ViewerResolver->new( schema => $schema )
              ->resolve($ALICE)
              ->member,
            $member{$status},
            "$status account's viewer"
        );
        is_deeply(
            GPForum::Service::Moderation::SuspensionStore->new(
                schema => $schema,
                clock  => $clock
            )->can_participate($ALICE),
            $participation{$status},
            "$status account's participation"
        );
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
        my $viewer =
          GPForum::Service::Forum::ViewerResolver->new( schema => $schema )
          ->resolve($ALICE);

        # A category binding grants its category, and nothing without one.
        is_deeply(
            {
                global_read  => $viewer->global_read,
                category_ids => $viewer->category_ids,
                space_ids    => $viewer->space_ids
            },
            {
                global_read  => 0,
                category_ids => [ $scope->[0] // () ],
                space_ids    => []
            },
            'viewer grant scope'
        );
        for my $requested (
            [ undef,  undef ],
            [ $SCOPE, undef ],
            [ undef,  $SPACE ],
            [ $SCOPE, $SPACE ],
            [ $BOB,   $SPACE ]
          )
        {
            my $allowed =
              GPForum::Service::Admin::PermissionGate->new( schema => $schema )
              ->allowed(
                $ALICE,
                {
                    resource_type => 'category',
                    action        => 'read',
                    resource_id   => $requested->[0],
                    space_id      => $requested->[1]
                }
              );
            is(
                $allowed,
                _grants( $scope, $requested ),
                'permission matches the entire requested scope'
            );
        }
    }
    return;
}

# A global binding -- no resource, no space -- grants every scope; any other
# grants only the scope it names, resource and space both.
sub _grants ( $binding, $requested ) {
    return 1 if !defined $binding->[0] && !defined $binding->[1];
    for my $at ( 0, 1 ) {
        my ( $bound, $asked ) = ( $binding->[$at], $requested->[$at] );
        return 0 if defined $bound != defined $asked;
        return 0 if defined $bound && $bound ne $asked;
    }
    return 1;
}

# A suspension is in force while it has no end or its end is not before the
# clock's now, compared as instants: the boundary itself still holds.
sub _suspension_policy {
    my %in_force = (
        'unlimited'            => 1,
        '2026-05-22T12:00:00Z' => 0,
        $NOW                   => 1,
        '2026-05-23T13:00:00Z' => 1,
        '9999-12-31T12:00:00Z' => 1,
    );
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
        my $store = GPForum::Service::Moderation::SuspensionStore->new(
            schema => $schema,
            clock  => $clock,
        );
        my $label  = $until // 'unlimited';
        my $active = $store->active_for_user($ALICE);
        if ( $in_force{$label} ) {
            is( $active && $active->{suspension_id},
                $SID, "suspension boundary $label is in force" );
            is_deeply(
                $store->can_participate($ALICE),
                { ok => 0, reason => 'suspended', suspension_id => $SID },
                'and refuses participation'
            );
        }
        else {
            is( $active, undef, "suspension boundary $label has ended" );
            is_deeply(
                $store->can_participate($ALICE),
                { ok => 1 },
                'and allows participation'
            );
        }
    }
    return;
}

sub _rate {
    subtest 'rate limit increments and expiry are counted atomically' => sub {
        $dbh->do('DELETE FROM rate_limit_buckets');
        my $store =
          GPForum::Service::Operations::RateLimiter::PostgreSQLStore->new(
            schema => $schema,
            clock  => $clock
          );
        my @checks = map {
            $store->check(
                {
                    scope    => 'forum',
                    action   => 'reply',
                    actor_id => $ALICE,
                    limit    => 2
                }
            )
        } 1 .. $RATE_CHECKS;
        is_deeply(
            [ map { [ @{$_}{qw(ok remaining)} ] } @checks ],
            [ [ 1, 1 ], [ 1, 0 ], [ 0, 0 ], [ 0, 0 ] ],
            'two requests pass, then each is refused'
        );
        is_deeply(
            [ map { $_->{observed_count} } @checks ],
            [ 1 .. $RATE_CHECKS ],
            'and each is counted'
        );
        is( scalar( uniq map { $_->{key} } @checks ),
            1, 'every check of the window counts in one bucket' );
        is_deeply(
            $store->snapshot,
            { buckets => 1, store => 'postgresql', status => 'ok' },
            'the snapshot counts the live bucket'
        );
        my $rows = $dbh->selectall_arrayref(
            'SELECT observed_count, blocked_count FROM rate_limit_buckets',
            { Slice => {} } );
        is_deeply(
            $rows,
            [ { observed_count => $RATE_CHECKS, blocked_count => 2 } ],
            'the row counts every request and every refused one'
        );
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
        my $store = _sessions();
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

sub _sessions {
    return GPForum::Service::Identity::SessionStore->new(
        schema     => $schema,
        clock      => $clock,
        id_service =>
          GPForum::Test::ScriptedId->new( next_ids => [ $SID, $NEXT ] ),
        session_tokens => GPForum::Test::SessionToken->new,
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

# The transaction that last wrote the session $SID.
sub _version {
    return $dbh->selectrow_array(
        'SELECT xmin::text FROM sessions WHERE session_id = ?',
        undef, $SID );
}

# A session row, or a value holding them, as one line each: its id, member,
# hash and times, the ids named and the times short.
sub _lines ($value) {
    return $value                           if !ref $value;
    return [ map { _lines($_) } @{$value} ] if ref $value eq 'ARRAY';
    return join q{ },
      map { _short( $value->{$_} ) }
      qw(session_id user_id session_hash created_at last_seen_at expires_at
      revoked_at)
      if exists $value->{session_hash};
    return { map { $_ => _lines( $value->{$_} ) } keys %{$value} };
}

sub _short ($value) {
    return q{-}          if !defined $value;
    return $NAME{$value} if exists $NAME{$value};
    $value =~ s/\A 2026- ( \d\d-\d\dT [\d:]+ ) Z \z/$1/msx;
    return $value;
}

sub _stated ( $label, $seed, $run, $expected ) {
    subtest $label => sub {
        _clear();
        $seed->();
        my $answer = _normal( $run->() );
        is_deeply(
            _lines(
                {
                    answer => $answer,
                    stored => _normal(
                        $dbh->selectall_arrayref(
                            'SELECT * FROM sessions ORDER BY session_id',
                            { Slice => {} }
                        )
                    )
                }
            ),
            $expected,
            'the answer and the stored rows'
        );
    };
    return;
}

1;
