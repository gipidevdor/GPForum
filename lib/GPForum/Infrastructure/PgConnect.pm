# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::PgConnect;

use Mojo::Base -base, -signatures;
use v5.40;
use English    qw(-no_match_vars);
use Carp       qw(croak);
use List::Util qw(any);
use Const::Fast;
use DBI;
use Mojo::IOLoop;
use GPForum::Infrastructure::PgDatabase;
use GPForum::Infrastructure::AsyncWork;
use Socket
  qw(getaddrinfo getnameinfo NI_NUMERICHOST NI_NUMERICSERV SOCK_STREAM AF_INET AF_INET6 inet_pton);
use Mojo::Promise;
use GPForum::X::Unavailable;

our $VERSION = '0.001';
const my $CONNECT_SECONDS  => 5;
const my $POLL_READ        => 1;
const my $POLL_WRITE       => 2;
const my $ALL_FIELDS       => -1;
const my $RESOLVED_LIMIT   => 128;
const my $RESOLVED_SECONDS => 60;

has timeout   => sub { return $CONNECT_SECONDS; };
has connector => sub {
    return sub (@arguments) { return DBI->connect(@arguments); };
};

sub connect_p ( $self, $pg ) {
    return $self->_dsn_p($pg)->then(
        sub ($dsn) {
            my $dbh = $self->connector->(
                $dsn, $pg->username, $pg->password,
                { %{ $pg->options }, pg_async_connect => 1 }
            );
            croak 'asynchronous PostgreSQL connection unavailable' if !$dbh;
            $dbh->{private_mojo_no_reuse} = 1;
            $dbh->{pg_skip_deallocate}    = 1
              ; # Native promise code owns plan retirement; DBI destruction must not send synchronous SQL.
            return $self->_poll_p($dbh)->then(
                sub {
                    return GPForum::Infrastructure::PgDatabase->new(
                        pg  => $pg,
                        dbh => $dbh
                    );
                }
            );
        }
    );
}

