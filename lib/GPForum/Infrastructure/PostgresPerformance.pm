# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::PostgresPerformance;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Carp          qw(croak);
use JSON::MaybeXS qw(encode_json decode_json);
use Fcntl         qw(O_WRONLY O_CREAT O_EXCL);
use IO::Handle;
use Const::Fast;
use List::Util qw(any);
use GPForum::Infrastructure::PostgresProfile;
use GPForum::X::Check;

our $VERSION = '0.001';
__PACKAGE__->requires('config');
__PACKAGE__->requires('dbh');

const my @TUNING =>
  qw(shared_buffers effective_cache_size work_mem maintenance_work_mem random_page_cost effective_io_concurrency jit max_connections track_io_timing);
const my %ALLOWED => map { $_ => 1 } @TUNING;
const my %SAFETY => (
    fsync              => 'on',
    full_page_writes   => 'on',
    synchronous_commit => 'on',
    autovacuum         => 'on',
);

# These modes all confirm local WAL durability. Remote acknowledgement policy
# remains the operator's choice; remote_apply must not be mislabeled unsafe.
const my %DURABLE_COMMIT => map { $_ => 1 }
  qw(on local remote_write remote_apply);

const my %BYTE_UNIT =>
  ( kB => 1_024, MB => 1_048_576, GB => 1_073_741_824, B => 1 );
const my $SUPERUSER_RESERVE => 3;
const my $PRIVATE_MODE      => oct '600';
const my %OVERRIDE_SOURCE => map { $_ => 1 }
  ( 'command line', 'database', 'user', 'database user', 'client', 'session' );

sub settings ($self) {
    my @names = (
        @TUNING,
        sort keys %SAFETY,
        qw(superuser_reserved_connections reserved_connections autovacuum_max_workers max_parallel_workers_per_gather hash_mem_multiplier checkpoint_completion_target checkpoint_timeout max_wal_size min_wal_size wal_buffers),
    );
    my $bind = join q{,}, map { q{?} } @names;
    my $rows = $self->dbh->selectall_arrayref(
"SELECT name, setting, unit, source, context, pending_restart, boot_val, reset_val FROM pg_catalog.pg_settings WHERE name IN ($bind) ORDER BY name",
        { Slice => {} },
        @names
    );
    return { map { $_->{name} => $_ } @{$rows} };
}

