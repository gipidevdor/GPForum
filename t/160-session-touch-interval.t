# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::Exception;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Config;
use GPForum::Service::Identity::SessionStore;
use GPForum::Service::Identity::Store;
use GPForum::Service::Identity::Support;
use GPForum::Test::AnsweringFunctions;
use GPForum::Test::FixedClock;

our $VERSION = '0.001';

const my $DEFAULT_INTERVAL => 300;
const my $CUSTOM_INTERVAL  => 900;
const my $NOW              => '2026-05-23T12:00:00Z';
const my $NOW_EPOCH        => 1_779_537_600;
const my $SESSION_TOKEN    => 'probe-session-token';
const my $FUTURE_EXPIRY    => '2026-06-23T12:00:00Z';

_config_contract();
_timestamp_parsing();
_interval_is_asked();
_result_codes_answered();
_interval_is_configurable();

done_testing();

sub _config_contract {
    is( GPForum::Config->new->session_touch_interval_seconds,
        $DEFAULT_INTERVAL, 'session touch interval defaults to 300 seconds' );
    is(
        GPForum::Config->from_environment(
            { GPFORUM_SESSION_TOUCH_INTERVAL_SECONDS => $CUSTOM_INTERVAL }
        )->session_touch_interval_seconds,
        $CUSTOM_INTERVAL,
        'session touch interval reads GPFORUM_SESSION_TOUCH_INTERVAL_SECONDS'
    );
    throws_ok {
        GPForum::Config->from_environment(
            { GPFORUM_SESSION_TOUCH_INTERVAL_SECONDS => '0' } );
    }
    qr/_INTERVAL_SECONDS [ ] must [ ] be [ ] at [ ] least/msx,
      'session touch interval must be positive';
    throws_ok {
        GPForum::Config->from_environment(
            { GPFORUM_SESSION_TOUCH_INTERVAL_SECONDS => 'soon' } );
    }
    qr/_INTERVAL_SECONDS [ ] must [ ] be [ ] a [ ] whole/msx,
      'session touch interval must be an integer';

    return;
}

sub _timestamp_parsing {
    my $support = GPForum::Service::Identity::Support->new;

    is( $support->epoch_from_timestamp($NOW),
        $NOW_EPOCH, 'ISO-8601 UTC timestamps parse' );
    is( $support->epoch_from_timestamp('2026-05-23 14:00:00.123+02'),
        $NOW_EPOCH, 'PostgreSQL timestamptz text with offset parses' );
    is( $support->epoch_from_timestamp('2026-05-23 06:30:00-05:30'),
        $NOW_EPOCH, 'negative offsets with minutes parse' );
    ok( !defined $support->epoch_from_timestamp('yesterday'),
        'garbage timestamps are rejected' );
    ok(
        !defined $support->epoch_from_timestamp('2026-02-30T12:00:00Z'),
        'a timestamp shaped right on a day the calendar lacks is rejected'
    );
    ok( !defined $support->epoch_from_timestamp(undef),
        'missing timestamps are rejected' );

    return;
}

# Whether a session is touched is api.session_validate's to decide
# (t/integration/postgres-sql-function-prologue.t states each case); the
# store tells it the interval and reads back its result code.
sub _interval_is_asked {
    my ( $store, $functions ) = _session_store();

    ok( _validate($store)->{ok}, 'a live session validates' );
    my ($asked) = @{ $functions->asked('session_validate') };
    is( $asked->{touch_interval_seconds},
        $DEFAULT_INTERVAL, 'the default interval is asked for' );
    is( $asked->{now}, $NOW, 'the clock is the time asked at' );
    is(
        $asked->{token_hash},
        $store->session_tokens->hash_token($SESSION_TOKEN),
        'the presented token is asked for as its digest'
    );

    return;
}

sub _result_codes_answered {
    for my $code (qw(revoked invalid_token)) {
        my ($store) = _session_store($code);
        is_deeply(
            _validate($store),
            { ok => 0, error => $code },
            "$code is refused"
        );
    }
    my ($expired) = _session_store('expired');
    my $answer = _validate($expired);
    is( $answer->{error}, 'expired', 'an expired session is refused' );
    is( $answer->{session}{session_id}, 's-1', 'with the session it revoked' );

    my ($missing) = _session_store(undef);
    is_deeply(
        _validate($missing),
        { ok => 0, error => 'not_found' },
        'a session the function does not answer is not found'
    );
    is_deeply(
        $missing->validate_session( { session_id => 's-1', user_id => q{} } ),
        { ok => 0, error => 'not_found' },
        'a session without its member is not looked up'
    );
    is( scalar @{ $missing->functions->asked('session_validate') },
        1, 'only the complete session is asked for' );

    return;
}

sub _interval_is_configurable {
    my $functions = _functions('ok');
    my $store     = GPForum::Service::Identity::Store->new(
        clock                          => GPForum::Test::FixedClock->new,
        functions                      => $functions,
        schema                         => {},
        session_touch_interval_seconds => $CUSTOM_INTERVAL,
    );

    ok( _validate($store)->{ok},
        'identity store validates through the session store' );
    is( $store->session_store->session_touch_interval_seconds,
        $CUSTOM_INTERVAL, 'identity store forwards the configured interval' );
    is( $functions->asked('session_validate')->[0]{touch_interval_seconds},
        $CUSTOM_INTERVAL, 'the configured interval is the one asked for' );

    return;
}

sub _session_store ( $code = 'ok' ) {
    my $functions = _functions($code);
    my $store     = GPForum::Service::Identity::SessionStore->new(
        clock     => GPForum::Test::FixedClock->new,
        functions => $functions,
        schema    => {},
    );

    return ( $store, $functions );
}

# api.session_validate answering the session with $code, or no row.
sub _functions ($code) {
    return GPForum::Test::AnsweringFunctions->new(
        answers => {
            session_validate => defined $code
            ? [
                {
                    expires_at   => $FUTURE_EXPIRY,
                    last_seen_at => $NOW,
                    result_code  => $code,
                    session_id   => 's-1',
                    user_id      => 'u-1',
                }
              ]
            : [],
        }
    );
}

sub _validate ($store) {
    return $store->validate_session(
        {
            session_id    => 's-1',
            session_token => $SESSION_TOKEN,
            user_id       => 'u-1',
        }
    );
}

1;
