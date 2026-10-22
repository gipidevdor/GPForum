# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use English       qw(-no_match_vars);
use File::Temp    qw(tempdir);
use IPC::Open3    qw(open3);
use JSON::MaybeXS qw(decode_json);
use Mojo::File    qw(path);
use Symbol        qw(gensym);
use Test::More;

our $VERSION = '0.001';

# The drills and the evidence helper took their ports, directories and output
# from variables -- GPFORUM_PITR_PORT, GPFORUM_STANDBY_DIR,
# GPFORUM_EVIDENCE_DIR -- where every other command takes flags (audit 2.2,
# D4'). They take flags now, and the old variables are not read: nothing was
# released with them. No case here starts a cluster: each stops at its
# arguments.

const my $USAGE        => 2;
const my $FAILURE      => 1;
const my $STATUS_SHIFT => 8;
const my $PITR_PORT    => 55_991;
const my $PITR_TIMEOUT => 15;
const my %DRILL => (
    'script/pitr-drill' => {
        flags          => [qw(--port --dir --keep --json --timeout --validate)],
        old            => [qw(GPFORUM_PITR_PORT GPFORUM_PITR_DIR)],
        refusal_status => $FAILURE,
        inline_help    => 1,
    },
    'script/standby-drill' => {
        flags => [qw(--primary-port --standby-port --dir --keep)],
        old   => [
            qw(GPFORUM_STANDBY_PRIMARY_PORT GPFORUM_STANDBY_PORT
              GPFORUM_STANDBY_DIR)
        ],
        refusal_status => $USAGE,
        inline_help    => 0,
    },
);

