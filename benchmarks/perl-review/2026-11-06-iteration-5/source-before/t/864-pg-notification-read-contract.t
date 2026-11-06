# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::PgNotifications;
use GPForum::Test::RealtimeBusDbh;
use GPForum::Test::RealtimeBusSchema;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';

sub _queue {
    my $schema = GPForum::Test::RealtimeBusSchema->new(
        dbh => GPForum::Test::RealtimeBusDbh->new );
    my $queue =
      GPForum::Infrastructure::PgNotifications->new( schema => $schema );
    $queue->listen_to('cache');
    $queue->listen_to('domain');
    return ( $queue, $schema );
}

for my $failure (qw(exception dbi_error)) {
    subtest "a repeated $failure read failure makes every consumer stale" =>
      sub {
        my ( $queue, $schema ) = _queue();
        my $attempts = 0;
        with_replaced_subs(
            'GPForum::Test::RealtimeBusDbh',
            {
                pg_notifies => sub {
                    $attempts += 1;
                    die "socket closed\n" if $failure eq 'exception';
                    return undef;
                },
                err => sub { return 1 },
            },
            sub {
                my $taken = $queue->take('cache');
                ok( !$taken->{available}, 'a failed retry is unavailable' );
                ok( $taken->{gap},
                    'the current consumer learns it lost coverage' );
                is( $attempts, 2,
                    'only one reconnect/read retry is attempted' );
                ok( !$queue->listening('cache'),
                    'the failed channel is stale' );
                ok(
                    !$queue->listening('domain'),
                    'other channels are also stale'
                );
            }
        );
        my $recovered = $queue->take('cache');
        ok( $recovered->{available}, 'a healthy read recovers' );
        ok( $recovered->{gap},
            'recovery on the same handle still reports the gap' );
        ok( $queue->listening('domain'), 'every channel is registered again' );
        ok(
            $queue->take('domain')->{gap},
            'the other consumer retains its gap'
        );
        ok(
            !$queue->take('cache')->{gap},
            'a healthy idle read has no new gap'
        );
      };
}

subtest 'losing the storage handle retires established listeners' => sub {
    my ( $queue, $schema ) = _queue();
    my $backend = $schema->dbh;
    $schema->dbh(undef);
    my $taken = $queue->take('cache');
    ok( !$taken->{available}, 'the absent handle is unavailable' );
    ok( $taken->{gap}, 'the cache must distrust its old values immediately' );
    ok( !$queue->listening('domain'),
        'the other listener is no longer current' );
    $schema->dbh($backend);
    ok( $queue->take('domain')->{gap}, 'coverage is restored with a gap' );
};

subtest 'a successful retry on the same handle still reports lost coverage' =>
  sub {
    my ( $queue, $schema ) = _queue();
    my $attempts = 0;
    with_replaced_subs(
        'GPForum::Test::RealtimeBusDbh',
        {
            pg_notifies => sub {
                die "socket temporarily unreadable\n" if ++$attempts == 1;
                return undef;
            },
        },
        sub {
            my $taken = $queue->take('cache');
            ok( $taken->{available}, 'the retry reads successfully' );
            ok( $taken->{gap}, 'the failed read still retires cached state' );
            ok( $queue->take('domain')->{gap},
                'the other consumer also learns of the lost coverage' );
        }
    );
  };

subtest 'healthy idle polls read without reconnecting or reissuing LISTEN' =>
  sub {
    my ( $queue, $schema ) = _queue();
    my $reads = 0;
    my $read  = GPForum::Test::RealtimeBusDbh->can('pg_notifies');
    with_replaced_subs(
        'GPForum::Test::RealtimeBusDbh',
        {
            pg_notifies => sub {
                $reads += 1;
                return $read->(@_);
            },
        },
        sub {
            with_replaced_subs(
                'GPForum::Infrastructure::Storage',
                { dbh_of => sub { die "unexpected ping/reconnect\n" } },
                sub {
                    ok( $queue->take('cache')->{available}, 'the cache polls' );
                    ok( $queue->take('domain')->{available},
                        'the other consumer polls' );
                }
            );
        }
    );
    is( $reads, 2, 'both polls still read pending notifications' );
    is( scalar @{ $schema->dbh->statements },
        2, 'only the initial LISTENs ran' );
    ok(
        $queue->listen_to('new_channel'),
        'a later registration is synchronized'
    );
    is( scalar @{ $schema->dbh->statements },
        1 + 2, 'existing channels need no new LISTEN' );
  };

done_testing();

1;
