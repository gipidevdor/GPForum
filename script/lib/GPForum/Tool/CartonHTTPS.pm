# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Tool::CartonHTTPS;

use v5.40;

use Carp qw(croak);

our $VERSION = '0.001';
my $installed;

# Carton 1.0.35 adds HTTP CPAN/BackPAN fallbacks even for a custom HTTPS
# mirror. Guard its installer boundary in this launcher only; the host's
# Carton installation and other projects keep their own configuration.
sub import ($class) {
    return if $installed++;
    require Carton::Builder;
    my $install = Carton::Builder->can('run_install')
      or croak 'Carton has no supported installer boundary';
    {
        no warnings 'redefine';    ## no critic (TestingAndDebugging::ProhibitNoWarnings) -- scoped installer transport policy for the host tool
        *Carton::Builder::run_install = sub ( $builder, @arguments ) {
            return $install->( $builder, $class->arguments(@arguments) );
        };
    }
    return;
}

sub arguments ( $class, @arguments ) {
    my @safe;
    while (@arguments) {
        my $argument = shift @arguments;
        if ( $argument eq '--mirror' ) {
            croak 'Carton mirror needs a URL or local path' if !@arguments;
            push @safe, '--mirror', _mirror( shift @arguments );
        }
        elsif ( $argument =~ /\A --mirror= (.*) \z/msx ) {
            push @safe, '--mirror', _mirror($1);
        }
        else {
            push @safe, $argument;
        }
    }

    # This also disables Menlo's HTTP CPAN Meta DB discovery. Last wins over
    # any earlier --no-mirror-only, including for Carton's default mirror.
    push @safe, '--mirror-only';
    return @safe;
}

sub _mirror ($url) {
    return $url if $url =~ m{\A (?: https:// | file:// | / )}msxi;
    my ($host) = $url =~ m{\A http:// ([^/]+) (?:/|\z)}msxi;
    if (
        defined $host
        && (   lc($host) eq 'cpan.metacpan.org'
            || lc($host) eq 'backpan.perl.org' )
      )
    {
        $url =~ s{\A http:}{https:}msxi;
        return $url;
    }
    croak 'Carton mirrors must use HTTPS or a local path';
}

1;
