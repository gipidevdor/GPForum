# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use English    qw(-no_match_vars);
use IPC::Open3 qw(open3);
use Mojo::File qw(path tempdir);
use Symbol     qw(gensym);
use Test::More;

our $VERSION = '0.001';

const my $EXECUTABLE   => oct '0755';
const my $STATUS_SHIFT => 8;

subtest 'production installs in parallel from the lock, under system Perl' =>
  sub {
    my $root = _checkout();
    is(
        _run(
            $root, { GPFORUM_CPM_WORKERS => 2 }, qw(--postgres --production)
        ),
        0,
        'production install succeeds'
    );
    my $args = $root->child('cpm.args')->slurp;
    like(
        $args,
        qr/--resolver\nsnapshot\n--no-default-resolvers\n/msx,
        'missing pins cannot fall back to CPAN'
    );
    like( $args, qr/--workers\n2\n/msx,
        'the operator can limit parallel builds' );
    like( $args, qr/--home\nlocal\n/msx,
        'archives stay where Carton bundle reads them' );
    like( $args, qr/--final-install\nall\n/msx,
        'build dependencies remain installed' );
    like(
        $args,
        qr/--top-level-phase\nconfigure,build,test,runtime\n/msx,
        'production keeps test and runtime, without develop'
    );
    like( $args, qr/--feature\npostgres\z/msx,
        'postgres is enabled explicitly' );
    my ( $status, $expected ) =
      _capture( path('script/gpforum-system-perl')->to_abs->to_string,
        '--require' );
    is( $status, 0, 'the system Perl is available' );
    chomp $expected;
    like( $args, qr/\A\Q$expected\E\n/msx,
        'cpm runs under the validated Perl' );
    is( $root->child('cpanfile.snapshot')->slurp,
        "locked\n", 'the lock is unchanged' );
    my $carton = $root->child('carton.commands')->slurp;
    like(
        $carton,
        qr/\Acheck\nexec [ ] perl [ ] -e [ ] 1\n/msx,
        'Carton checks the lock, then the interpreter shim is primed'
    );
    unlike( $carton, qr/^install/msx,
        'Carton did not install the distributions' );
  };

subtest 'development and cached installation retain their choices' => sub {
    my $root = _checkout();
    is( _run( $root, {} ), 0, 'default install succeeds' );
    my $args = $root->child('cpm.args')->slurp;
    like( $args, qr/--workers\n5\n/msx, 'five workers by default' );
    like(
        $args,
        qr/--top-level-phase\nconfigure,build,test,runtime,develop\z/msx,
        'development tools are included'
    );
    unlike( $args, qr/--feature/msx, 'postgres is opt-in' );
    $root->child('vendor/cache/authors/id')->make_path;
    is( _run( $root, {}, '--cached' ), 0, 'cached install succeeds' );
    my $mirror = $root->child('vendor/cache')->to_string;
    like(
        $root->child('cpm.args')->slurp,
        qr/--mirror\n\Q$mirror\E\n/msx,
        'the resolver uses only the local bundle mirror'
    );
};

subtest 'lock updates still use Carton' => sub {
    my $root = _checkout();
    is( _run( $root, {}, '--update' ), 0, 'development lock update succeeds' );
    ok( !-e $root->child('cpm.args'), 'cpm did not run' );
    like(
        $root->child('carton.commands')->slurp,
        qr/\Ainstall [ ] --without [ ] postgres\ncheck\n/msx,
        'Carton retains lock maintenance'
    );
};

subtest 'invalid input and installer failure stop before lock checks' => sub {
    for my $case (
        [ { GPFORUM_CPM_WORKERS => 0 },                 [] ],
        [ { GPFORUM_CPM_WORKERS => '-1' },              [] ],
        [ { GPFORUM_CPM_WORKERS => '2x' },              [] ],
        [ { PERL_CARTON_MIRROR => 'http://cpan.org/' }, [] ],
        [ {},                             [qw(--production --update)] ],
        [ {},                             ['--cached'] ],
        [ { GPFORUM_TEST_CPM_FAIL => 1 }, [] ],
      )
    {
        my ( $env, $args ) = @{$case};
        my $root = _checkout();
        isnt( _run( $root, $env, @{$args} ), 0, 'failure is propagated' );
        ok(
            !-e $root->child('carton.commands'),
            'no check or post-install command ran'
        );
    }
    my $root = _checkout();
    unlink $root->child('cpanfile.snapshot') or croak "unlink: $OS_ERROR";
    isnt( _run( $root, {} ), 0, 'a missing snapshot is refused' );
    ok( !-e $root->child('cpm.args'), 'without running cpm' );
};

done_testing();

sub _checkout {
    my $root = tempdir;
    $root->child('script')->make_path;
    for my $name (
        qw(bootstrap-deps gpforum-cpm gpforum-carton gpforum-system-perl))
    {
        path( 'script', $name )
          ->copy_to( $root->child( 'script', $name ) )
          ->chmod($EXECUTABLE);
    }
    $root->child('cpanfile')->spew("requires 'perl', '5.040';\n");
    $root->child('cpanfile.postgres')->spew("1;\n");
    $root->child('cpanfile.snapshot')->spew("locked\n");
    $root->child('cpm')->spew(<<'CPM');
#!/usr/bin/env perl
use v5.40;
open my $out, '>', 'cpm.args' or die $!;
print {$out} join "\n", $^X, @ARGV;
close $out or die $!;
exit($ENV{GPFORUM_TEST_CPM_FAIL} || 0);
CPM
    $root->child('carton')->spew(<<'CARTON');
#!/bin/sh
printf '%s\n' "$*" >> carton.commands
CARTON
    $root->child('cpm')->chmod($EXECUTABLE);
    $root->child('carton')->chmod($EXECUTABLE);
    $root->child('pg_config')
      ->spew("#!/bin/sh\necho /usr\n")
      ->chmod($EXECUTABLE);
    return $root;
}

sub _run ( $root, $env, @args ) {
    local %ENV = (
        %ENV,
        GPFORUM_CPM         => $root->child('cpm')->to_string,
        GPFORUM_CARTON      => $root->child('carton')->to_string,
        GPFORUM_PG_CONFIG   => $root->child('pg_config')->to_string,
        GPFORUM_CPM_WORKERS => 5,
        PERL_CARTON_MIRROR  => 'https://cpan.metacpan.org/',
        %{$env},
    );
    my ( $status, $output ) =
      _capture( 'sh', $root->child('script/bootstrap-deps')->to_string, @args );
    if ($status) {
        note $output;
    }
    return $status;
}

sub _capture (@command) {
    my $errors = gensym;
    my $pid    = open3( my $input, my $output, $errors, @command );
    close $input or croak "close: $OS_ERROR";
    my $stdout = do { local $INPUT_RECORD_SEPARATOR = undef; <$output> }
      // q{};
    my $stderr = do { local $INPUT_RECORD_SEPARATOR = undef; <$errors> }
      // q{};
    waitpid $pid, 0;
    my $status = $CHILD_ERROR >> $STATUS_SHIFT;
    return ( $status, "$stdout$stderr" );
}

1;
