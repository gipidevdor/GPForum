# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
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
    1, 'CREATE ownership registered before first connection' );
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
