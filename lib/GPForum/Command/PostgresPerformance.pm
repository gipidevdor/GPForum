# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Command::PostgresPerformance;

use Mojo::Base -base, -signatures;
use v5.40;
use Carp qw(croak);
use Cwd  qw(getcwd);
use Const::Fast;
use DBI;
use Fcntl         qw(O_WRONLY O_CREAT O_EXCL);
use JSON::MaybeXS qw(decode_json encode_json);
use Mojo::File    qw(path);
use GPForum::Command::Usage;
use GPForum::Config;
use GPForum::Infrastructure::PostgresPerformance;

our $VERSION = '0.001';
has config => sub { return GPForum::Config->from_environment; };
has dbh    => undef;    # optional: injected administrative connection for tests

# The directory the command was typed in, which a relative path reads from:
# the front door moves the check verbs to the code directory.
has directory => sub { return getcwd(); };

const my $PRIVATE_MODE => oct '600';
const my %MODE         => map { $_ => 1 } qw(inspect plan apply verify);

sub run ( $self, @arguments ) {
    return GPForum::Command::Usage->help( \*STDOUT, $self->usage_text )
      if GPForum::Command::Usage->wants_help(@arguments);
    my $mode   = shift @arguments // 'inspect';
    my $parsed = $self->_options( $mode, \@arguments );
    return $parsed if !ref $parsed;
    my %options = %{$parsed};
    try {
        my $config = $self->config;
        if ( $options{strict} ) { $config->postgres_strict(1); }
        my $dbh     = $self->_connect($mode);
        my $service = GPForum::Infrastructure::PostgresPerformance->new(
            config => $config,
            dbh    => $dbh
        );
        my $report = _operation( $service, $mode, \%options );
        $report->{mode}    = $mode;
        $report->{command} = 'gpforum-postgres-performance';
        if ( $options{output} ) { _write_plan( $report, \%options ); }

        if ( $options{json} ) {
            GPForum::Command::Usage->json( \*STDOUT, $report );
        }
        else { print _text($report) or croak 'cannot write report'; }
        return 1 if $report->{status} eq 'fail';
        return 1 if $mode eq 'verify' && @{ $report->{findings} // [] };
    }
    catch ($error) { return GPForum::Command::Usage->failure($error); };
    return 0;
}

# The options a mode takes, read as every gpforum verb reads them. --output
# is plan's alone and refused before anything connects: apply had changed
# the cluster's settings by the time it said so. A relative path reads from
# the directory the command was typed in.
sub _options ( $self, $mode, $arguments ) {
    my $usage = $self->usage_text;
    return GPForum::Command::Usage->error(
        'expected inspect, plan, apply or verify', $usage )
      if !exists $MODE{$mode};

    return GPForum::Command::Usage->read_arguments(
        $usage,
        sub {
            my $options = GPForum::Command::Usage->parse_options(
                $arguments,
                {},
                {
                    switches => {
                        '--json'                => { json   => 1 },
                        '--strict'              => { strict => 1 },
                        '--controlled-instance' =>
                          { 'controlled-instance' => 1 },
                    },
                    values => {
                        '--allow' => sub ( $options, $value ) {
                            push @{ $options->{allow} },
                              GPForum::Command::Usage->option_given( $value,
                                $usage, '--allow' );
                        },
                        '--instance' => sub ( $options, $value ) {
                            $options->{instance} =
                              GPForum::Command::Usage->option_given( $value,
                                $usage, '--instance' );
                        },
                        map { ( "--$_" => $self->_path_option( $_, $usage ) ) }
                          qw(journal output plan restore),
                    },
                    usage => $usage,
                }
            );
            if ( defined $options->{output} && $mode ne 'plan' ) {
                GPForum::Command::Usage->misuse( 'cli.misuse.mode_only',
                    { option => '--output', mode => 'plan' }, $usage );
            }

            return $options;
        }
    );
}

# What reads an option that names a file: its value, from where the command
# was typed when it is relative.
sub _path_option ( $self, $name, $usage ) {
    return sub ( $options, $value ) {
        my $file =
          GPForum::Command::Usage->option_given( $value, $usage, "--$name" );
        $options->{$name} =
          path($file)->is_abs
          ? $file
          : path( $self->directory, $file )->to_string;
    };
}

sub _write_plan ( $report, $options ) {
    sysopen my $fh, $options->{output}, O_WRONLY | O_CREAT | O_EXCL,
      $PRIVATE_MODE
      or croak 'cannot create new plan file';
    print {$fh} encode_json($report), "\n" or croak 'cannot write plan';
    close $fh or croak 'cannot close plan';

    return;
}

sub _operation ( $service, $mode, $options ) {
    my $report;
    if ( $mode eq 'apply' ) {
        croak 'choose exactly one of --plan or --restore'
          if !$options->{plan} == !$options->{restore};
        my $input =
          _read( $options->{plan} // $options->{restore}, $options->{restore} );
        my $authorization = {
            controlled => $options->{'controlled-instance'},
            instance   => $options->{instance},
            journal    => $options->{journal},
            allow      => [ map { split /,/msx } @{ $options->{allow} // [] } ]
        };
        $report =
            $options->{restore}
          ? $service->restore( $input, $authorization )
          : $service->apply( $input, $authorization );
    }
    else {
        $report = $mode eq 'plan' ? $service->plan : $service->inspect;
        $report->{identity} //= $service->identity;
    }
    return $report;
}

sub _connect ( $self, $mode ) {
    return $self->dbh if $self->dbh;
    my $c     = $self->config;
    my $admin = $mode eq 'apply'
      || ( $mode eq 'plan' && length( $c->admin_database_user // q{} ) );
    croak
'apply requires GPFORUM_ADMIN_DATABASE_USER in a separate operator environment'
      if $admin && !length( $c->admin_database_user // q{} );
    my $dbh = DBI->connect(
        $admin
        ? (
            length( $c->admin_database_dsn // q{} )
            ? $c->admin_database_dsn
            : $c->database_dsn,
            $c->admin_database_user,
            $c->admin_database_password // q{}
          )
        : ( $c->database_dsn, $c->database_user, $c->database_password ),
        {
            AutoCommit     => 1,
            RaiseError     => 1,
            PrintError     => 0,
            pg_enable_utf8 => 1
        }
    );
    for my $sql ( @{ $c->database_session_settings } ) { $dbh->do($sql); }
    return $dbh;
}

sub _read ( $path, $journal ) {
    open my $fh, '<', $path or croak 'cannot read plan/journal';
    my ( $completed_record, $text );
    while ( my $line = <$fh> ) {
        if ($journal) {
            try { $completed_record = decode_json($line); }
            catch ($error) { croak 'invalid journal record' if !eof $fh; };
        }
        else { $text .= $line; }
    }
    close $fh or croak 'cannot close plan/journal';
    return decode_json($text)                   if !$journal;
    croak 'journal contains no complete record' if !$completed_record;
    return $completed_record;
}

sub _text ($report) {
    my @lines = ("PostgreSQL performance: $report->{status}");
    push @lines,
      'Cluster: '
      . ( $report->{identity}{system_identifier}
          // 'identifier requires operator privileges' );
    if ( $report->{profile} ) {
        push @lines,
"Profile: $report->{profile}{name}; RAM $report->{profile}{memory_mb} MiB; reserve $report->{profile}{reserve_mb} MiB";
    }
    for my $name ( sort keys %{ $report->{settings} // {} } ) {
        my $r = $report->{settings}{$name};
        push @lines, join q{ }, $name, $r->{setting}, $r->{unit} // q{},
          "source=$r->{source}", "context=$r->{context}",
          'pending_restart=' . ( $r->{pending_restart} ? 1 : 0 ),
          'recommended='
          . ( $report->{profile}{settings}{$name} // 'safety/observation' );
    }
    push @lines,
      map { "$_->{severity}: $_->{parameter}: $_->{reason}" }
      @{ $report->{findings} // [] };
    push @lines,
      map { "plan: $_->{name} = $_->{value} ($_->{activation})" }
      @{ $report->{changes} // [] };
    if ( exists $report->{written} ) {
        push @lines, "Settings written: $report->{written}";
    }
    if ( $report->{journal} ) {
        push @lines, "Journal: $report->{journal}; $report->{activation}";
    }
    return join( "\n", @lines ) . "\n";
}

sub usage_text ($class) {
    return <<'USAGE';
Usage: gpforum postgres-performance inspect|plan|apply|verify [--json] [--strict]

inspect                 Read effective pg_settings and sized profile.
plan [--output FILE]     Save a reviewable plan (new file, never overwritten).
apply --plan FILE --instance SYSTEM_IDENTIFIER --controlled-instance
      --allow NAME[,NAME...] --journal NEW_FILE
apply --restore JOURNAL --instance SYSTEM_IDENTIFIER --controlled-instance
      --journal NEW_FILE
verify                  Read a fresh runtime connection; exit 1 on any mismatch.

Set GPFORUM_POSTGRES_PROFILE, TOPOLOGY, MEMORY_MB, RESERVE_MB, CPU_COUNT and
STORAGE in the usual environment. Automatic hardware detection is allowed
only for explicitly local PostgreSQL. Managed services use provider tooling.
Apply uses only GPFORUM_ADMIN_DATABASE_* credentials, requires a superuser,
and affects the entire identified cluster: --controlled-instance asserts
authority over every database it serves. It writes ALTER SYSTEM settings,
requests reload and journals previous overrides; it never restarts PostgreSQL.
Review restart requirements, then verify using the application's runtime role.
Strict also rejects recommendations; ordinary runtime tuning drift only warns.
See docs/ops/postgres-performance.md. Exit: 0 success, 1 failed, 2 usage.
USAGE
}

1;

__END__

=head1 NAME

GPForum::Command::PostgresPerformance - PostgreSQL performance administration.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Command::PostgresPerformance->new->run(qw(inspect --json));

=head1 DESCRIPTION

Implements inspect, plan, apply and verify through the existing front door. Reads runtime and separate administrator credentials from Config. See docs/ops/postgres-performance.md.

=head1 SUBROUTINES/METHODS

run executes a command and returns its exit status. usage_text describes authorization, plan and journal options.

=head1 DIAGNOSTICS

Failures name missing evidence, nonconforming settings or refused authorization.

=head1 CONFIGURATION AND ENVIRONMENT

Receives PostgreSQL settings through L<GPForum::Config>.

=head1 DEPENDENCIES

Uses the existing Good Phorum configuration, OS and database infrastructure.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Resource estimates require an operator budget; measurements remain necessary.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
