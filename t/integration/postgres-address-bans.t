# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Mojo::JSON qw(encode_json);
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::AdminBootstrap;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Admin::AddressBans;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';

const my $HTTP_OK           => 200;
const my $HTTP_CREATED      => 201;
const my $HTTP_FOUND        => 302;
const my $HTTP_INVALID      => 400;
const my $HTTP_UNAUTHORIZED => 401;
const my $HTTP_FORBIDDEN    => 403;
const my $HTTP_MISSING      => 404;
const my $HTTP_CONFLICT     => 409;
const my $TOO_LONG          => 501;
const my $WORD              => 'wombatban';
const my $JSON              => { Accept => 'application/json' };
const my $NOW               => '2026-10-22T10:00:00Z';
const my $HERE              => '127.0.0.1';
const my $WEEK              => 604_800;
const my $HOUR              => 3_600;
const my $SLACK             => 120;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the address bans';
}

# ADR 0146 on a migrated, seeded PostgreSQL: staff holding admin_console
# place, edit and lift bans on an address or a range, every change audited
# without its reason; each write request from a covered address is refused
# where the ban's scope reaches, plainly; nothing of a ban reaches a page,
# the search, the export or the outbox, and an erased staff member's name
# leaves their bans.
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $schema    = $database->schema;
my $dbh       = $database->dbh;
my $ids       = GPForum::Infrastructure::Id->new;
my $functions = GPForum::Infrastructure::SqlFunction->new( schema => $schema );
my $bans      = GPForum::Service::Admin::AddressBans->new(
    schema    => $schema,
    functions => $functions
);
my $admin     = _user( 'bans_admin',     1 );
my $deputy    = _user( 'bans_deputy',    1 );
my $member    = _user( 'bans_member',    0 );
my $suspended = _user( 'bans_suspended', 1 );
$dbh->do(
    q{INSERT INTO suspensions (suspension_id, user_id, actor_user_id, reason)}
      . q{ VALUES (gen_random_uuid(), ?, ?, 'bans test')},
    undef, $suspended, $admin
);

my $first;
subtest 'the store places, replays and refuses' => sub {
    my $command = $ids->uuid;
    my $placed  = _place(
        {
            range      => ' 203.0.113.77/24 ',
            scope      => 'registration',
            reason     => "Spam\n  wave $WORD",
            command_id => $command,
        }
    );
    is_deeply(
        $placed,
        { status => 'ok', ban_id => $command },
        'a ban is placed under the form\'s command id'
    );
    $first = $command;
    my $ban = _ban($first);
    is( $ban->{address_range}, '203.0.113.0/24',  'the host bits cleared' );
    is( $ban->{reason},        "Spam wave $WORD", 'the reason made one line' );
    is( $ban->{created_by_user_id}, $admin,       'who placed it is kept' );
    ok( $ban->{week}, 'it lasts the length chosen' );

    is( _place( { command_id => $command } )->{status},
        'replayed', 'the same submission again places nothing' );
    is(
        _place( { command_id => $command, actor_user_id => $deputy } )
          ->{status},
        'conflict',
        'an id another ban holds is a conflict'
    );
    is_deeply(
        _place( { range => '203.0.113.0/24' } ),
        { status => 'duplicate', ban_id => $first },
        'a live ban on the same range answers with its id'
    );
    is_deeply(
        _place( { range => '10.0.0.0/15' } ),
        { status => 'too_broad', field => 'range' },
        'an IPv4 range wider than /16 is refused'
    );
    is( _place( { range => '2001:db8::/31' } )->{status},
        'too_broad', 'and an IPv6 range wider than /32' );
    is( _raw_place('10.0.0.0/8')->{status},
        'too_broad', 'the function refuses it as well' );

    for my $case (
        [ range    => '300.1.2.3' ],
        [ range    => 'host.example' ],
        [ scope    => 'everything' ],
        [ reason   => q{ } ],
        [ reason   => 'x' x $TOO_LONG ],
        [ duration => '2d' ],
      )
    {
        my ( $field, $value ) = @{$case};
        is_deeply(
            _place( { $field => $value } ),
            { status => 'invalid', field => $field },
            "$field is refused"
        );
    }
    is(
        _place(
            {
                range         => '198.51.100.0/24',
                scope         => 'writes',
                actor_address => '198.51.100.9',
            }
        )->{status},
        'covers_self',
        'a writes ban covering the staff member\'s own address is refused'
    );
    is(
        _place(
            {
                range         => '198.51.100.0/24',
                scope         => 'registration',
                actor_address => '::ffff:198.51.100.9',
            }
        )->{status},
        'ok',
        'a registration ban covering it is not'
    );
    is( _audits('address_ban.placed'), 2, 'each placing is audited once' );
    unlike( _audit_text('address_ban.placed'),
        qr/$WORD/msx, 'and the audit does not hold the reason' );
};

