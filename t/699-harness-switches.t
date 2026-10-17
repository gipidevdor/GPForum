# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp       qw(croak);
use English    qw(-no_match_vars);
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use Mojo::File qw(path);
use Symbol     qw(gensym);
use Test::More;

our $VERSION = '0.001';

# An explicit prove --exec ignores HARNESS_PERL_SWITCHES, so a .proverc that
# preloaded the reactor that way ran Devel::Cover and NYTProf on nothing;
# script/coverage worked around it by loading GPForum::OS::Reactor ahead of
# Devel::Cover, which then measured that module at 0%. The front door now
# chooses the backend in the environment, and the switches reach the tests.

my $scratch = tempdir( CLEANUP => 1 );
my $probe   = path( $scratch, 'switch.t' );
$probe->spew( qq{print "1..1\\n";\n}
      . q{print exists $INC{'Text/Abbrev.pm'} ? "ok 1\n" : "not ok 1\n";}
      . "\n" );

my ( $status, $output ) = _run(
    [
        $EXECUTABLE_NAME,
        '-MApp::Prove',
        '-e',
        'my $prove = App::Prove->new; $prove->process_args(@ARGV);'
          . ' exit( $prove->run ? 0 : 1 );',
        $probe->to_string,
    ],
    HARNESS_PERL_SWITCHES => '-MText::Abbrev',
);
is( $status, 0, 'prove in this checkout honors HARNESS_PERL_SWITCHES' )
  or diag $output;

my $coverage = path('script/coverage')->slurp;
ok(
    index( $coverage,
        'HARNESS_PERL_SWITCHES=-MDevel::Cover "$gpforum_carton" exec prove' )
      >= 0,
    'script/coverage loads Devel::Cover through the harness switches'
);
unlike( $coverage, qr/--exec/msx,
    'and no --exec that would load a module before it' );

SKIP: {
    if ( !eval { require Devel::Cover::DB; 1 } ) {
        skip 'Devel::Cover is a develop dependency', 1;
    }
    my $database = path( $scratch, 'cover_db' );
    ( $status, $output ) = _run(
        [
            $EXECUTABLE_NAME,
            '-MApp::Prove',
            '-e',
            'my $prove = App::Prove->new; $prove->process_args(@ARGV);'
              . ' exit( $prove->run ? 0 : 1 );',
            '-l',
            't/688-native-reactor.t',
        ],
        HARNESS_PERL_SWITCHES => "-MDevel::Cover=-db,$database,-silent,1",
    );
    my $module   = 'lib/GPForum/OS/Reactor.pm';
    my $measured = 0;
    if ( $status == 0 ) {
        my $db =
          Devel::Cover::DB->new( db => $database->to_string )->merge_runs;
        $db->calculate_summary( statement => 1, files => [$module] );
        $measured = $db->summary( $module, 'statement', 'percentage' ) // 0;
    }
    cmp_ok( $measured, q{>}, 0,
        'GPForum::OS::Reactor is measured, not loaded ahead of Devel::Cover' )
      or diag $output;
}

done_testing();

sub _run ( $command, %environment ) {
    local %ENV = ( %ENV, %environment );
    delete local $ENV{HARNESS_ACTIVE};
    my $error = gensym;
    my $pid   = open3( my $input, my $output, $error, @{$command} );
    close $input or croak "close child input: $OS_ERROR";
    my $text = do { local $INPUT_RECORD_SEPARATOR = undef; <$output> // q{} };
    $text .= do { local $INPUT_RECORD_SEPARATOR = undef; <$error> // q{} };
    close $output or croak "close child output: $OS_ERROR";
    close $error  or croak "close child error: $OS_ERROR";
    waitpid $pid, 0;

    return ( $CHILD_ERROR, $text );
}

1;
