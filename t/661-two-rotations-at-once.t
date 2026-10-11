# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use Crypt::URandom ();
use English        qw(-no_match_vars);
use File::Temp     qw(tempdir);
use List::Util     qw(uniq);
use Mojo::File     qw(path);
use POSIX          qw(_exit);
use Time::HiRes    qw(sleep);
use Test::More;

use lib 'lib';

use GPForum::Command::Secret;
use GPForum::Command::Support::EnvironmentFileEdit;

our $VERSION = '0.001';

# Token review, iteration 4 (friction 14): gpforum secret rotate read the
# file, edited it and renamed the edit over it with no lock, so two
# rotations at once each read the same file and the second rename dropped
# the first one's new token -- a token a scraper may already have been
# given, refused from then on. Rotations take turns now, on an advisory lock
# of the file itself.

const my $SECRET_FILE_MODE => oct '640';
const my $TOKEN_BYTES      => 32;
const my $FIRST            => 'a' x 64;
const my $ROTATORS         => 2;
const my $ROTATIONS        => 8;
const my $THINKING         => 0.02;
const my $CHILD_FAILED     => 1;
const my $EXIT_SHIFT       => 8;

local $ENV{LC_ALL} = 'en_US.UTF-8';

my $directory = tempdir( CLEANUP => 1 );

subtest 'two rotations at once keep both new tokens' => sub {
    my $file = path( $directory, 'forum.env' );
    $file->spew("GPFORUM_ENV=production\nGPFORUM_METRICS_TOKEN=$FIRST\n");
    chmod $SECRET_FILE_MODE, "$file" or croak "chmod: $ERRNO";

    # Each rotation takes a moment between its read and its rename, as a
    # slow disk or a busy host gives it, so two at once overlap.
    my @rotators;
    for ( 1 .. $ROTATORS ) {
        my $child = fork // croak "fork: $ERRNO";
        if ( !$child ) {
            my $failed = 0;
            for ( 1 .. $ROTATIONS ) {
                $failed ||= _rotate("$file");
            }
            _exit( $failed ? $CHILD_FAILED : 0 );
        }
        push @rotators, $child;
    }
    my $failed = 0;
    for my $child (@rotators) {
        waitpid $child, 0;
        $failed ||= $CHILD_ERROR >> $EXIT_SHIFT;
    }
    is( $failed, 0, 'every rotation was written' );

    my %value = %{ GPForum::Command::Support::EnvironmentFileEdit->values_of(
            [ split /^/msx, $file->slurp ]
        )
    };
    my @tokens = uniq( $value{GPFORUM_METRICS_TOKEN},
        split /,/msx, $value{GPFORUM_METRICS_TOKENS} // q{} );
    is(
        scalar @tokens,
        $ROTATORS * $ROTATIONS + 1,
        'the first token and every rotation\'s, none lost'
    );
    is( $tokens[-1],                   $FIRST, 'the first still last' );
    is( ( stat $file )[2] & oct '777', $SECRET_FILE_MODE, 'its mode kept' );
    is( scalar( () = glob "$directory/*" ),
        1, 'and no lock file left beside it' );
};

subtest 'a file it cannot open is said as before' => sub {
    my $missing = path( $directory, 'missing.env' );
    my $ran =
      GPForum::Command::Support::EnvironmentFileEdit->locked( "$missing",
        sub { return 'ran' } );
    is( $ran, 'ran', 'the code runs, to say why it cannot read it' );
};

done_testing();

sub _rotate ($file) {
    my $command = GPForum::Command::Secret->new(
        file               => $file,
        services_installed => 1,
        metrics_reread     => 1,
        generate           => sub {
            sleep $THINKING;
            return unpack 'H*', Crypt::URandom::urandom($TOKEN_BYTES);
        },
    );
    my $output = q{};
    my $status;
    {
        open my $stdout, '>', \$output or croak 'capture stdout';
        local *STDOUT = $stdout;
        $status = $command->run( 'rotate', 'metrics' );
        close $stdout or croak 'close stdout';
    }

    return $status;
}

1;
