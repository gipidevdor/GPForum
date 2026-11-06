# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Cwd        qw(abs_path);
use English    qw(-no_match_vars);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use JSON::PP;
use Symbol qw(gensym);
use Test::More;
use lib 'lib';
use GPForum::Infrastructure::PerlRuntime;

our $VERSION = '0.001';
my $runtime = 'GPForum::Infrastructure::PerlRuntime';
my $perl    = abs_path($EXECUTABLE_NAME);
my $root    = tempdir( CLEANUP => 1 );
my $local   = File::Spec->catdir( $root, 'local', 'lib', 'perl5' );
make_path( $local, "$root/script", "$root/lib/GPForum/Infrastructure" );
for my $name (qw(gpforum-system-perl gpforum-carton)) {
    copy( "script/$name", "$root/script/$name" ) or die $OS_ERROR;
    chmod oct('755'), "$root/script/$name" or die $OS_ERROR;
}
copy(
    'lib/GPForum/Infrastructure/PerlRuntime.pm',
    "$root/lib/GPForum/Infrastructure/PerlRuntime.pm"
) or die $OS_ERROR;
my $selector = "$root/script/gpforum-system-perl";

for my $layout (
    'perlbrew/perls/pinned/bin',      '.plenv/versions/pinned/bin',
    '.asdf/installs/perl/pinned/bin', 'custom prefix/bin'
  )
{
    my $directory = "$root/$layout";
    make_path($directory);
    symlink $perl, "$directory/perl" or die $OS_ERROR;
    my $selected =
      _run( { GPFORUM_PERL => "$directory/perl" }, $selector, '--require' );
    is( $selected->{status}, 0,         "accepts $layout" );
    is( $selected->{output}, "$perl\n", 'pins the actual executable' );
}

make_path("$root/shims");
_write( "$root/shims/perl", <<'SHIM' );
#!/bin/sh
printf '%s\n' "$*" >> "$GPFORUM_TEST_PROBES"
exec "$GPFORUM_TEST_PERL" "$@"
SHIM
chmod oct('755'), "$root/shims/perl" or die $OS_ERROR;
my %shim_environment = (
    PATH                => "$root/shims:$ENV{PATH}",
    GPFORUM_TEST_PERL   => $perl,
    GPFORUM_TEST_PROBES => "$root/probes",
);
my $selected = _run( \%shim_environment, $selector, '--require' );
is( $selected->{status}, 0, 'accepts the active version-manager shim' );
is( $selected->{output}, "$perl\n",
    'resolves its actual Perl for subprocesses' );
ok( -s "$root/probes", 'PATH is consulted before distribution fallbacks' );
is(
    _run( { %shim_environment, GPFORUM_PERL => 'perl' }, $selector )->{status},
    0,
    'an explicit command name is resolved on PATH'
);

_write( "$root/old-perl", <<'OLD' );
#!/bin/sh
case "$*" in
    '-e print $^X') printf '%s' "$0" ;;
    '-e printf "%vd", $^V') printf '5.38.0' ;;
    *) exit 1 ;;
esac
OLD
chmod oct('755'), "$root/old-perl" or die $OS_ERROR;
my $old = _run( { GPFORUM_PERL => "$root/old-perl" }, $selector, '--require' );
is( $old->{status}, 1, 'an explicitly selected old Perl is refused' );
like(
    $old->{errors},
    qr/older[ ]than[ ]the[ ]5[.]40/msx,
    'the version floor remains explicit'
);
my $missing = _run( { GPFORUM_PERL => "$root/missing" }, $selector );
is( $missing->{status}, 1, 'an invalid override never silently falls back' );

ok( $runtime->check($root), 'an empty legacy dependency tree is accepted' );
$runtime->record_installation($root);
my $manifest = "$root/local/.gpforum-perl.json";
my $saved    = _read($manifest);
ok( $runtime->check($root), 'the installing runtime accepts its tree' );
like( $runtime->cache_key, qr/\A[[:xdigit:]]{64}\z/msx,
    'dependency cache identity includes the ABI' );
my $identity = JSON::PP->new->decode($saved);
$identity->{executable} = '/a/different/prefix/bin/perl';
_write( $manifest, JSON::PP->new->encode($identity) );
ok( $runtime->check($root),
    'a relocated equivalent runtime remains compatible' );

for my $field (qw(version archname useithreads usemultiplicity nvsize)) {
    my $foreign = JSON::PP->new->decode($saved);
    $foreign->{abi}{$field} = 'different';
    _write( $manifest, JSON::PP->new->encode($foreign) );
    my $error;
    try { $runtime->check($root); }
    catch ($caught) { $error = "$caught"; };
    like( $error, qr/incompatible.*\Q$field\E/msx, "refuses a changed $field" );
    like( $error, qr/--rebuild-local/msx,
        'explains the non-destructive rebuild' );
    my $wrapped = _run( { GPFORUM_PERL => $perl },
        "$root/script/gpforum-carton", 'exec', 'perl', '-e',
        'print "executed"' );
    isnt( $wrapped->{status}, 0,
        'wrapper refuses the mismatched dependency tree' );
    is( $wrapped->{output}, q{}, 'before launching the application' );
    is(
        _read($manifest),
        JSON::PP->new->encode($foreign),
        'refusal preserves the tree'
    );
}
_write( $manifest, '{broken' );
my $invalid = _run( { GPFORUM_PERL => $perl },
    "$root/script/gpforum-carton", 'exec', 'perl', '-e', '1' );
like(
    $invalid->{errors},
    qr/unreadable[ ]runtime[ ]manifest/msx,
    'corrupt metadata fails with rebuild instructions'
);
unlink $manifest or die $OS_ERROR;
make_path("$local/Cpanel/JSON");
_write( "$local/Cpanel/JSON/XS.pm", "die qq{bad native ABI};\n" );
my $legacy = _run( { GPFORUM_PERL => $perl },
    "$root/script/gpforum-carton", 'exec', 'perl', '-e', '1' );
like(
    $legacy->{errors},
    qr/native[ ]module.*failed[ ]to[ ]load/msx,
    'older unrecorded native trees are checked too'
);

done_testing();

sub _write ( $file, $contents ) {
    open my $output, '>', $file or die $OS_ERROR;
    print {$output} $contents or die $OS_ERROR;
    close $output             or die $OS_ERROR;
    return;
}

sub _read ($file) {
    open my $input, '<', $file or die $OS_ERROR;
    my $contents = do { local $INPUT_RECORD_SEPARATOR = undef; <$input> };
    close $input or die $OS_ERROR;
    return $contents;
}

sub _run ( $environment, @command ) {
    local %ENV = ( %ENV, %{$environment} );
    delete @ENV{qw(PERL5LIB PERL5OPT)};
    delete $ENV{GPFORUM_PERL} if !exists $environment->{GPFORUM_PERL};
    delete $ENV{GPFORUM_CARTON};
    my $errors = gensym;
    my $pid    = open3( my $input, my $output, $errors, @command );
    close $input or die $OS_ERROR;
    my $stdout = do { local $INPUT_RECORD_SEPARATOR = undef; <$output> };
    my $stderr = do { local $INPUT_RECORD_SEPARATOR = undef; <$errors> };
    waitpid $pid, 0;
    return {
        output => $stdout // q{},
        errors => $stderr // q{},
        status => $CHILD_ERROR >> 8
    };
}
1;
