# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Test::More;
use lib 'lib', 't/lib';
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to check table maintenance';
}
my $database = GPForum::Test::PgDatabase->fresh;
my $dbh      = $database->dbh;

for my $table (
    qw(threads thread_counters posts search_documents outbox_messages sessions
    rate_limit_buckets thread_read_state user_read_marker_deltas)
  )
{
    my $options = $dbh->selectall_arrayref(
        'SELECT option_name, option_value FROM pg_catalog.pg_class c '
          . 'CROSS JOIN LATERAL pg_catalog.pg_options_to_table(c.reloptions) '
          . 'WHERE c.oid = ?::regclass',
        { Slice => {} },
        "public.$table"
    );
    my %option = map { $_->{option_name} => $_->{option_value} } @{$options};
    is( $option{autovacuum_vacuum_scale_factor},
        '0.02', "$table vacuums before dead tuples reach the default 20%" );
    is( $option{autovacuum_analyze_scale_factor},
        '0.01', "$table refreshes planner statistics sooner" );
    ok( !exists $option{autovacuum_enabled},
        "$table does not override the cluster's autovacuum switch" );
    if (   $table eq 'threads'
        || $table eq 'sessions'
        || $table eq 'rate_limit_buckets' )
    {
        is( $option{fillfactor}, '90',
            'existing HOT-update space is preserved' );
    }
    if ( $table eq 'thread_counters' ) {
        is( $option{fillfactor}, '80',
            'thread counters keep their update space' );
    }
}

my ($threshold) =
  $dbh->selectrow_array( 'SELECT option_value FROM pg_catalog.pg_class c '
      . 'CROSS JOIN LATERAL pg_catalog.pg_options_to_table(c.reloptions) '
      . q{WHERE c.oid = 'public.categories'::regclass }
      . q{AND option_name = 'autovacuum_analyze_threshold'} );
is( $threshold, '0', 'small-category statistics policy is preserved' );

done_testing();
1;