subtest 'the lookup finds the strongest live ban' => sub {
    is( $bans->covering('203.0.113.200')->{scope},
        'registration', 'an address in the range is covered' );
    is( $bans->covering('::ffff:203.0.113.200')->{ban_id},
        $first, 'written IPv4-mapped as well' );
    ok( !$bans->covering('203.0.114.1'),  'one outside is not' );
    ok( !$bans->covering('connection:4'), 'nor a connection key' );
    ok( !$bans->covering('2001:db8::1'),  'nor an IPv6 address' );
    my $narrow = _place( { range => '203.0.113.200', scope => 'writes' } );
    is( $narrow->{status}, 'ok', 'a single address inside the range' );
    is( $bans->covering('203.0.113.200')->{ban_id},
        $narrow->{ban_id}, 'the writes ban wins over registration' );
    is( $bans->covering('203.0.113.201')->{ban_id},
        $first, 'the range still covers its neighbour' );
    my $six = _place( { range => '2001:DB8:aa::/48', scope => 'sign_in' } );
    is( _ban( $six->{ban_id} )->{address_range},
        '2001:db8:aa::/48', 'IPv6 is stored compressed' );
    is( $bans->covering('2001:db8:aa::1:2')->{scope},
        'sign_in', 'and covers its addresses' );

    _expire( $narrow->{ban_id} );
    is( $bans->covering('203.0.113.200')->{ban_id},
        $first, 'an expired ban covers nothing' );
    my $plan = join "\n",
      @{
        $dbh->selectcol_arrayref(
                q{EXPLAIN SELECT * FROM address_bans b WHERE b.lifted_at}
              . q{ IS NULL AND b.address_range >>= '203.0.113.9'::inet}
        )
      };
    like(
        $plan,
        qr/idx_address_bans_live_range/msx,
        'the lookup can use the GiST index on live ranges'
    ) or diag $plan;
};