for my $drill ( sort keys %DRILL ) {
    subtest $drill => sub {
        my $help = _run( {}, $drill, '--help' );
        is( $help->{status}, 0, '--help' );
        for my $flag ( @{ $DRILL{$drill}{flags} } ) {
            my $documented =
              $DRILL{$drill}{inline_help}
              ? qr/\Q$flag\E \b/msx
              : qr/^ \s+ \Q$flag\E \b/msx;
            like( $help->{out}, $documented, "offers $flag" );
        }
        unlike( $help->{out}, qr/GPFORUM_/msx, 'and names no variable' );

        my $port = ( grep { /port/msx } @{ $DRILL{$drill}{flags} } )[0];
        is( _run( {}, $drill, $port )->{status},
            $USAGE, "$port without a value is a usage error" );
        my $word = _run( {}, $drill, $port, 'many' );
        is( $word->{status}, $USAGE, "$port takes a number" );
        like( $word->{err}, qr/['"]many['"]/msx, 'and says what it was given' );

        # The drill removes its directory when it ends: one that holds files
        # is refused before anything starts, and left as it was. A relative
        # one is the caller's, not the checkout's.
        my $caller = path( tempdir( CLEANUP => 1 ) )->realpath->to_string;
        path( $caller, 'mine' )->make_path->child('notes.txt')->touch;
        my $full = _run_in( $caller, {}, $drill, '--dir', 'mine' );
        is(
            $full->{status},
            $DRILL{$drill}{refusal_status},
            '--dir naming a directory with files is refused'
        );
        if ( $DRILL{$drill}{inline_help} ) {
            like(
                $full->{err},
                qr/owned_workspace_refused/msx,
                'the owned-workspace failure has a stable diagnostic code'
            );
        }
        else {
            like(
                $full->{err},
                qr/--dir [ ] \Q$caller\E\/mine [ ] is [ ] not [ ] empty/msx,
                'is refused, named from where the drill was run'
            );
        }
        ok( -e path( $caller, 'mine', 'notes.txt' ), 'and nothing is removed' );

        for my $old ( @{ $DRILL{$drill}{old} } ) {
            my $result = _run( { $old => 'old' }, $drill, '--bogus' );
            unlike( $result->{err}, qr/\Q$old\E/msx, "$old is not read" );
        }
    };
}

subtest 'the Perl PITR frontend forwards flags to the owned drill' => sub {
    my $directory = path( tempdir( CLEANUP => 1 ), 'owned' )->to_string;

    # Empty PATH prevents discovery of any PostgreSQL tool. Invoke the current
    # interpreter explicitly so the frontend still parses its real arguments
    # and emits partial evidence before starting any external server.
    local $ENV{PATH} = q{};
    my $result = _run(
        {},                  $EXECUTABLE_NAME,
        'script/pitr-drill', '--json',
        '--port',            $PITR_PORT,
        '--timeout',         $PITR_TIMEOUT,
        '--dir',             $directory,
        '--keep'
    );
    is( $result->{status}, $FAILURE,
        'an unavailable server tool remains a failed measurement' );
    my $evidence = decode_json( $result->{out} );
    is( $evidence->{reason}, 'missing_required_tool',
        'the command stops before any PostgreSQL server starts' );
    is( $evidence->{configuration}{port},
        $PITR_PORT, '--port reaches the implementation' );
    is( $evidence->{configuration}{timeout_seconds},
        $PITR_TIMEOUT, '--timeout reaches the implementation' );
    ok( $evidence->{cleanup}{kept}, '--keep reaches the implementation' );
    ok(
        -f path( $directory, '.gpforum-pitr-owned' ),
        '--dir selects the owned workspace'
    );
    ok(
        !$evidence->{configuration}{external_database_used},
        'argument handling never connects to an application database'
    );
};

subtest 'the PITR JSON frontend preserves an occupied workspace' => sub {
    my $directory = path( tempdir( CLEANUP => 1 ), 'occupied' )->make_path;
    my $existing  = $directory->child('notes.txt')->spurt('existing bytes');
    local $ENV{PATH} = q{};
    my $result = _run( {}, $EXECUTABLE_NAME, 'script/pitr-drill', '--json',
        '--dir', $directory->to_string );
    is( $result->{status}, $FAILURE,
        'an unowned workspace yields a failed measurement' );
    my $evidence = decode_json( $result->{out} );
    is( $evidence->{status}, 'fail', 'JSON never claims the drill ran' );
    is( $evidence->{reason}, 'owned_workspace_refused',
        'partial evidence identifies the safety refusal' );
    ok(
        !$evidence->{cleanup}{workspace_removed},
        'cleanup does not claim removal of caller files'
    );
    is( $existing->slurp, 'existing bytes', 'caller bytes are preserved' );
    ok(
        !-e $directory->child('.gpforum-pitr-owned'),
        'the refused directory is never claimed by the drill'
    );
};

subtest 'script/gpforum-evidence-live' => sub {
    my $helper  = 'script/gpforum-evidence-live';
    my $printed = _run( {}, $helper, '--out', q{/tmp/it's here},
        '--env-file', '/srv/staging.env' );
    is( $printed->{status}, 0, '--out and --env-file' );
    like(
        $printed->{out},
        qr/^ evidence_dir='\/tmp\/it'\\''s [ ] here' $/msx,
        'the directory, quoted for the shell the commands are pasted into'
    );
    like(
        $printed->{out},
        qr/^ evidence_env_file='\/srv\/staging[.]env' $/msx,
        'and the env file'
    );
    like(
        $printed->{out},
        qr{--env-file [ ] "\$evidence_env_file"}msx,
        'which the printed verify reads'
    );
    unlike( $printed->{out}, qr/GPFORUM_EVIDENCE/msx,
        'with no old variable in them' );

    my $old = _run( { GPFORUM_EVIDENCE_DIR => '/var/tmp/evidence' }, $helper );
    is( $old->{err}, q{}, 'GPFORUM_EVIDENCE_DIR is not read' );
    like(
        $old->{out},
        qr/^ evidence_dir='\/tmp\/gpforum-evidence-live' $/msx,
        'the default directory is used'
    );
};

done_testing();

# A script's status, standard output and standard error, run with the
# variables given and no other GPFORUM_ one.
sub _run ( $variables, @command ) {
    delete local @ENV{ grep { /\A GPFORUM_/msx } keys %ENV };
    local @ENV{ keys %{$variables} } = values %{$variables};
    my $pid = open3( my $input, my $output, my $errors = gensym, @command );
    close $input or return {};
    my ( $out, $err ) = map { _slurp($_) } $output, $errors;
    waitpid $pid, 0;

    return {
        status => $CHILD_ERROR >> $STATUS_SHIFT,
        out    => $out,
        err    => $err
    };
}

# The same, run from another directory.
sub _run_in ( $directory, $variables, $script, @arguments ) {
    my $command = path($script)->to_abs->to_string;
    my $here    = path->to_abs;
    chdir $directory or return {};
    my $result = _run( $variables, $command, @arguments );
    chdir $here or return {};

    return $result;
}

sub _slurp ($handle) {
    local $INPUT_RECORD_SEPARATOR = undef;

    my $text = <$handle>;

    return $text // q{};
}

1;