# Values are compared in the units pg_settings actually reports (including
# block-size prefixes), never by comparing SHOW's formatted strings.
sub equivalent ( $class, $row, $wanted ) {
    return 0 if !$row || !defined $row->{setting};
    if ( $wanted =~ /\A([[:digit:].]+)(kB|MB|GB)\z/msx ) {
        my $expected = $1 * $BYTE_UNIT{$2};
        my ( $blocks, $unit ) =
          ( $row->{unit} // q{} ) =~ /\A([[:digit:]]*)(kB|MB|GB|B)\z/msx;
        return 0 if !defined $unit;
        return
          abs(
            $row->{setting} * ( $blocks || 1 ) * $BYTE_UNIT{$unit} - $expected )
          < 1;
    }
    return $row->{setting} == $wanted
      if $wanted =~ /\A[[:digit:].]+\z/msx;
    return $row->{setting} eq $wanted;
}

sub inspect ($self) {
    my $profile =
      GPForum::Infrastructure::PostgresProfile->new( config => $self->config )
      ->recommendation;
    my ( $settings, $error );
    try { $settings = $self->settings; }
    catch ($caught) { $error = 'pg_settings unavailable'; };
    my @findings = map {
        +{
            severity  => 'recommendation',
            parameter => 'profile',
            reason    => $_
        }
    } @{ $profile->{issues} };
    if ($error) {
        push @findings,
          { severity => 'critical', parameter => 'evidence', reason => $error };
    }
    $settings //= {};
    for my $name ( sort keys %SAFETY ) {
        if ( !_safety_ok( $name, $settings->{$name} ) ) {
            push @findings,
              {
                severity  => 'critical',
                parameter => $name,
                reason    =>
'durability or autovacuum safety setting is unsafe or unavailable'
              };
        }
    }
    my ( $tuning, $changes ) = _tuning_findings( $profile, $settings );
    push @findings, @{$tuning};
    my $required = $profile->{required_connections};
    my $usable =
      ( $settings->{max_connections}{setting} // 0 ) -
      ( $settings->{superuser_reserved_connections}{setting}
          // $SUPERUSER_RESERVE ) -
      ( $settings->{reserved_connections}{setting} // 0 );
    if ( $usable < $required ) {
        push @findings,
          {
            severity  => 'critical',
            parameter => 'max_connections',
            reason    =>
"connection budget needs $required nonreserved slots (2 per web worker plus 16 for workers, operations and reload overlap)"
          };
    }
    if ( $profile->{memory_mb} && !$profile->{sufficient_memory} ) {
        push @findings,
          {
            severity  => 'critical',
            parameter => 'memory',
            reason    => 'profile cannot fit the declared database memory'
          };
    }
    my $critical = grep { $_->{severity} eq 'critical' } @findings;
    return {
        status =>
          _status( $critical, \@findings, $self->config->postgres_strict ),
        available            => $error                         ? 0 : 1,
        strict               => $self->config->postgres_strict ? 1 : 0,
        topology             => $self->config->postgres_topology,
        profile              => $profile,
        settings             => $settings,
        findings             => \@findings,
        changes              => $changes,
        required_connections => $required,
        conformant           => @findings ? 0 : 1,
        default_parameters   => [
            sort grep { ( $settings->{$_}{source} // q{} ) eq 'default' }
              keys %{$settings}
        ],
        applied_by_gpforum => 0
    };
}

sub _safety_ok ( $name, $row ) {
    return 0 if !$row || !defined $row->{setting};
    return exists $DURABLE_COMMIT{ $row->{setting} }
      if $name eq 'synchronous_commit';
    return __PACKAGE__->equivalent( $row, $SAFETY{$name} );
}

sub _status ( $critical, $findings, $strict ) {
    return 'fail' if $critical || ( $strict && @{$findings} );
    return @{$findings} ? 'degraded' : 'ok';
}

sub _tuning_findings ( $profile, $settings ) {
    my ( @findings, @changes );
    for my $name (@TUNING) {
        my $row      = $settings->{$name};
        my $expected = $profile->{settings}{$name};
        if (
            !$row
            || ( defined $expected
                && !__PACKAGE__->equivalent( $row, $expected ) )
            || ( $row && $row->{pending_restart} )
          )
        {
            push @findings,
              {
                severity  => 'recommendation',
                parameter => $name,
                reason    => !$row ? 'setting unavailable'
                : $row->{pending_restart}
                ? 'pending_restart: effective value is not the configured value'
                : 'effective value differs from selected profile',
                expected => $expected
              };
            if ( defined $expected ) {
                push @changes,
                  {
                    name       => $name,
                    value      => $expected,
                    activation => $row && $row->{context} eq 'postmaster'
                    ? 'restart'
                    : 'reload; reconnect sessions with overrides',
                    before => $row
                  };
            }
        }
    }
    return ( \@findings, \@changes );
}

sub enforce ($self) {
    my $report = $self->inspect;
    return $report if $report->{status} eq 'ok';
    my $message = 'PostgreSQL performance: '
      . join( '; ',
        map { "$_->{parameter}: $_->{reason}" } @{ $report->{findings} } )
      . '. Run gpforum postgres-performance inspect; docs/ops/postgres-performance.md';
    if ( $self->config->postgres_strict ) {
        GPForum::X::Check->throw( message => $message );
    }
    warn "$message\n";
    return $report;
}

sub identity ($self) {
    my $identity = $self->dbh->selectrow_hashref(
q{SELECT current_database() AS database, current_user AS operator, inet_server_addr()::text AS address, current_setting('port') AS port, version() AS version, pg_is_in_recovery() AS in_recovery, current_setting('is_superuser') AS superuser}
    );
    if ( $identity->{superuser} eq 'on' ) {
        $identity->{system_identifier} = $self->dbh->selectrow_array(
q{SELECT system_identifier::text FROM pg_catalog.pg_control_system()}
        );
    }
    return $identity;
}

sub _overrides ($self) {
    my $rows = $self->dbh->selectall_arrayref(
q{SELECT f.name, f.setting, f.error, s.context, s.pending_restart FROM pg_catalog.pg_file_settings f LEFT JOIN pg_catalog.pg_settings s ON s.name = f.name WHERE f.sourcefile = current_setting('data_directory') || '/postgresql.auto.conf' ORDER BY f.seqno},
        { Slice => {} }
    );
    croak 'postgresql.auto.conf contains invalid settings' if any {
        defined $_->{error}
          && !(
            ( $_->{context} // q{} ) eq 'postmaster' && ( $_->{pending_restart}
                || ( $_->{error} // q{} ) eq 'setting could not be applied' )
          )
    } @{$rows};
    return {
        map  { $_->{name} => $_->{setting} }
        grep { exists $ALLOWED{ $_->{name} // q{} } } @{$rows}
    };
}

sub plan ($self) {
    my $report   = $self->inspect;
    my $identity = $self->identity;
    $report->{identity} = $identity;
    $report->{format}   = 'gpforum-postgres-plan-v1';
    if ( $identity->{superuser} eq 'on' ) {
        $report->{overrides} = $self->_overrides;
    }
    return $report;
}

# ALTER SYSTEM cannot be transactional. Journal each intention and completion
# before continuing; an interrupted/partially failed run can be restored.
sub apply ( $self, $plan, $options ) {
    croak 'unsupported plan format'
      if ( $plan->{format} // q{} ) ne 'gpforum-postgres-plan-v1';
    $self->_authorize( $plan->{identity}, $options );
    croak 'a sized profile and known storage are required'
      if !$plan->{profile}{valid} || @{ $plan->{profile}{issues} };
    my $recommended =
      GPForum::Infrastructure::PostgresProfile->new( config => $self->config )
      ->recommendation;
    my %allow = map { $_ => 1 } @{ $options->{allow} // [] };
    croak 'explicit --allow parameter list required' if !keys %allow;
    croak 'parameter is outside the tuning allowlist'
      if any { !exists $ALLOWED{$_} } keys %allow;
    my %change = map { $_->{name} => $_ } @{ $plan->{changes} };
    croak '--allow must name only changes in the reviewed plan'
      if any { !$change{$_} } keys %allow;
    return $self->_mutate(
        $options,
        sub ($journal) {
            my $current  = $self->_overrides;
            my $settings = $self->settings;
            my @entries;
            for my $name ( sort keys %allow ) {
                my $change = $change{$name};
                my $entry =
                  _apply_entry( $name, $change, $plan, $recommended, $current,
                    $settings );
                if ($entry) { push @entries, $entry; }
            }
            return \@entries;
        }
    );
}

sub _setting_available ($row) {
    return
         $row
      && defined $row->{setting}
      && defined $row->{context}
      && defined $row->{source};
}

sub _apply_entry ( $name, $change, $plan, $recommended, $current, $settings ) {
    croak "setting unavailable or not mutable: $name"
      if !_setting_available( $settings->{$name} );
    croak 'plan value differs from its profile'
      if ( $change->{value} // q{} ) ne
      ( $plan->{profile}{settings}{$name} // q{} );
    croak 'profile changed since plan; create a new plan'
      if !$recommended->{valid}
      || ( $change->{value} // q{} ) ne
      ( $recommended->{settings}{$name} // q{} );
    return undef
      if defined $current->{$name}
      && $current->{$name} eq $change->{value};
    croak "configuration changed since plan: $name"
      if !_same( $current->{$name},           $plan->{overrides}{$name} )
      || !_same( $settings->{$name}{setting}, $change->{before}{setting} )
      || !_same( $settings->{$name}{source},  $change->{before}{source} );
    croak "setting cannot be changed globally: $name"
      if $settings->{$name}{context} eq 'internal'
      || exists $OVERRIDE_SOURCE{ $settings->{$name}{source} };
    return {
        name   => $name,
        before => $current->{$name},
        after  => $change->{value}
    };
}

sub restore ( $self, $original, $options ) {
    croak 'unsupported journal format'
      if ( $original->{format} // q{} ) ne 'gpforum-postgres-journal-v1';
    $self->_authorize( $original->{identity}, $options );
    return $self->_mutate(
        $options,
        sub ($journal) {
            my $current = $self->_overrides;
            my @entries;
            for my $entry ( reverse @{ $original->{entries} } ) {
                my $name = $entry->{name};
                croak 'journal parameter is outside the tuning allowlist'
                  if !exists $ALLOWED{$name};
                next if _same( $current->{$name}, $entry->{before} );
                croak "configuration changed after apply: $name"
                  if !_same( $current->{$name}, $entry->{after} );
                push @entries,
                  {
                    name   => $name,
                    before => $current->{$name},
                    after  => $entry->{before}
                  };
            }
            return \@entries;
        }
    );
}

sub _authorize ( $self, $identity, $options ) {
    croak 'explicit --controlled-instance is required'
      if !$options->{controlled};
    croak 'managed PostgreSQL must be configured through its provider'
      if $self->config->postgres_topology eq 'managed';
    croak 'an autocommit administrative connection is required'
      if !$self->dbh->{AutoCommit};
    my $actual = $self->identity;
    croak 'ALTER SYSTEM requires a separate superuser operator connection'
      if $actual->{superuser} ne 'on';
    croak 'endpoint changed since review; create a new plan for this server'
      if !_same( $actual->{address}, $identity->{address} )
      || !_same( $actual->{port},    $identity->{port} );
    croak '--instance must match the reviewed PostgreSQL system_identifier'
      if !defined $options->{instance}
      || $options->{instance} ne $actual->{system_identifier}
      || ( $identity->{system_identifier} // q{} ) ne
      $actual->{system_identifier};
    return;
}

sub _same ( $a, $b ) {
    return !defined $a ? !defined $b : defined $b && $a eq $b;
}

sub _mutate ( $self, $options, $prepare ) {
    my $dbh = $self->dbh;
    $dbh->do('SELECT pg_catalog.pg_advisory_lock(18273, 41)');
    my ( $result, $error, $fh );
    try {
        my $journal = {
            format    => 'gpforum-postgres-journal-v1',
            identity  => $self->identity,
            timestamp => time,
            entries   => []
        };
        my $entries = $prepare->($journal);
        croak '--journal path is required' if !$options->{journal};
        sysopen $fh, $options->{journal}, O_WRONLY | O_CREAT | O_EXCL,
          $PRIVATE_MODE
          or croak 'cannot create new journal (never overwrite an earlier run)';
        $fh->autoflush(1);

        # JSON Lines: the first record is metadata; each subsequent record is
        # a complete snapshot, usable even if the final line was interrupted.
        _record( $fh, $journal );
        for my $entry ( @{$entries} ) {
            push @{ $journal->{entries} }, $entry;
            $entry->{state} = 'attempting';
            _record( $fh, $journal );
            my $name = $dbh->quote_identifier( $entry->{name} );
            my $sql =
              defined $entry->{after}
              ? "ALTER SYSTEM SET $name = " . $dbh->quote( $entry->{after} )
              : "ALTER SYSTEM RESET $name";
            $dbh->do($sql);
            $entry->{state} = 'written';
            _record( $fh, $journal );
        }
        croak 'configuration reload was refused'
          if !$dbh->selectrow_array('SELECT pg_catalog.pg_reload_conf()');
        $journal->{reload_requested} = 1;
        _record( $fh, $journal );
        close $fh or croak 'cannot close journal';
        $fh     = undef;
        $result = {
            status     => 'ok',
            identity   => $journal->{identity},
            written    => scalar @{$entries},
            journal    => $options->{journal},
            activation =>
'reload requested; verify on a fresh runtime connection; restart remains an operator action'
        };
    }
    catch ($caught) { $error = $caught; };
    if ($fh) {
        if ( !close $fh ) { $error //= 'cannot close failed journal'; }
    }
    $dbh->do('SELECT pg_catalog.pg_advisory_unlock(18273, 41)');
    croak $error if defined $error;
    return $result;
}

sub _record ( $fh, $journal ) {
    print {$fh} encode_json($journal), "\n" or croak 'cannot write journal';
    $fh->sync or croak 'cannot sync journal before changing PostgreSQL';
    return;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::PostgresPerformance - Inspect and control PostgreSQL performance settings.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $report = GPForum::Infrastructure::PostgresPerformance->new(config => $config, dbh => $dbh)->inspect;

=head1 DESCRIPTION

One pg_settings assessment shared by connections, runtime evidence, readiness and the administrative CLI. Mutation requires explicit cluster authority, identity and individual setting authorization; journal records precede ALTER SYSTEM.

=head1 SUBROUTINES/METHODS

settings reads effective catalog values; equivalent normalizes units; inspect assesses findings; enforce warns or throws in strict mode; identity identifies the cluster; plan captures settings and previous tuning overrides; apply and restore write journaled changes and request reload. Neither restarts the server.

=head1 DIAGNOSTICS

Failures name missing evidence, nonconforming settings or refused authorization.

=head1 CONFIGURATION AND ENVIRONMENT

Receives PostgreSQL settings through L<GPForum::Config>.

=head1 DEPENDENCIES

Uses the existing GPForum configuration, OS and database infrastructure.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Resource estimates require an operator budget; measurements remain necessary.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. BSD-3-Clause.

=cut
