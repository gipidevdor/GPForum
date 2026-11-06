# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::PerlRuntime;

use v5.40;
use Carp qw(croak);
use Config;
use Digest::SHA qw(sha256_hex);
use English     qw(-no_match_vars);
use Cwd         qw(abs_path);
use File::Spec;
use File::Temp qw(tempfile);
use JSON::PP;

our $VERSION = '0.001';

# Core modules only: this boundary runs before the dependency tree is put
# on @INC. Installation prefixes are deliberately absent from the ABI.
## no critic (ValuesAndExpressions::ProhibitConstantPragma) -- core-only bootstrap runs before Const::Fast can be loaded
use constant ABI_KEYS => qw(version archname api_versionstring useithreads
  usemultiplicity use64bitint use64bitall uselongdouble usequadmath
  ivsize nvsize ptrsize byteorder);
use constant MANIFEST => '.gpforum-perl.json';
use constant LEGACY_XS => qw(Cpanel/JSON/XS.pm DBD/Pg.pm Crypt/Argon2.pm
  Email/Address/XS.pm EV.pm);
## use critic

sub identity ($class) {
    return {
        format     => 1,
        abi        => { map { $_ => $Config{$_} // q{} } ABI_KEYS },
        executable => abs_path($EXECUTABLE_NAME) // $EXECUTABLE_NAME,
    };
}

sub cache_key ($class) {
    return sha256_hex(
        JSON::PP->new->canonical->encode( $class->identity->{abi} ) );
}

sub check ( $class, $root ) {
    my $directory = File::Spec->catdir( $root, 'local', 'lib', 'perl5' );
    return 1 if !-d $directory;
    my $file = File::Spec->catfile( $root, 'local', MANIFEST );
    if ( !-f $file ) {

        # Older installations have no manifest. Check the native modules
        # they actually contain, without writing into a read-only release.
        return $class->_legacy_check($directory);
    }
    my $stored;
    try {
        open my $input, '<', $file or croak 'cannot read Perl runtime manifest';
        my $json = do { local $INPUT_RECORD_SEPARATOR = undef; <$input> };
        close $input or croak 'cannot close Perl runtime manifest';
        $stored = JSON::PP->new->decode($json);
    }
    catch ($error) { _incompatible('unreadable runtime manifest'); };
    if (   ref $stored ne 'HASH'
        || ( $stored->{format} // 0 ) != 1
        || ref $stored->{abi} ne 'HASH' )
    {
        _incompatible('invalid runtime manifest');
    }
    my $current = $class->identity->{abi};
    my @changed = grep {
        !exists $stored->{abi}{$_} || $stored->{abi}{$_} ne $current->{$_}
    } ABI_KEYS;
    if (@changed) { _incompatible( join q{, }, @changed ); }
    return 1;
}

sub record_installation ( $class, $root ) {
    my $directory = File::Spec->catdir( $root, 'local' );
    my ( $output, $temporary ) =
      tempfile( '.gpforum-perl-XXXXXX', DIR => $directory, UNLINK => 1 );
    print {$output} JSON::PP->new->canonical->encode( $class->identity ), "\n"
      or croak 'cannot write Perl runtime manifest';
    close $output or croak 'cannot close Perl runtime manifest';
    rename $temporary, File::Spec->catfile( $directory, MANIFEST )
      or croak 'cannot publish Perl runtime manifest';
    return 1;
}

sub _legacy_check ( $class, $directory ) {
    local @INC = @INC;
    require lib;
    lib->import($directory);
    my @local_inc =
      grep { !ref && ( $_ eq $directory || index( $_, "$directory/" ) == 0 ) }
      @INC;
    for my $file (LEGACY_XS) {
        my @found = grep { -f File::Spec->catfile( $_, $file ) } @local_inc;
        next if !@found;
        try { require $file; }
        catch ($error) { _incompatible("native module $file failed to load"); };
    }
    return 1;
}

sub _incompatible ($reason) {
    croak "local/ is incompatible with the selected Perl runtime ($reason). "
      . 'Rebuild with script/bootstrap-deps --postgres --rebuild-local; '
      . 'the previous tree will be preserved.';
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::PerlRuntime - Match a dependency tree to its Perl ABI.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Infrastructure::PerlRuntime->check($checkout);
    GPForum::Infrastructure::PerlRuntime->record_installation($checkout);

=head1 DESCRIPTION

Validates the Perl version, architecture and ABI options used to install
C<local/>. Equal builds can live at different prefixes. A mismatch refuses
startup with rebuild instructions; it never removes or modifies dependencies.
Legacy trees without a manifest are checked by loading their native modules.

=head1 SUBROUTINES/METHODS

=head2 identity

Returns the interpreter's ABI and executable path, with format version 1.

=head2 check

Accepts a checkout root. Reads the manifest without modifying it, or checks
native modules for an older installation. Returns 1, or croaks on a mismatch.

=head2 cache_key

Returns an ABI digest for dependency cache keys, independent of the prefix.

=head2 record_installation

Writes the selected interpreter's manifest atomically after installation.

=head1 DIAGNOSTICS

An incompatible tree names the changed ABI fields and the rebuild command.

=head1 CONFIGURATION AND ENVIRONMENT

Uses C<local/.gpforum-perl.json>. The caller selects the interpreter first.

=head1 DEPENDENCIES

Core Perl modules only, so the dependency tree need not be loaded yet.

=head1 INCOMPATIBILITIES

Compiled dependency trees cannot be reused across different ABI identities.

=head1 BUGS AND LIMITATIONS

Legacy checking probes the main native dependencies; new installs record
the complete ABI identity regardless of which dependencies were installed.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause license.

=cut