subtest 'the store edits and lifts' => sub {
    my $expires = _ban($first)->{expires_at};
    is(
        $bans->edit(
            {
                ban_id        => $first,
                scope         => 'sign_in',
                reason        => "Spam wave $WORD again",
                duration      => q{},
                actor_user_id => $deputy,
            }
        )->{status},
        'ok',
        'a ban is edited'
    );
    my $ban = _ban($first);
    is( $ban->{scope},              'sign_in', 'its scope changes' );
    is( $ban->{expires_at},         $expires,  'no length keeps its expiry' );
    is( $ban->{updated_by_user_id}, $deputy,   'who edited it is kept' );
    is( _edit( $first, 'sign_in', "Spam wave $WORD again" )->{status},
        'unchanged', 'the same values again change nothing' );
    is( _edit( $first, 'writes', 'x', '1h' )->{status},
        'ok', 'a length counts from now' );
    ok( _ban($first)->{hour}, 'an hour' );
    is( _edit( $first, 'writes', 'x', '2d' )->{field},
        'duration', 'an unknown length is refused' );
    is( _edit( $ids->uuid, 'writes', 'x' )->{status},
        'not_found', 'an unknown ban is not found' );
    is(
        $bans->edit(
            {
                ban_id        => $first,
                scope         => 'writes',
                reason        => 'mine',
                actor_user_id => $admin,
                actor_address => '203.0.113.1',
            }
        )->{status},
        'covers_self',
        'an edit that would cover the staff member is refused'
    );

    is(
        $bans->lift( { ban_id => $first, actor_user_id => $deputy } )->{status},
        'ok',
        'a ban is lifted'
    );
    is( _ban($first)->{lifted_by_user_id}, $deputy, 'by whom is kept' );
    ok( !$bans->covering('203.0.113.9'), 'a lifted ban covers nothing' );
    is(
        $bans->lift( { ban_id => $first, actor_user_id => $deputy } )->{status},
        'ended',
        'and is not lifted twice'
    );
    is( _edit( $first, 'writes', 'again' )->{status}, 'ended', 'nor edited' );
    is( _audits('address_ban.edited'), 2, 'each edit is audited' );
    is( _audits('address_ban.lifted'), 1, 'and the lifting' );

    my $listed = $bans->list;
    is( $listed->[0]{state}, 'active', 'the list starts with a live ban' );
    is( ( grep { $_->{ban_id} eq $first } @{$listed} )[0]{state},
        'lifted', 'and shows the lifted one' );
    is( ( grep { $_->{ban_id} eq $first } @{$listed} )[0]{lifted_by_username},
        'bans_deputy', 'with who lifted it' );

    $dbh->do(
        q{UPDATE address_bans SET created_at = now() - interval '200 days',}
          . q{ expires_at = now() - interval '100 days',}
          . q{ lifted_at = now() - interval '120 days' WHERE ban_id = ?},
        undef, $first
    );
    _place( { range => '192.0.2.0/24' } );
    ok( !_ban($first), 'a ban that ended 90 days ago goes at the next one' );
};

subtest 'a covered address is refused where the scope reaches' => sub {
    my $here = _place(
        { range => $HERE, scope => 'registration', reason => "Here $WORD" } );
    is( $here->{status}, 'ok', 'a ban on the test client\'s address' );
    my $visitor = Test::Mojo->new('GPForum');
    _refused( $visitor, '/register', 'registration' );
    _admitted( $visitor, '/login', 'registration ban, sign-in' );
    $visitor->get_ok('/register')->status_is( $HTTP_OK, 'reads are open' );
    $visitor->post_ok( '/register' => form => {} )
      ->status_is($HTTP_FORBIDDEN)
      ->content_unlike( qr/$WORD/msx, 'the page says no reason' );
    $visitor->content_unlike( qr/127[.]0[.]0[.]1/msx, 'and no range' );

    _edit( $here->{ban_id}, 'sign_in', "Here $WORD" );
    _refused( $visitor, '/login',          'sign-in' );
    _refused( $visitor, '/password/reset', 'sign-in, a password reset' );
    _admitted( $visitor, '/logout', 'sign-in ban, signing out' );

    _edit( $here->{ban_id}, 'writes', "Here $WORD" );
    my $signed = _session($member);
    _refused( $signed, '/threads',          'writes' );
    _refused( $signed, '/settings/profile', 'writes, the profile' );
    _admitted( $signed, '/locale',         'writes ban, the language' );
    _admitted( $signed, '/privacy/export', 'writes ban, the export' );
    $signed->get_ok('/categories')->status_is( $HTTP_OK, 'reads stay open' );

    my $staff = _session($admin);
    $staff->post_ok( '/admin/address-bans' => $JSON => form =>
          { csrf_token => _csrf($staff), range => '192.0.2.1' } )
      ->status_is( $HTTP_INVALID, 'the console\'s own forms stay open' );
    $staff->post_ok(
        "/admin/address-bans/$here->{ban_id}/lift" => $JSON => form =>
          { csrf_token => _csrf($staff) } )
      ->status_is($HTTP_OK)
      ->json_is( '/status' => 'lifted' );
    _admitted( $signed, '/threads', 'lifted, writes go on' );
};

