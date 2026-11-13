# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp       qw(croak);
use English    qw(-no_match_vars);
use IPC::Open3 qw(open3);
use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::AdminBootstrap;
use GPForum::Command::Migrate;
use GPForum::Command::Usage;

our $VERSION = '0.001';

const my $EXIT_USAGE => 2;
const my $EXIT_SHIFT => 8;
const my $USAGE      => "Usage: bin/gpforum-x [--limit N]\n";

# B6: misuse always says what was wrong, once, before the usage; and through
# the front door the usage names the verb the operator typed.

subtest 'the shared parser says which option it did not know' => sub {
    my $table = {
        numbers  => { '--limit' => [ limit => 'positive_integer' ] },
        switches => { '--json'  => { json => 1 } },
        usage    => $USAGE,
    };
    for my $case (
        [ ['--bogus'], qr/\A --bogus [ ] is [ ] not [ ] an [ ] option/msx ],
        [ [ '--limit', 'ten' ], qr/above [ ] zero, [ ] not [ ] 'ten'/msx ],
        [ ['--limit'], qr/\A --limit [ ] takes [ ] a [ ] whole [ ] number/msx ],
      )
    {
        my ( $arguments, $reason ) = @{$case};
        my $error = _refusal(
            sub {
                GPForum::Command::Usage->parse_options( $arguments, {},
                    $table );
            }
        );
        ok( GPForum::Command::Usage->is_usage($error),
            "@{$arguments} is misuse" );
        like( "$error", $reason,            'and says what was wrong' );
        like( "$error", qr/\n\nUsage: /msx, 'before the usage' );
    }
    my $choice = _refusal(
        sub {
            GPForum::Command::Usage->option_choice( 'huge', [qw(small medium)],
                $USAGE, '--profile' );
        }
    );
    like(
        "$choice",
        qr/of [ ] small, [ ] medium, [ ] not [ ] 'huge'/msx,
        'a choice lists what it takes'
    );
};

subtest 'a usage error prints the usage once' => sub {
    my ( $status, $errors ) = _stderr(
        sub {
            GPForum::Command::Usage->error( "--bogus is wrong\n\n$USAGE",
                $USAGE );
        }
    );
    is( $status, $EXIT_USAGE, 'misuse is 2' );
    my @usages = $errors =~ /^Usage:/gmsx;
    is( scalar @usages, 1, 'with the usage once, not twice' );
    like( $errors, qr/\A --bogus [ ] is [ ] wrong/msx, 'after the reason' );
};

subtest 'admin says what was wrong with its command line' => sub {
    for my $case (
        [ [],          qr/\A Say [ ] what [ ] to [ ] do/msx ],
        [ ['promote'], qr/\A 'promote' [ ] is [ ] not [ ] something/msx ],
        [
            ['create'],
            qr/\A gpforum [ ] admin [ ] create [ ] needs [ ] --email/msx
        ],
        [
            [ 'create', '--email', 'you@example.com' ],
            qr/needs [ ] --username/msx
        ],
        [
            [ 'create', '--email' ],
            qr/\A --email [ ] needs [ ] a [ ] value/msx
        ],
        [ ['grant'],                            qr/\A Say [ ] whom/msx ],
        [ [ 'grant', 'you', '--user-id', 'x' ], qr/one [ ] of [ ] them/msx ],
        [
            [ 'grant', '--user-id', 'x', '--bogus' ],
            qr/\A --bogus [ ] is [ ] not [ ] an [ ] option/msx
        ],
      )
    {
        my ( $arguments, $reason ) = @{$case};
        my ( $status,    $errors ) = _stderr(
            sub { GPForum::Command::AdminBootstrap->new->run( @{$arguments} ) }
        );
        is( $status, $EXIT_USAGE, "admin @{$arguments} is misuse" );
        like( $errors, $reason, 'saying what was wrong' );
        my @usages = $errors =~ /^Usage:/gmsx;
        is( scalar @usages, 1, 'with the usage once' );
    }
};

subtest 'migrate too' => sub {
    for my $case (
        [ ['--aply'], qr/\A --aply [ ] is [ ] not [ ] an [ ] option/msx ],
        [ [ '--plan',  '--apply' ],         qr/\A Choose [ ] one [ ] of/msx ],
        [ [ '--check', '--no-partitions' ], qr/goes [ ] with [ ] applying/msx ],
      )
    {
        my ( $arguments, $reason ) = @{$case};
        my ( $status,    $errors ) = _stderr(
            sub { GPForum::Command::Migrate->new->run( @{$arguments} ) } );
        is( $status, $EXIT_USAGE, "migrate @{$arguments} is misuse" );
        like( $errors, $reason, 'saying what was wrong' );
    }
};

subtest 'the adapters that read their own options say the misuse too' => sub {
    for my $case (
        [
            'mail_in', ['--bogus'],
            qr/\A --bogus [ ] is [ ] not [ ] an [ ] option/msx
        ],
        [
            'sign_posts', ['--bogus'],
            qr/\A --bogus [ ] is [ ] not [ ] an [ ] option/msx
        ],
        [ 'gemini', [], qr/\A --cert [ ] is [ ] required[.]/msx ],
        [
            'gemini',
            [ '--cert', 'absent.crt', '--key', 'absent.key' ],
qr/\A --cert [ ] names [ ] absent[.]crt, [ ] which [ ] is [ ] not/msx
        ],
        [
            'gemini',
            [ '--port', '0' ],
            qr/\A --port [ ] takes [ ] a [ ] whole [ ] number [ ] above/msx
        ],
      )
    {
        my ( $adapter, $arguments, $reason ) = @{$case};
        my $run = _adapter( $adapter, @{$arguments} );
        is( $run->{status}, $EXIT_USAGE, "$adapter @{$arguments} is misuse" );
        like( $run->{errors}, $reason, 'saying what was wrong' );
        my @usages = $run->{errors} =~ /^Usage:/gmsx;
        is( scalar @usages, 1, 'then the usage' );
    }
};

done_testing();

sub _refusal ($code) {
    try {
        $code->();
    }
    catch ($error) {
        return $error;
    };

    return undef;
}

sub _stderr ($code) {
    my $errors = q{};
    open my $capture, '>', \$errors or croak 'capture stderr';
    my $status;
    {
        local *STDERR = $capture;
        $status = $code->();
    }
    close $capture or croak 'close stderr';

    return ( $status, $errors );
}

# An adapter run as the front door runs it, in a process of its own: on
# misuse it exits.
sub _adapter ( $adapter, @arguments ) {
    my $pid = open3(
        my $input,
        my $output,
        undef,
        $EXECUTABLE_NAME,
        '-Ilib',
        '-e',
        "require GPForum::CLI::$adapter;"
          . " GPForum::CLI::$adapter->new->run(\@ARGV)",
        q{--},
        @arguments
    );
    close $input or croak 'close the input';
    my $errors = do { local $INPUT_RECORD_SEPARATOR = undef; <$output> };
    close $output or croak 'close the output';
    waitpid $pid, 0;

    return { errors => $errors // q{}, status => $CHILD_ERROR >> $EXIT_SHIFT };
}

1;
