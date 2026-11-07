# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Carp qw(croak);
use Const::Fast;
use Test::More;
use Mojo::IOLoop;
use Mojo::Promise;
use lib 'lib', 't/lib';
use GPForum::Schema;
use GPForum::Infrastructure::PgNotifications;
use GPForum::Infrastructure::AsyncQuery;
use GPForum::Test::PgDatabase;
use GPForum::Test::Promise qw(await_result);
our $VERSION = '0.001';
const my $POLL_SECONDS     => 0.01;
const my $DEADLINE_SECONDS => 2;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'PostgreSQL required';
}
my $fixture = GPForum::Test::PgDatabase->fresh;
my $schema  = GPForum::Schema->connect(
    $fixture->dsn,
    $ENV{GPFORUM_DATABASE_USER}     // q{},
    $ENV{GPFORUM_DATABASE_PASSWORD} // q{}
);
my $db      = $schema->storage->dbh;
my $queries = GPForum::Infrastructure::AsyncQuery->for_schema($schema);
is( await_result( $queries->prewarm_p ),
    2, 'two native query leases are warmed' );
$db->{Callbacks} = {
    do => sub { croak 'LISTEN must not use the synchronous workflow handle'; }
};
my $broker = GPForum::Infrastructure::PgNotifications->new(
    schema       => $schema,
    asynchronous => 1
);
await_result(
    Mojo::Promise->all(
        $broker->listen_to_p('async_alpha'),
        $broker->listen_to_p('async_beta')
    )
);
ok( $broker->listening('async_alpha') && $broker->listening('async_beta'),
    'concurrent registration shares one listener' );
my $pid = $broker->backend_pid;
isnt( $pid, $db->{pg_pid}, 'listener owns a separate backend' );

for my $query ( @{ $queries->connections } ) {
    isnt(
        $pid,
        $query->dbh->{pg_pid},
        'LISTEN never borrows an active query lease'
    );
}
$broker->take('async_alpha');
$broker->take('async_beta');
$db->selectrow_array(
    q{SELECT pg_notify('async_alpha', 'alpha'), pg_notify('async_beta', 'beta')}
);
my $deadline = Mojo::Promise->new;
my $timer    = Mojo::IOLoop->timer( $DEADLINE_SECONDS =>
      sub { $deadline->reject('notification deadline'); return; } );
my $poll = Mojo::IOLoop->recurring(
    $POLL_SECONDS => sub {
        if (   $broker->snapshot->{channels}{async_alpha}{queued}
            && $broker->snapshot->{channels}{async_beta}{queued} )
        {
            $deadline->resolve;
        }
        return;
    }
);
await_result($deadline);
Mojo::IOLoop->remove($timer);
Mojo::IOLoop->remove($poll);
my $alpha = $broker->take('async_alpha');
my $beta  = $broker->take('async_beta');
is_deeply( [ map { $_->[2] } @{ $alpha->{notifications} } ],
    ['alpha'], 'the first consumer drains only its channel' );
is_deeply( [ map { $_->[2] } @{ $beta->{notifications} } ],
    ['beta'], 'the other consumer retains its notifications' );
$schema->storage->disconnect;
ok( !$broker->{async_db}, 'storage retirement closes the owned listener' );
is( scalar @{ $queries->connections },
    0, 'the query leases retire independently' );
ok( await_result( $broker->listen_to_p('async_alpha') ),
    'native registrations reconnect' );
isnt( $broker->backend_pid, $pid, 'reconnection obtains a fresh backend' );
ok( $broker->take('async_alpha')->{gap},
    'reconnection reports the missed notification interval' );
$schema->storage->disconnect;
done_testing();
1;