subtest 'the console lists, checks, places, edits and lifts' => sub {
    my $staff = _session($admin);
    $staff->get_ok('/admin/address-bans')
      ->status_is($HTTP_OK)
      ->content_like( qr{2001:db8:aa::/48}msx, 'the bans are listed' );
    $staff->content_like(
        qr/You[ ]are[ ]writing[ ]from[ ]127[.]0[.]0[.]1/msx,
        'with the address the staff member writes from'
    );
    $staff->get_ok( '/admin/address-bans?check=2001:db8:aa::5' => $JSON )
      ->status_is($HTTP_OK)
      ->json_is( '/check/ban/scope' => 'sign_in' );
    $staff->json_is( '/check/ban/address_range' => '2001:db8:aa::/48' )
      ->json_is( '/client_address' => $HERE );
    $staff->get_ok('/admin/address-bans?check=nonsense')
      ->status_is($HTTP_OK)
      ->content_like(qr/not[ ]an[ ]IPv4[ ]or[ ]IPv6[ ]address/msx);
    $staff->get_ok('/admin/address-bans?check=198.18.0.1')
      ->content_like(qr/No[ ]live[ ]ban[ ]covers[ ]198[.]18[.]0[.]1/msx);

    $staff->post_ok( '/admin/address-bans' => form =>
          { range => '198.18.0.0/24', scope => 'writes', reason => 'x' } )
      ->status_is( $HTTP_FORBIDDEN, 'no CSRF token, no ban' );
    my $csrf    = _csrf($staff);
    my $command = $ids->uuid;
    my %form    = (
        csrf_token => $csrf,
        command_id => $command,
        range      => '198.18.0.0/24',
        scope      => 'writes',
        duration   => '30d',
        reason     => "Console $WORD",
    );
    $staff->post_ok( '/admin/address-bans' => form => \%form )
      ->status_is($HTTP_FOUND)
      ->header_is( Location => '/admin/address-bans' );
    is( _ban($command)->{scope}, 'writes', 'the form places a ban' );
    $staff->get_ok('/admin/address-bans')
      ->content_like( qr/The[ ]ban[ ]is[ ]in[ ]place/msx, 'and says so' );
    $staff->post_ok( '/admin/address-bans' => $JSON => form => \%form )
      ->status_is($HTTP_OK)
      ->json_is( '/status' => 'replayed' );
    $staff->post_ok( '/admin/address-bans' => $JSON => form =>
          { %form, command_id => $ids->uuid } )
      ->status_is($HTTP_CONFLICT)
      ->json_is( '/status' => 'duplicate' );
    $staff->json_is( '/ban_id' => $command );
    $staff->post_ok( '/admin/address-bans' => $JSON => form =>
          { %form, command_id => $ids->uuid, range => '127.0.0.0/16' } )
      ->status_is($HTTP_CONFLICT)
      ->json_is( '/status' => 'covers_self' );
    $staff->post_ok( '/admin/address-bans' => $JSON => form =>
          { %form, command_id => $ids->uuid, range => '10.0.0.0/12' } )
      ->status_is($HTTP_INVALID)
      ->json_is( '/status' => 'too_broad' );
    $staff->post_ok( '/admin/address-bans' => form =>
          { %form, command_id => $ids->uuid, range => '10.0.0.0/12' } )
      ->status_is($HTTP_FOUND);
    $staff->get_ok('/admin/address-bans')
      ->content_like( qr/That[ ]range[ ]is[ ]too[ ]wide/msx,
        'a refusal says why' );
    $staff->post_ok( '/admin/address-bans' => $JSON => form =>
          { %form, command_id => $ids->uuid, range => '198.19.0.0/24' } )
      ->status_is($HTTP_CREATED)
      ->json_is( '/status' => 'placed' );

    $staff->post_ok(
        "/admin/address-bans/$command" => $JSON => form => {
            csrf_token => $csrf,
            scope      => 'registration',
            reason     => "Console $WORD edited",
            duration   => q{},
        }
    )->status_is($HTTP_OK)->json_is( '/status' => 'edited' );
    is( _ban($command)->{scope}, 'registration', 'the form edits it' );
    $staff->post_ok( '/admin/address-bans/not-a-uuid' => $JSON => form =>
          { csrf_token => $csrf, scope => 'writes', reason => 'x' } )
      ->status_is($HTTP_MISSING);
    $staff->post_ok(
        "/admin/address-bans/$command/lift" => form => { csrf_token => $csrf } )
      ->status_is($HTTP_FOUND);
    ok( _ban($command)->{lifted_at}, 'the form lifts it' );
    $staff->post_ok( "/admin/address-bans/$command/lift" => $JSON => form =>
          { csrf_token => $csrf } )
      ->status_is($HTTP_CONFLICT)
      ->json_is( '/status' => 'ended' );
};

