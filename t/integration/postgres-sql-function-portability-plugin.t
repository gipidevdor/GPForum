# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use JSON::MaybeXS;
use Test::More;
use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Service::Portability::ImportJobStore;
use GPForum::Service::Portability::LegacyIdMapper;
use GPForum::Service::Plugin::Registry;
use GPForum::Service::Plugin::FailureRecorder;
use GPForum::Service::Plugin::HookDispatcher;
use GPForum::Test::FixedClock;
use GPForum::Test::PgDatabase;
use GPForum::Test::SequenceId;
our $VERSION = '0.001';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all =>
      'set GPFORUM_TEST_DSN for portability/plugin differential tests';
}
my %pair =
  map { $_ => GPForum::Test::PgDatabase->fresh( seed => 1 ) } qw(function perl);
my $clock = GPForum::Test::FixedClock->new( iso8601 => '2026-10-11T10:00:00Z' );
my %services;
for my $path (qw(function perl)) {
    my %old    = $path eq 'perl' ? ( functions => undef ) : ();
    my $ids    = GPForum::Test::SequenceId->new;
    my %common = (
        schema     => $pair{$path}->schema,
        clock      => $clock,
        id_service => $ids,
        %old,
    );
    $services{$path} = {
        imports  => GPForum::Service::Portability::ImportJobStore->new(%common),
        mapper   => GPForum::Service::Portability::LegacyIdMapper->new(%common),
        plugins  => GPForum::Service::Plugin::Registry->new(%common),
        failures => GPForum::Service::Plugin::FailureRecorder->new(%common)
    };
}
my $created = same(
    'imports',
    'create_job',
    {
        actor_user_id => seed_id( user => 2 ),
        manifest      => {
            source_system  => 'legacy',
            source_version => '1',
            adapter_name   => 'fixture',
            dry_run        => 1,
            records => { users => 1, categories => 1, threads => 1, posts => 2 }
        }
    }
);
my $job = $created->{job}{import_job_id};
same( 'imports', 'update_progress', $job, { posts => 1,   users => undef } );
same( 'imports', 'update_progress', $job, { posts => '1', users => q{} } );
same(
    'imports',
    'record_failure',
    {
        import_job_id      => $job,
        source_record_type => 'post',
        source_record_id   => 'legacy-1',
        error_code         => 'invalid',
        error_message      => 'missing body',
        payload            => { original => 'failed' }
    }
);
same(
    'imports',
    'record_failure',
    {
        import_job_id      => $job,
        source_record_type => 'post',
        source_record_id   => 'legacy-1',
        error_code         => 'changed',
        error_message      => 'ignored'
    }
);
same(
    'mapper',
    'map_identifier',
    {
        import_job_id => $job,
        legacy_type   => 'post',
        legacy_id     => 'legacy-2',
        native_type   => 'post',
        native_id     => seed_id( post => 1 ),
        canonical_url => '/p/one',
        visibility    => 'public'
    }
);
same(
    'mapper',
    'map_identifier',
    {
        import_job_id => $job,
        legacy_type   => 'post',
        legacy_id     => 'legacy-2',
        native_type   => 'post',
        native_id     => seed_id( post => 2 ),
        canonical_url => '/p/two',
        visibility    => 'private'
    }
);
same( 'mapper', 'find_native', 'post', 'legacy-2' );
my $manifest = {
    name                     => 'differential',
    version                  => '1.0',
    author                   => 'Fixture',
    compatible_gpforum_range => '>=0.1',
    capabilities             => ['analytics'],
    required_permissions     => [],
    config_schema            => {},
    hooks                    => [
        {
            hook_name          => 'post.created',
            callback_name      => 'observe',
            timeout_ms         => 100,
            execution_order    => 5,
            side_effect_policy => 'read_only'
        }
    ]
};
my $plugin = same( 'plugins', 'install', $manifest )->{plugin}{plugin_id};
same( 'plugins', 'install', $manifest );
same( 'plugins', 'enable',  $plugin );
same( 'plugins', 'enable',  $plugin );
same( 'plugins', 'disable', $plugin );
same(
    'failures',
    'record_failure',
    {
        plugin_id     => $plugin,
        hook_name     => 'post.created',
        error_class   => 'timeout',
        error_message => 'timed out',
        context       => { test => 1 }
    }
);

for my $path (qw(function perl)) {
    my %old = $path eq 'perl' ? ( functions => undef ) : ();
    $services{$path}{hooks} = GPForum::Service::Plugin::HookDispatcher->new(
        schema           => $pair{$path}->schema,
        failure_recorder => $services{$path}{failures},
        handlers         => {
            observe => sub ( $payload, $hook ) {
                return {
                    observed => $payload->{post_id},
                    plugin   => $hook->get_column('plugin_id')
                };
            }
        },
        %old,
    );
}
same( 'hooks', 'dispatch', 'post.created',
    { post_id => seed_id( post => 1 ) } );
for my $table (
    qw(import_jobs import_failures legacy_id_map plugins plugin_hooks plugin_failures)
  )
{
    is_deeply(
        snapshot( $pair{function}->dbh, $table ),
        snapshot( $pair{perl}->dbh,     $table ),
        "same persisted $table"
    );
}
done_testing();

sub same( $service, $method, @args ) {
    my %result =
      map { $_ => $services{$_}{$service}->$method(@args) } qw(function perl);
    is_deeply(
        normalize( $result{function} ),
        normalize( $result{perl} ),
        "$service/$method returns the same document"
    );
    return $result{function};
}

sub normalize($value) {
    return undef                               if !defined $value;
    return [ map { normalize($_) } @{$value} ] if ref $value eq 'ARRAY';
    if (   ref $value eq 'HASH'
        || ref $value && eval { $value->can('get_columns') } )
    {
        my %row = ref $value eq 'HASH' ? %{$value} : $value->get_columns;
        return { map { $_ => normalize( $row{$_} ) } keys %row };
    }
    return 0 + $value if JSON::MaybeXS::is_bool($value);

    return $value;
}

sub snapshot( $dbh, $table ) {
    return $dbh->selectall_arrayref( "SELECT * FROM $table ORDER BY 1",
        { Slice => {} } );
}
1;
