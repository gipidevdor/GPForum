# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use JSON::MaybeXS qw(decode_json);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::OsPreflight;
use GPForum::Config;
use GPForum::OS::Linux;
use GPForum::OS::Preflight;
use GPForum::OS::RuntimePolicy;
use GPForum::Runtime;
use GPForum::Service::I18N::CliCatalog;
use GPForum::Test::OSResourceSnapshot;
use GPForum::Test::OSTinyLinux;

our $VERSION = '0.001';

# GPFORUM_WEB_PROCESSES' default when the walkthrough was made.
const my $CONFIGURED_WEB => 4;

# What cap-to-cpu gives Hypnotoad on one CPU: GPFORUM_RUNTIME_MAX_WEB_PER_CPU.
const my $CAPPED_WEB => 2;

# A per-CPU allowance other than the default, to see it carried over.
const my $PER_CPU => 3;

# The walkthrough (docs/ops/evidence/2026-10-07-operator-walkthrough, item 3)
# read that the shipped units could not start on a 1-vCPU VPS: their
# ExecStartPre ran `os-preflight --strict`, which failed on any degraded
# check, and one CPU was always degraded twice -- its recommended worker
# count was read as 1, below GPFORUM_OS_MIN_RECOMMENDED_WORKERS (2), although
# the forum runs two web processes a CPU, and the configured 4 web processes
# were compared with 1 x 2 although Hypnotoad is given 2.

# A threshold one CPU does not reach: the two it carries are fewer.
const my $THRESHOLD => 3;

subtest 'the check counts the web processes Hypnotoad is given' => sub {
    my $runtime = _one_cpu( worker_policy => 'cap-to-cpu' );
    is(
        GPForum::OS::RuntimePolicy->new(
            config  => GPForum::Config->new,
            runtime => $runtime,
        )->hypnotoad_config->{workers},
        $CAPPED_WEB,
        'cap-to-cpu gives Hypnotoad two on one CPU'
    );
    is( $runtime->effective_web_processes,
        $CAPPED_WEB, 'and the runtime says the same number' );
    is( _check( $runtime, 'web_processes' )->{status},
        'ok', 'so the preflight finds nothing oversubscribed' );

    my $configured = _one_cpu( worker_policy => 'configured' );
    is( $configured->effective_web_processes,
        $CONFIGURED_WEB, 'the configured policy gives Hypnotoad all four' );
    is( _check( $configured, 'web_processes' )->{status},
        'degraded', 'and that is still reported as oversubscribed' );
};

subtest 'the policy comes from the configuration' => sub {
    my $runtime = GPForum::Runtime->from_config(
        GPForum::Config->new(
            runtime_worker_policy   => 'configured',
            runtime_max_web_per_cpu => $PER_CPU,
        )
    );
    is( $runtime->worker_policy,   'configured', 'the worker policy' );
    is( $runtime->max_web_per_cpu, $PER_CPU,     'and the processes per CPU' );
};

subtest 'one CPU carries the two web processes it is given' => sub {
    my $run =
      _run( _one_cpu( worker_policy => 'cap-to-cpu' ), '--strict', '--json' );
    is( decode_json( $run->{output} )->{status},
        'ok', 'one CPU is not degraded under the default threshold' );
    is( $run->{errors}, q{}, 'and says nothing on stderr' );
};

subtest 'a degraded host starts, and says why on stderr' => sub {
    my $config =
      GPForum::Config->new( os_min_recommended_workers => $THRESHOLD );
    my $run = _run( _one_cpu( worker_policy => 'cap-to-cpu' ),
        '--strict', '--json', $config );
    is( decode_json( $run->{output} )->{status},
        'degraded', 'one CPU is degraded' );
    is( $run->{status}, 0, 'but --strict lets the service start' );
    is_deeply(
        [ split /\n/msx, $run->{errors} ],
        [
            'os-preflight: ! workers: this host carries 2, fewer than'
              . ' GPFORUM_OS_MIN_RECOMMENDED_WORKERS (3)',
            'os-preflight:     Fix: set GPFORUM_OS_MIN_RECOMMENDED_WORKERS=2'
              . q{ in your shell's environment, or give the host more CPUs},
        ],
        'and says each degraded check, and its fix, on stderr for the journal'
    );

    my $quiet =
      _run( _one_cpu( worker_policy => 'cap-to-cpu' ), '--json', $config );
    is( $quiet->{status}, 0,   'without --strict the status is the same' );
    is( $quiet->{errors}, q{}, 'and stderr stays quiet, as before' );
};

subtest 'a failed check still stops the start' => sub {
    my $no_cpu = GPForum::Runtime->new(
        web_processes => 1,
        os_profile    => GPForum::OS::Linux->new(
            cpu_detection  => { count => 0, source => 'test' },
            resource_probe => GPForum::Test::OSResourceSnapshot->new,
        ),
    );
    my $strict = _run( $no_cpu, '--strict', '--json' );
    is( decode_json( $strict->{output} )->{status},
        'fail', 'no CPU count is a failure' );
    is( $strict->{status}, 1, 'and --strict exits 1 on it' );
    like(
        $strict->{errors},
        qr/^os-preflight: [ ] \S+ [ ] CPUs: [ ] they [ ] could [ ] not/msx,
        'naming the check that failed'
    );
    is( _run( $no_cpu, '--json' )->{status}, 1, 'as the default always did' );
};

done_testing();

sub _one_cpu (%options) {
    return GPForum::Runtime->new(
        web_processes => $CONFIGURED_WEB,
        os_profile    => GPForum::Test::OSTinyLinux->new(
            resource_probe => GPForum::Test::OSResourceSnapshot->new,
        ),
        os_feature_settings => GPForum::Config->new->os_feature_settings,
        %options,
    );
}

sub _check ( $runtime, $name ) {
    my ($check) =
      grep { $_->{name} eq $name }
      @{ GPForum::OS::Preflight->from_runtime($runtime)->report->{checks} };

    return $check // {};
}

# The command as the unit runs it, with the configuration's defaults or the
# configuration given after the arguments.
sub _run ( $runtime, @arguments ) {
    my $config = ref $arguments[-1] ? pop @arguments : GPForum::Config->new;
    my ( $output, $errors ) = ( q{}, q{} );
    my $status;
    my $command = GPForum::Command::OsPreflight->new(
        catalog => GPForum::Service::I18N::CliCatalog->new( language => 'en' ),
        config  => $config,
        runtime => $runtime,
    );

    # A fix names the shell's environment outside staging and production.
    delete local $ENV{GPFORUM_ENV};
    {
        open my $stdout, '>', \$output or croak 'capture stdout';
        open my $stderr, '>', \$errors or croak 'capture stderr';
        local *STDOUT = $stdout;
        local *STDERR = $stderr;
        $status = $command->run(@arguments);
        close $stdout or croak 'close stdout';
        close $stderr or croak 'close stderr';
    }

    return { output => $output, errors => $errors, status => $status };
}

1;