subtest 'only active staff with the admin console' => sub {
    Test::Mojo->new('GPForum')
      ->get_ok( '/admin/address-bans' => $JSON )
      ->status_is( $HTTP_UNAUTHORIZED, 'nobody signed in reads nothing' );
    my $other = _session($member);
    $other->get_ok( '/admin/address-bans' => $JSON )
      ->status_is( $HTTP_FORBIDDEN, 'a member reads no bans' )
      ->content_unlike(qr/$WORD/msx);
    $other->post_ok(
        '/admin/address-bans' => $JSON => form => {
            csrf_token => _csrf($other),
            range      => '198.18.1.0/24',
            scope      => 'writes',
            duration   => '1d',
            reason     => 'member',
        }
    )->status_is( $HTTP_FORBIDDEN, 'and places none' );
    my $away = _session($suspended);
    $away->post_ok(
        '/admin/address-bans' => $JSON => form => {
            csrf_token => _csrf($away),
            range      => '198.18.2.0/24',
            scope      => 'writes',
            duration   => '1d',
            reason     => 'suspended',
        }
    )->status_is( $HTTP_FORBIDDEN, 'a suspended staff member places none' );
    is(
        scalar $dbh->selectrow_array(
                q{SELECT count(*) FROM address_bans}
              . q{ WHERE address_range <<= '198.18.0.0/16'}
              . q{ AND address_range <> '198.18.0.0/24'}
        ),
        0,
        'neither placed a ban'
    );
};

subtest 'nothing of a ban leaks, and erasure takes the staff name' => sub {
    my $public = Test::Mojo->new('GPForum');
    $public->get_ok('/feed.atom')
      ->content_unlike( qr/$WORD/msx, 'the public feed holds none' );
    for my $table (qw(audit_log outbox_messages event_log search_documents)) {
        is( _containing($table), 0, "no $table row holds a reason" );
    }
    my $document =
      $functions->row( 'portability_export_parts', { user_id => $admin } )
      ->{document};
    unlike( encode_json($document), qr/$WORD/msx,
        'the export leaves the bans out' );

    my $revoked =
      $functions->row( 'privacy_revoke_user',
        { source => 'AddressBan', user_id => $admin, at => $NOW } );
    ok( $revoked->{revoked} >= 1, 'the erased staff member\'s bans' );
    is(
        scalar $dbh->selectrow_array(
            q{SELECT count(*) FROM address_bans WHERE ? IN}
              . q{ (created_by_user_id, updated_by_user_id, lifted_by_user_id)},
            undef,
            $admin
        ),
        0,
        'name them no more'
    );
    ok( scalar $dbh->selectrow_array(q{SELECT count(*) FROM address_bans}),
        'and the bans stay' );
};

done_testing();

