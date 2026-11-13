# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Admin::ConsoleReader;
use GPForum::Test::AdminRuntimeStatus;
use GPForum::Test::AnsweringFunctions;
use GPForum::Test::Promise qw(await_result);

our $VERSION = '0.001';

const my $LIST_LIMIT => 5;

# The console's reads over the users, the moderation queue and the async
# jobs, on a call layer that answers each api.admin_console_* function with
# the rows stated here: what the console asks for and what it makes of the
# answers. What those functions read is checked on PostgreSQL in
# t/integration/postgres-sql-function-admin.t; the role catalog, role
# bindings, the review pages and the permission gate in
# t/integration/postgres-admin-authorization.t.
my $functions = GPForum::Test::AnsweringFunctions->new(
    answers => {
        admin_console_counts => sub ($values) {
            return [ { total => $values->{dead_letters} ? 1 : 2 } ];
        },
        admin_console_dead_letters => [
            {
                dead_letter_id => 'dead-letter-1',
                error_class    => 'worker_failed',
                error_message  => 'retry limit exceeded',
            }
        ],
        admin_console_outbox => [
            {
                job_type  => 'notification.dispatch',
                outbox_id => 'outbox-1',
                status    => 'pending',
            }
        ],
        admin_console_reports =>
          [ { report_id => 'report-1', reason => 'spam', status => 'open' } ],
        admin_console_users =>
          [ { id => 'user-1', status => 'active', username => 'admin_user' } ],
    }
);
my $console = GPForum::Service::Admin::ConsoleReader->new(
    functions        => $functions,
    metrics_snapshot => GPForum::Test::AdminRuntimeStatus->new,
    readiness        => GPForum::Test::AdminRuntimeStatus->new,
    schema           => {},
);
is( $console->list_users( { limit => $LIST_LIMIT } )->[0]{username},
    'admin_user', 'admin console lists users' );
is_deeply(
    $functions->asked('admin_console_users')->[0],
    { row_limit => $LIST_LIMIT, status => undef },
    'admin user list applies limit, and any status'
);

my $jobs = $console->async_jobs( { limit => $LIST_LIMIT } );
is( $jobs->{outbox_messages}[0]{outbox_id},
    'outbox-1', 'admin console lists outbox messages' );
is( $jobs->{dead_letters}[0]{dead_letter_id},
    'dead-letter-1', 'admin console lists dead letters' );
is( $jobs->{outbox_message_total}, 2, 'with the outbox counted' );
is( $jobs->{dead_letter_total},    1, 'and the dead letters counted' );

my $summary =
  await_result( $console->dashboard_summary_p( { limit => $LIST_LIMIT } ) );
is( $summary->{moderation}{reports}[0]{report_id},
    'report-1', 'admin console dashboard includes moderation queue' );
is_deeply(
    $functions->asked('admin_console_reports')->[0],
    { row_limit => $LIST_LIMIT, status => 'open' },
    'the open reports, up to the limit'
);
is( $summary->{health}{readiness}{status},
    'ok', 'admin console exposes health status' );
is( $summary->{health}{benchmark}{status},
    'manual', 'admin console exposes read-only benchmark status' );

# A count that fails reads 0 and leaves the dashboard standing.
my $failing = GPForum::Service::Admin::ConsoleReader->new(
    functions => GPForum::Test::AnsweringFunctions->new(
        answers => { admin_console_counts => sub { die "gone\n" } }
    ),
    schema => {},
);
is( $failing->count_outbox, 0, 'a count that fails reads 0' );

done_testing();

1;
