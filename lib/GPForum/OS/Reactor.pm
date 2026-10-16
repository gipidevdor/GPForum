# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::OS::Reactor;

use v5.40;

use Carp    qw(croak);
use English qw(-no_match_vars);

our $VERSION = '0.001';

# This bootstrap also runs before Carton dependencies are installed. Loading
# EV here would initialise its default loop before LIBEV_FLAGS takes effect.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma) -- core-only event-loop bootstrap
    EPOLL_BACKEND  => 4,
    KQUEUE_BACKEND => 8,
};

sub expected_backend ( $class, $os = $OSNAME ) {
    return { name => 'epoll',  flags => EPOLL_BACKEND } if $os eq 'linux';
    return { name => 'kqueue', flags => KQUEUE_BACKEND }
      if $os eq 'darwin' || $os eq 'freebsd';

    return undef;
}

sub import ($class) {
    $class->configure;

    return;
}

sub configure ($class) {
    my $backend = $class->expected_backend;
    return undef if !$backend;

    ## no critic (Variables::RequireLocalizedPunctuationVars) -- process-wide bootstrap, inherited by Hypnotoad and its restarts
    $ENV{MOJO_REACTOR} = 'Mojo::Reactor::EV';
    $ENV{LIBEV_FLAGS}  = $backend->{flags};
    ## use critic

    return $backend;
}

sub assert_native ($class) {
    my $backend = $class->configure;
    return undef if !$backend;

    try {
        require EV;
        EV->VERSION('4.37');
    }
    catch ($error) {
        croak 'GPForum requires EV 4.37 or newer for '
          . $backend->{name}
          . '; install the locked dependencies with script/bootstrap-deps --postgres: '
          . $error;
    };

    my $actual = EV::backend();
    if ( !( EV::supported_backends() & $backend->{flags} )
        || $actual != $backend->{flags} )
    {
        croak "GPForum requires $backend->{name} (libev $backend->{flags});"
          . " actual libev backend is $actual. Load GPForum::OS::Reactor"
          . ' before EV or Mojo::IOLoop (perl -Ilib -MGPForum::OS::Reactor).';
    }

    require Mojo::IOLoop;
    my $reactor = ref Mojo::IOLoop->singleton->reactor;
    if ( $reactor ne 'Mojo::Reactor::EV' ) {
        croak "GPForum requires Mojo::Reactor::EV with $backend->{name};"
          . " actual reactor is $reactor. Load GPForum::OS::Reactor"
          . ' before Mojo::IOLoop.';
    }

    return $backend;
}

1;

__END__

=head1 NAME

GPForum::OS::Reactor - Require the supported operating system's event backend.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    use GPForum::OS::Reactor; # before EV or any Mojo event-loop consumer
    GPForum::OS::Reactor->assert_native;

=head1 DESCRIPTION

Linux uses libev epoll; macOS and FreeBSD use libev kqueue. Importing this
core-only module sets C<MOJO_REACTOR> and C<LIBEV_FLAGS> before EV initialises
its default loop. Application startup verifies the actual libev backend and
singleton Mojo reactor, refusing a fallback or an incompatible existing loop.

=head1 SUBROUTINES/METHODS

=head2 expected_backend

Returns the backend name and libev flags for an OS name (the host by default),
or undef for an unsupported OS.

=head2 import

Configures the process before event-loop dependencies load.

=head2 configure

Sets and returns the required backend for this host. Unsupported operating
systems keep Mojolicious's portable detection.

=head2 assert_native

Loads EV and Mojo::IOLoop and refuses startup unless both use the required
native backend. Existing loops are never destroyed or replaced.

=head1 DIAGNOSTICS

Missing EV, an unavailable native backend, or an already initialised loop
using another backend stops application startup with installation or preload
guidance.

=head1 CONFIGURATION AND ENVIRONMENT

On supported systems C<MOJO_REACTOR> is C<Mojo::Reactor::EV> and C<LIBEV_FLAGS>
is 4 (epoll) or 8 (kqueue), overriding inherited reactor preferences.

=head1 DEPENDENCIES

Core L<Carp> and L<English>; L<EV> and L<Mojo::IOLoop> at verification time.

=head1 INCOMPATIBILITIES

A supported host cannot serve GPForum using Mojo::Reactor::Poll or libev
select/poll. An embedding process must preload this module before its loop.

=head1 BUGS AND LIMITATIONS

Only Linux, macOS and FreeBSD have a required native backend.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
