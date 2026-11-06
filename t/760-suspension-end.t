# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Operations::ScheduledJobs;
use GPForum::Service::Outbox::HandlerIdempotency;
use GPForum::Test::EndingStore;
use GPForum::Worker::Handler::SuspensionEnd;

our $VERSION = '0.001';

# The end of a timed suspension (v5.0.0-2.3.2), as the outbox delivers it:
# the handler hands it to the suspension store, and the hourly sweep queues
# the ends the store lacks. t/integration/postgres-suspension-ends.t runs
# both against PostgreSQL.

my $due = {
    domain_payload =>
      { suspension_id => 'suspension-1', user_id => 'member-1' },
    event_id   => 'suspension-1',
    event_type => 'user.suspension_end_due',
};
my $store   = GPForum::Test::EndingStore->new;
my $handler = GPForum::Worker::Handler::SuspensionEnd->new( store => $store );

ok( $handler->supports($due), 'the handler takes a suspension end' );
ok( !$handler->supports( { %{$due}, event_type => 'user.suspended' } ),
    'and not the suspension itself' );
ok(
    !$handler->supports(
        { %{$due}, domain_payload => { suspension_id => 'suspension-1' } }
    ),
    'nor an end that names no member'
);
is_deeply(
    $handler->handle($due),
    {
        action        => 'suspension.end',
        ended         => 1,
        suspension_id => 'suspension-1',
    },
    'it answers what the store did'
);
is_deeply(
    $store->calls,
    [ [ end_suspension => 'member-1', 'suspension-1' ] ],
    'having asked it to end that suspension of that member'
);
is(
    GPForum::Service::Outbox::HandlerIdempotency->new->key_for(
        $handler, $due
    ),
    'worker.suspension_end:suspension-1',
    'its claim is one per suspension'
);

my $jobs = GPForum::Service::Operations::ScheduledJobs->new(
    suspension_store => $store );
ok( ( grep { $_ eq 'suspension_ends' } @{ $jobs->job_names } ),
    'the hourly jobs include the sweep' );
is_deeply(
    $jobs->run_job( 'suspension_ends', { limit => 10 } ),
    { ok => 1, queued => 2 },
    'which queues through the store'
);
is_deeply(
    GPForum::Service::Operations::ScheduledJobs->new(
        suspension_store => undef
    )->run_job( 'suspension_ends', {} ),
    { ok => 1, queued => 0, skipped => 'unavailable' },
    'and is not run without one'
);

done_testing();

1;
