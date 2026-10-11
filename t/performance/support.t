# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Carp qw(croak);
use FindBin;
use lib "$FindBin::Bin/../../script/lib";
use English qw(-no_match_vars);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use GPForum::Performance::Support qw(run_bounded monotonic redact);
our $VERSION = '0.001';

# Core constants allow tests to run before application dependency installation.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    TERMINATION_BOUND => 5,
    ACCEPTED_CODE     => 7,
};

my $directory = tempdir( CLEANUP => 1 );
my $log       = File::Spec->catfile( $directory, 'partial.log' );
my $started   = monotonic();
my $error;
{
    local $ENV{GPFORUM_DATABASE_PASSWORD} = 'private-test-secret';
    try {
        run_bounded(
            [
                $EXECUTABLE_NAME,
                '-e',
'$|=1; print qq{password=private-test-secret dbi:Pg:dbname=private;host=private\n}; sleep 60'
            ],
            { timeout => 0.2, log => $log }
        );
    }
    catch ($caught) { $error = $caught; };
}
isa_ok( $error, 'GPForum::Performance::CommandError' );
ok( $error->{timed_out}, 'timeout classified' );
cmp_ok( monotonic() - $started,
    '<', TERMINATION_BOUND, 'owned subprocess terminated in bounded time' );
open my $handle, '<', $log or croak 'Cannot read timeout diagnostic';
my $raw = do { local $INPUT_RECORD_SEPARATOR = undef; <$handle> };
close $handle or croak 'Cannot close timeout diagnostic';
unlike(
    $raw,
    qr/private-test-secret|dbname=/msx,
    'partial logs redact credentials and the entire DSN'
);

my $pid;
try {
    run_bounded(
        [ $EXECUTABLE_NAME, '-e', 'sleep 60' ],
        {
            timeout   => 10,
            on_sample => sub ( $owned, $elapsed ) {
                $pid = $owned;
                croak 'synthetic cancellation';
            }
        }
    );
}
catch ($caught) { $error = $caught; };
like(
    "$error",
    qr/synthetic[ ]cancellation/msx,
    'monitor interruption propagated'
);
ok( !kill( 0, $pid ), 'interrupted owned process reaped' );

my %result;
my $stdout = run_bounded(
    [ $EXECUTABLE_NAME, '-e', 'print qq{structured\n}; exit 7' ],
    { timeout => 1, accepted_codes => [ACCEPTED_CODE], result => \%result }
);
is( $stdout, "structured\n",
    'accepted nonzero command keeps structured stdout' );
is( $result{returncode}, ACCEPTED_CODE, 'caller receives actual exit code' );
ok( !$result{timed_out}, 'successful accepted code is not a timeout' );

%result = ( initialized => 1 );
try {
    run_bounded(
        [ $EXECUTABLE_NAME, '-e', 'print qq{{"partial":1}\n}; exit 1' ],
        { timeout => 1, result => \%result } );
}
catch ($caught) { $error = $caught; };
is( $result{returncode}, 1, 'failed command exit retained' );
like( $result{output}, qr/"partial":1/msx,
    'failed structured partial stdout remains available internally' );
{
    # A caller's password may itself be the protocol name. Test URI parsing
    # separately from the intentionally conservative environment redaction.
    local $ENV{GPFORUM_DATABASE_PASSWORD} = q{};
    local $ENV{PGPASSWORD}                = q{};
    local $ENV{POSTGRES_PASSWORD}         = q{};
    is(
        redact('postgresql://user:private@localhost'),
        'postgresql://[redacted]@localhost',
        'URI credentials redacted without residual backslash'
    );
}

done_testing;
1;