# OS hostname resolution may consult hosts, NSS or enterprise DNS and is not
# guaranteed nonblocking. Resolve trusted configured peers in the shared
# Mojolicious executor and pin hostaddr while retaining host for TLS identity.
sub _dsn_p ( $self, $pg ) {
    my $dsn = $pg->dsn;
    return Mojo::Promise->resolve($dsn)
      if $dsn =~ /(?:[:;])hostaddr=/msx || length( $ENV{PGHOSTADDR} // q{} );
    my ($host) = $dsn =~ /(?:[:;])host=([^;]*)/msx;
    $host //= $ENV{PGHOST};
    return Mojo::Promise->resolve($dsn) if defined $host && !_needs_dns($host);
    my $service =
      $dsn =~ /(?:[:;])service=/msx || length( $ENV{PGSERVICE} // q{} );
    return Mojo::Promise->resolve($dsn) if !defined $host && !$service;
    my $key  = _resolution_key( $dsn, $host );
    my $kept = $self->{resolved}{$key};
    return Mojo::Promise->resolve( $kept->{dsn} )
      if $kept && $kept->{expires} > time;
    return $self->{resolving}{$key} if $self->{resolving}{$key};
    my $promise = GPForum::Infrastructure::AsyncWork->shared->run_p(
        sub {
            return !defined $host
              ? _service_dsn($pg)
              : _hostname_dsn( $pg, $host );
        }
    )->then(
        sub ($resolved) {
            $self->_cache_dsn( $key, $resolved );
            return $resolved;
        }
    );
    $self->{resolving}{$key} = $promise;
    return $promise->finally(
        sub { delete $self->{resolving}{$key}; return; } );
}

sub _cache_dsn( $self, $key, $resolved ) {
    if ( keys %{ $self->{resolved} // {} } >= $RESOLVED_LIMIT ) {
        $self->{resolved} = {};
    }
    $self->{resolved}{$key} =
      { dsn => $resolved, expires => time + $RESOLVED_SECONDS };
    return;
}

sub _resolution_key( $dsn, $host ) {
    return join "\0", $PROCESS_ID, $dsn, $host // q{};
}

sub _needs_dns($host) {
    my @hosts = split /,/msx, $host, $ALL_FIELDS;
    return any {
             length
          && !m{\A[/@]}msx
          && !inet_pton( AF_INET,  $_ )
          && !inet_pton( AF_INET6, $_ )
    } @hosts;
}

sub _service_dsn($pg) {
    my $dsn = $pg->dsn;

    # A libpq service can hide both hostname and failover policy.
    # Resolve its selected peer off-reactor using libpq itself, close
    # that probe, then open the owned asynchronous connection there.
    my $probe = DBI->connect( $dsn, $pg->username, $pg->password,
        { %{ $pg->options }, pg_async_connect => 0 } );
    croak 'PostgreSQL service resolution failed' if !$probe;
    open my $socket, '<&', $probe->{pg_socket}
      or croak 'PostgreSQL peer unavailable';
    my $peer = getpeername $socket;
    my ( $error, $address, $port ) =
      getnameinfo( $peer, NI_NUMERICHOST | NI_NUMERICSERV );
    my $selected = $probe->{pg_host};
    close $socket
      or croak 'cannot close PostgreSQL peer descriptor';
    $probe->disconnect;
    return $dsn if !$selected || $selected =~ m{\A/}msx;
    croak 'PostgreSQL service peer unavailable' if $error;
    return "$dsn;host=$selected;hostaddr=$address;port=$port";
}

sub _hostname_dsn( $pg, $host ) {
    my $dsn = $pg->dsn;
    my ($ports) = $dsn =~ /(?:[:;])port=([^;]*)/msx;
    $ports //= $ENV{PGPORT} // '5432';
    my @ports = split /,/msx, $ports, $ALL_FIELDS;
    my ( @hosts, @addresses, @expanded_ports );
    my @configured = split /,/msx, $host, $ALL_FIELDS;
    for my $index ( 0 .. $#configured ) {
        my $name = $configured[$index];
        my $port = @ports == 1 ? $ports[0] : $ports[$index];
        if ( !length($name) || $name =~ m{\A[/@]}msx ) {
            push @hosts,          $name;
            push @addresses,      q{};
            push @expanded_ports, $port;
            next;
        }
        for my $numeric ( @{ _addresses($name) } ) {
            push @hosts,          $name;
            push @addresses,      $numeric;
            push @expanded_ports, $port;
        }
    }
    croak 'PostgreSQL hostname resolution failed' if !@hosts;
    return
        $dsn
      . ';host='
      . join( q{,}, @hosts )
      . ';hostaddr='
      . join( q{,}, @addresses )
      . ';port='
      . ( join q{,}, @expanded_ports );
}

sub _addresses($name) {
    my ( $error, @answers ) =
      getaddrinfo( $name, undef, { socktype => SOCK_STREAM } );
    return [] if $error;
    my %seen;
    my @numeric;
    for my $answer (@answers) {
        my ( $failure, $numeric ) =
          getnameinfo( $answer->{addr}, NI_NUMERICHOST | NI_NUMERICSERV );
        next if $failure || $seen{$numeric}++;
        push @numeric, $numeric;
    }
    return \@numeric;

}

sub _poll_p ( $self, $dbh ) {
    my $promise = Mojo::Promise->new;
    my $reactor = Mojo::IOLoop->singleton->reactor;
    my ( $socket, $timer, $poll );
    my $finished = 0;
    my $clear    = sub {
        if ($socket) {
            $reactor->remove($socket);
            close $socket or croak 'cannot close PostgreSQL poll descriptor';
            undef $socket;
        }
        return;
    };
    my $finish = sub ( $error = undef ) {
        return if $finished++;
        $clear->();
        _remove_timer($timer);
        undef $poll;
        if ( defined $error ) {
            _discard($dbh);
            $promise->reject(
                GPForum::X::Unavailable->new( message => $error ) );
        }
        else { $promise->resolve; }
        return;
    };
    $poll = sub {
        return if $finished;
        my $state;
        try { $state = $dbh->pg_continue_connect; }
        catch ($error) { $finish->('PostgreSQL connection failed'); return; };
        $clear->();
        return $finish->() if $state == 0;
        return $finish->('PostgreSQL connection failed')
          if $state != $POLL_READ && $state != $POLL_WRITE;
        open $socket, '<&', $dbh->{pg_socket}    ## no critic (InputOutput::RequireBriefOpen) -- reactor watcher owns this descriptor until handshake completion
          or return $finish->('PostgreSQL connection descriptor unavailable');
        $reactor->io(
            $socket => sub {
                if ($poll) { $poll->(); }
                return;
            }
        )->watch( $socket, $state == $POLL_READ, $state == $POLL_WRITE );
        return;
    };
    $timer = Mojo::IOLoop->timer(
        $self->timeout => sub {
            $finish->('PostgreSQL connection deadline exceeded');
            return;
        }
    );
    $poll->();
    return $promise;
}

sub _remove_timer($timer) {
    if ( defined $timer ) { Mojo::IOLoop->remove($timer); }
    return;
}

sub _discard($dbh) {
    try { $dbh->disconnect; } catch ($cleanup_error) {

        # Preserve the original connection failure even when cleanup fails.
    };
    return;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::PgConnect - Complete libpq connections through the Mojolicious reactor.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $connector->connect_p($pg)->then(sub ($database) { ... });

=head1 DESCRIPTION

Uses DBD::Pg asynchronous connect and watches the current socket for the exact
read or write readiness requested by libpq. Replaces watchers when libpq changes
the socket and bounds the complete handshake with a deadline.

=head1 SUBROUTINES/METHODS

=head2 connect_p

Returns a promise for an owned Mojo::Pg::Database. Session initialization belongs
to PgStorage and runs after the connection has completed.

=head1 DIAGNOSTICS

Connection failures reject with Unavailable without exposing connection secrets.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the configured Mojo::Pg DSN, credentials and DBI attributes.

=head1 DEPENDENCIES

DBI, DBD::Pg, Mojo::Pg and Mojolicious.

=head1 INCOMPATIBILITIES

Requires DBD::Pg asynchronous connection support.

=head1 BUGS AND LIMITATIONS

Hostname resolution runs in the bounded Mojolicious subprocess executor and pins numeric peers for asynchronous libpq polling. Libpq service definitions require an isolated connection probe before the owned connection.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