# Places a ban through the store: a week of registration ban on a test
# range by the administrator, unless the input says otherwise.
sub _place ($input) {
    return $bans->place(
        {
            range         => '203.0.113.0/24',
            scope         => 'registration',
            duration      => '7d',
            reason        => 'test',
            actor_user_id => $admin,
            %{$input},
        }
    );
}

sub _edit ( $ban_id, $scope, $reason, $duration = q{} ) {
    return $bans->edit(
        {
            ban_id        => $ban_id,
            scope         => $scope,
            reason        => $reason,
            duration      => $duration,
            actor_user_id => $admin,
        }
    );
}

sub _raw_place ($range) {
    return $functions->row(
        'admin_address_ban_place',
        {
            ban_id        => $ids->uuid,
            range         => $range,
            scope         => 'writes',
            reason        => 'raw',
            expires_at    => '2026-10-23T10:00:00Z',
            actor_user_id => $admin,
            actor_address => undef,
            now           => $NOW,
            audit         => {},
        }
    );
}

# A ban's row, with whether it lasts about a week or an hour from now.
sub _ban ($ban_id) {
    my $ban = $dbh->selectrow_hashref(
        q{SELECT b.*, b.address_range::text AS address_range,}
          . q{ extract(epoch FROM b.expires_at - now()) AS remaining}
          . q{ FROM address_bans b WHERE b.ban_id = ?},
        undef, $ban_id
    );
    if ($ban) {
        $ban->{week} = abs( $ban->{remaining} - $WEEK ) < $SLACK;
        $ban->{hour} = abs( $ban->{remaining} - $HOUR ) < $SLACK;
    }

    return $ban;
}

sub _expire ($ban_id) {
    $dbh->do(
        q{UPDATE address_bans SET created_at = now() - interval '2 days',}
          . q{ expires_at = now() - interval '1 day' WHERE ban_id = ?},
        undef, $ban_id
    );

    return;
}

sub _audits ($action) {
    return
      scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM audit_log WHERE action = ?},
        undef, $action );
}

sub _audit_text ($action) {
    my $rows = $dbh->selectcol_arrayref(
        q{SELECT row_to_json(a)::text FROM audit_log a WHERE action = ?},
        undef, $action );

    return join "\n", @{$rows};
}

sub _containing ($table) {
    return
      scalar $dbh->selectrow_array(
        qq{SELECT count(*) FROM $table t WHERE row_to_json(t)::text LIKE ?},
        undef, "%$WORD%" );
}

# A write the ban refuses: 403, said as address_banned.
sub _refused ( $test, $path, $label ) {
    $test->post_ok( $path => $JSON => form => {} )
      ->status_is( $HTTP_FORBIDDEN, "$label: refused" )
      ->json_is( '/status' => 'address_banned', "$label: as a ban" );

    return;
}

# A write the ban lets through to its own answer, whatever that is.
sub _admitted ( $test, $path, $label ) {
    $test->post_ok( $path => $JSON => form => {} );
    isnt( $test->tx->res->json('/status') // q{},
        'address_banned', "$label: not refused" );

    return;
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
    $routes->get('/__test/bans-session')->to(
        cb => sub ($c) {
            $c->session( user_id => $user_id );
            return $c->render( json => { ok => 1 } );
        }
    );
    $test->get_ok('/__test/bans-session')->status_is($HTTP_OK);

    return $test;
}

# A new active member, given the bootstrap administration role when asked.
sub _user ( $name, $administrator ) {
    my ($id) = $dbh->selectrow_array(
        q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{ password_hash, status, email_verified_at) VALUES}
          . q{ (gen_random_uuid(), ?, ?, ?, 'x', 'active', now()) RETURNING id},
        undef, $name, $name, "$name\@example.test"
    );
    if ($administrator) {
        GPForum::Test::PostgresHarness::quietly(
            sub {
                return GPForum::Command::AdminBootstrap->new->run( 'grant',
                    '--user-id', $id );
            }
        );
    }

    return $id;
}

1;
