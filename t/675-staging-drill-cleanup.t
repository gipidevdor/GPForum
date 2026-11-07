# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Carp       qw(croak);
use File::Temp qw(tempdir);
use Test::More;
use lib 'lib';
use lib 't/lib';
use GPForum::Service::Operations::StagingDrill;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
our $VERSION = '0.001';

my $service_class = 'GPForum::Service::Operations::StagingDrill';
my $create        = $service_class->can('_create_throwaway');
my $restore_phase = $service_class->can('_run_dump_restore_phase');
my $admin         = bless { statements => [] }, 'GPForum::Test::DrillHandle';
my $connections   = 0;
my $service       = $service_class->new(
    admin_dsn => 'dbi:Pg:dbname=fixture_admin;host=fixture.invalid' );
my $failed_connect = with_replaced_subs(
    $service_class,
    {
        _connect => sub ($dsn) {
            ++$connections;
            return $admin if $connections == 1;
            croak 'fixture first connection failed after CREATE';
        },
        _execute => sub ( $self, $evidence, $options ) {
            $create->( $self, $options, 'fresh' );
            return undef;
        },
    },
    sub {
        return $service->run(
            {
                database_prefix => 'gpforum_drill_fixture',
                seed_profile    => 'none'
            }
        );
    }
);

is( $failed_connect->{status},
    'fail', 'first connection failure fails overall drill' );
like(
    $failed_connect->{error},
    qr/fixture[ ]first[ ]connection[ ]failed/msx,
    'original failure retained'
);
is( scalar @{ $service->created },
    0, 'cleanup retires database ownership after the run' );
is_deeply(
    $failed_connect->{databases_dropped},
    ['gpforum_drill_fixture_fresh'],
    'unconnected owned database still dropped'
);
is_deeply(
    $admin->{statements},
    [
        'CREATE DATABASE "gpforum_drill_fixture_fresh"',
        'DROP DATABASE IF EXISTS "gpforum_drill_fixture_fresh" WITH (FORCE)',
    ],
    'cleanup drops exactly the database this run created'
);
ok( $admin->{disconnected}, 'admin connection closed after cleanup' );

# Reusing a service after an earlier cleanup must never drop a name it no
# longer owns. A different process may have created that name in between.
my $before = scalar @{ $admin->{statements} };
with_replaced_subs(
    $service_class,
    { _execute => sub (@) { return undef; } },
    sub { return $service->run( { seed_profile => 'none' } ); }
);
is( scalar @{ $admin->{statements} },
    $before, 'a second run cannot drop databases from an earlier run' );

my $cleanup_service = $service_class->new;
my $cleanup_admin   = bless { statements => [], refuse_drop => 1 },
  'GPForum::Test::DrillHandle';
my $later_admin     = bless { statements => [] }, 'GPForum::Test::DrillHandle';
my $cleanup_failure = with_replaced_subs(
    $service_class,
    {
        _execute => sub ( $self, @ ) {
            $self->created(
                [
                    { name => 'owned_first',  admin_dbh => $later_admin },
                    { name => 'owned_second', admin_dbh => $cleanup_admin },
                ]
            );
            croak 'fixture primary failure';
        }
    },
    sub { return $cleanup_service->run( { seed_profile => 'none' } ); }
);
is( $cleanup_failure->{status}, 'fail', 'cleanup failures fail the drill' );
like(
    $cleanup_failure->{error},
    qr/fixture[ ]primary[ ]failure/msx,
    'cleanup preserves the primary failure'
);
is_deeply( $cleanup_failure->{databases_dropped},
    ['owned_first'], 'cleanup continues after one database cannot be dropped' );
is_deeply( $cleanup_failure->{databases_kept},
    ['owned_second'], 'remaining owned database is named in evidence' );
like(
    $cleanup_failure->{cleanup_errors}[0],
    qr/fixture[ ]drop[ ]failure/msx,
    'cleanup failure is retained separately'
);
ok( $cleanup_admin->{disconnected},
    'failed drop still closes the admin handle' );
is_deeply( $cleanup_service->created, [],
    'ownership retired even after failure' );

my $tools          = bless {}, 'GPForum::Test::DrillHandle';
my $dump_service   = $service_class->new( tools => $tools );
my $failed_restore = with_replaced_subs(
    $service_class,
    {
        _seed_if_requested => sub ( $self, $options ) { return undef; },
        _row_counts        => sub ($dbh) {
            return { schema_versions => 1, users => 0, threads => 0 };
        },
        _create_throwaway => sub ( $self, $options, $suffix ) {
            return { dsn => 'fixture-target', dbh => $admin };
        },
        _execute => sub ( $self, $evidence, $options ) {
            $evidence->{_fresh} = { dsn => 'fixture-source', dbh => $admin };
            $evidence->{fresh_migrate} = { status => 'pass' };
            $restore_phase->( $self, $evidence, $options );
            return undef;
        },
    },
    sub { return $dump_service->run( { seed_profile => 'none' } ); }
);

is( $failed_restore->{status},
    'fail', 'restore client failure fails overall drill' );
like(
    $failed_restore->{error},
    qr/fixture[ ]restore[ ]failure/msx,
    'restore error reported'
);
ok( $tools->{dump_written},
    'temporary dump was really written before restore failure' );
ok( !-e $tools->{dump_path},
    'temporary database contents deleted immediately on unwinding' );
is( $failed_restore->{fresh_migrate}->{status},
    'pass', 'completed phase retained' );
ok( !exists $failed_restore->{_fresh},
    'failure evidence retains no DB handle' );

done_testing;

package GPForum::Test::DrillHandle {    ## no critic (Modules::ProhibitMultiplePackages) -- no database calls in deterministic cleanup regression tests
    use v5.40;
    use Carp qw(croak);

    sub do ( $self, $sql ) {            ## no critic (Subroutines::ProhibitBuiltinHomonyms) -- implements the DBI handle API used by the drill
        push @{ $self->{statements} }, $sql;
        if ( $self->{refuse_drop} && $sql =~ /\A DROP/msx ) {
            croak 'fixture drop failure';
        }
        return 1;
    }
    sub quote_identifier ( $self, $name ) { return qq{"$name"}; }
    sub disconnect       ($self) { $self->{disconnected} = 1; return 1; }

    sub dump_database ( $self, $dsn, $path ) {
        $self->{dump_path} = $path;
        open my $handle, '>', $path
          or croak 'Cannot write temporary dump fixture';
        print {$handle} 'fixture database bytes'
          or croak 'Cannot write fixture bytes';
        close $handle or croak 'Cannot close temporary dump fixture';
        $self->{dump_written} = 1;
        return undef;
    }

    sub restore_database ( $self, $dsn, $path ) {
        croak 'fixture restore failure';
    }
}
1;
