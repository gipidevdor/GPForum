# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Const::Fast;
use Test::More;
use Mojo::IOLoop;
use Mojo::Promise;
use lib 'lib', 't/lib';
use GPForum::Schema;
use GPForum::Infrastructure::PgNotifications;
use GPForum::Test::PgDatabase;
use GPForum::Test::Promise      qw(await_result);
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
our $VERSION = '0.001';
const my $LOCK_KEY         => 88_201_763;
const my $POLL_SECONDS     => 0.01;
const my $DEADLINE_SECONDS => 2;
const my $CHANNEL          => 'ownership_alpha';
const my $NEXT_CHANNEL     => 'ownership_beta';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'PostgreSQL required';
}
my $fixture = GPForum::Test::PgDatabase->fresh;
my $schema  = GPForum::Schema->connect(
    $fixture->dsn,
    $ENV{GPFORUM_DATABASE_USER}     // q{},
    $ENV{GPFORUM_DATABASE_PASSWORD} // q{}
);
my $peer   = $schema->storage->dbh;
my $broker = GPForum::Infrastructure::PgNotifications->new(
    schema       => $schema,
    asynchronous => 1
);
ok( await_result( $broker->ensure_p ),
    'an idle listener can connect before channels exist' );
ok(
    await_result( $broker->listen_to_p($CHANNEL) ),
    'the first channel is registered after connection'
);
$broker->take($CHANNEL);
my $listener = $broker->{async_db};
my $query    = $listener->can('query');
my $pump     = $broker->can('_pump');
my ( $idle_reads, $released, $registered, $ticks ) = ( 0, 0, 0, 0 );
my ( $error, @received );
my $finished = Mojo::Promise->new;
$peer->selectrow_array( 'SELECT pg_advisory_lock(?)', undef, $LOCK_KEY );

with_replaced_subs(
    'GPForum::Infrastructure::PgDatabase',
    {
        query => sub ( $self, $sql, @arguments ) {
            if ( $self == $listener && $sql =~ /\ALISTEN[ ]/msx ) {

                # Hold a real asynchronous command on the existing listener. Its
                # single PostgreSQL transaction releases notifications on completion.
                $sql =
                    'SELECT pg_advisory_lock('
                  . $LOCK_KEY . ');'
                  . $sql
                  . ';SELECT pg_advisory_unlock('
                  . $LOCK_KEY . ')';
            }
            return $query->( $self, $sql, @arguments );
        },
    },
    sub {
        with_replaced_subs(
            'GPForum::Infrastructure::PgNotifications',
            {
                _pump => sub ( $self, $handle ) {
                    if ( $self == $broker && $handle->{pg_async_status} ) {
                        $idle_reads++;
                    }
                    return $pump->( $self, $handle );
                },
            },
            sub {
                $broker->listen_to_p($NEXT_CHANNEL)->then(
                    sub ($value) {
                        $registered = $value;
                        return;
                    }
                )->catch(
                    sub ($caught) {
                        $error = $caught;
                        $finished->resolve(0);
                        return;
                    }
                );
                my $poll = Mojo::IOLoop->recurring(
                    $POLL_SECONDS => sub {
                        $ticks++;
                        if ( !$released ) {
                            my ($locked) = $peer->selectrow_array(
q{SELECT wait_event_type = 'Lock' FROM pg_stat_activity WHERE pid = ?},
                                undef, $listener->dbh->{pg_pid}
                            );
                            if ($locked) {
                                $broker->take($CHANNEL);
                                $peer->selectrow_array(
                                    'SELECT pg_notify(?, ?)',
                                    undef, $CHANNEL, 'during-command' );
                                $peer->selectrow_array(
                                    'SELECT pg_advisory_unlock(?)',
                                    undef, $LOCK_KEY );
                                $released = 1;
                            }
                        }
                        push @received,
                          map { $_->[2] }
                          @{ $broker->take($CHANNEL)->{notifications} };
                        if ( $registered && @received ) {
                            $finished->resolve(1);
                        }
                        return;
                    }
                );
                my $deadline = Mojo::IOLoop->timer(
                    $DEADLINE_SECONDS => sub { $finished->resolve(0); return; }
                );
                ok( await_result($finished),
'a channel change completes and delivers within the deadline'
                );
                Mojo::IOLoop->remove($poll);
                Mojo::IOLoop->remove($deadline);
                return;
            }
        );
        return;
    }
);
if ( !$released ) {
    $peer->selectrow_array( 'SELECT pg_advisory_unlock(?)', undef, $LOCK_KEY );
}
ok( $released && $ticks,
    'reactor timers advance while the real command waits on its lock' );
is( $error, undef, 'the native channel command succeeds' );
is( $idle_reads, 0,
    'idle cache reads never consume the socket while Mojo::Pg owns a command' );
ok( $broker->listening($NEXT_CHANNEL), 'the added channel is active' );
is_deeply( \@received, ['during-command'],
    'a notification received during the command is retained exactly once' );
my $previous_pid = $broker->backend_pid;
$peer->selectrow_array( 'SELECT pg_terminate_backend(?)', undef,
    $previous_pid );
ok(
    !await_result( $broker->listen_to_p('ownership_after_failure') ),
    'a command on a terminated backend reports unavailable'
);
ok( !$broker->{async_db}, 'a failed command retires the broken connection' );
ok(
    await_result( $broker->listen_to_p($CHANNEL) ),
    'the next channel request reconnects after command failure'
);
isnt( $broker->backend_pid, $previous_pid,
    'recovery uses a fresh listening backend' );
$schema->storage->disconnect;
done_testing();
1;
