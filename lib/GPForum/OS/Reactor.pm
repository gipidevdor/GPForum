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
    SELECT_BACKEND => 1,
    POLL_BACKEND   => 2,
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

sub assert_native ( $class, %option ) {
    my $strict  = $option{strict} // 1;
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

    require Mojo::IOLoop;
    my $reactor = ref Mojo::IOLoop->singleton->reactor;
    my $actual  = $reactor eq 'Mojo::Reactor::EV' ? EV::backend() : undef;
    return $backend
      if defined $actual
      && $actual == $backend->{flags}
      && EV::supported_backends() & $backend->{flags};

    my $problem = _fallback( $backend, $reactor, $actual );
    croak "GPForum requires $backend->{name}; $problem" if $strict;

    return { %{$backend}, fallback => $problem };
}

# libev reads LIBEV_FLAGS once, when EV loads and creates its default loop,
# and an existing Mojo singleton is never replaced: past that point only the
# environment of the next process can choose. bin/gpforum and
# script/gpforum-carton exec set it for everything they start, so the message
# names them.
sub _fallback ( $backend, $reactor, $actual ) {
    my $found =
      defined $actual
      ? 'libev ' . _backend_name($actual) . " ($actual)"
      : $reactor;

    return
        "this process runs $found, because EV or Mojo::IOLoop loaded"
      . ' before GPForum::OS::Reactor could set'
      . " LIBEV_FLAGS=$backend->{flags} MOJO_REACTOR=Mojo::Reactor::EV."
      . ' Start through bin/gpforum or script/gpforum-carton exec, which set'
      . ' both, or export them in the environment of the runner.';
}

sub _backend_name ($flags) {
    state $name = {
        SELECT_BACKEND() => 'select',
        POLL_BACKEND()   => 'poll',
        EPOLL_BACKEND()  => 'epoll',
        KQUEUE_BACKEND() => 'kqueue',
    };

    return $name->{$flags} // 'backend';
}

1;

__END__

=head1 NAME

GPForum::OS::Reactor - Require the supported operating system's event backend.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    use GPForum::OS::Reactor; # before EV or any Mojo event-loop consumer
    GPForum::OS::Reactor->assert_native;                # refuses a fallback
    my $backend = GPForum::OS::Reactor->assert_native( strict => 0 );
    warn $backend->{fallback} if $backend->{fallback};  # development

=head1 DESCRIPTION

Linux uses libev epoll; macOS and FreeBSD use libev kqueue. Importing this
core-only module sets C<MOJO_REACTOR> and C<LIBEV_FLAGS> before EV initialises
its default loop. Application startup verifies the actual libev backend and
singleton Mojo reactor: production refuses a fallback or an incompatible
existing loop, and development and tests run on it with a warning, since a
runner that loads Test::Mojo or Mojo::IOLoop first has already chosen.

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

Loads EV and Mojo::IOLoop and returns the required backend when the singleton
reactor is Mojo::Reactor::EV on it. Otherwise it croaks, or, given
C<< strict => 0 >>, returns the backend with a C<fallback> explanation and
leaves the loop as it is: an existing loop is never destroyed or replaced.
Missing EV croaks either way.

=head1 DIAGNOSTICS

Missing EV stops startup with installation guidance. A loop that EV or
Mojo::IOLoop initialised before this module, on another backend or reactor,
stops a strict caller with the entry points that set the backend first.

=head1 CONFIGURATION AND ENVIRONMENT

On supported systems C<MOJO_REACTOR> is C<Mojo::Reactor::EV> and C<LIBEV_FLAGS>
is 4 (epoll) or 8 (kqueue), overriding inherited reactor preferences.

=head1 DEPENDENCIES

Core L<Carp> and L<English>; L<EV> and L<Mojo::IOLoop> at verification time.

=head1 INCOMPATIBILITIES

A production host cannot serve GPForum using Mojo::Reactor::Poll or libev
select/poll. An embedding process must preload this module before its loop, or
export the variables it sets.

=head1 BUGS AND LIMITATIONS

Only Linux, macOS and FreeBSD have a required native backend.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
