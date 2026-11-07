# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::ConnectionAdmission;

use Mojo::Base -strict, -signatures;
use v5.40;
use Const::Fast;
use English      qw(-no_match_vars);
use List::Util   qw(min);
use Scalar::Util qw(refaddr weaken);

our $VERSION = '0.001';
const my $SINGLE_ACCEPT_CLIENTS => 250;
const my $CLIENTS_PER_ACCEPT    => 64;
const my $MAX_ACCEPT_BATCH      => 64;
const my $BURST_CLIENTS         => 4096;
const my $BURST_ACCEPT_BATCH    => 512;
const my $FAIR_ACCEPT_PAUSE     => 0.05;

sub batch_size ( $, $clients ) {
    return 1 if $clients <= $SINGLE_ACCEPT_CLIENTS;

    # Large cold bursts must enter before established keep-alive clients
    # consume whole loop turns. Keep ordinary deployment budgets unchanged.
    return $BURST_ACCEPT_BATCH if $clients > $BURST_CLIENTS;
    return min( $MAX_ACCEPT_BATCH,
        int( ( $clients + $CLIENTS_PER_ACCEPT - 1 ) / $CLIENTS_PER_ACCEPT ) );
}

sub single_accept ( $class, $location, $clients ) {
    return $location =~ m{\Ahttps:}msx
      || $class->batch_size($clients) == 1 ? 1 : 0;
}

sub register ( $class, $application, $config ) {
    my $batch = $class->batch_size( $config->runtime_clients );
    return if $batch == 1;
    my @locations = $config->runtime_listen_locations->@*;
    my @indices   = grep { $locations[$_] !~ m{\Ahttps:|[?&]single_accept=}msx }
      0 .. $#locations;
    return if !@indices;
    $application->hook(
        before_server_start => sub ( $server, $ ) {
            return if !$server->isa('Mojo::Server::Daemon');
            my $manager = $PROCESS_ID;
            $server->ioloop->next_tick(
                sub {
                    return
                      if $server->isa('Mojo::Server::Prefork')
                      && $PROCESS_ID == $manager;
                    $class->install( $server, $batch, \@indices );
                    return;
                }
            );
            return;
        }
    );
    return;
}

sub install ( $class, $server, $batch, $indices ) {
    for my $index ( $indices->@* ) {
        $class->_attach( $server, $index, $batch );
    }
    return;
}

sub _attach ( $, $server, $index, $batch ) {
    my $loop = $server->ioloop;
    my $id   = $server->acceptors->[$index];
    return if !defined $id;
    my $acceptor = $loop->acceptor($id) or return;
    my $state    = {
        loop      => $loop,
        server    => $server,
        id        => $id,
        index     => $index,
        batch     => $batch,
        allowance => $batch,
        accepted  => 0,
        scheduled => 0,
        paused    => 0,
        handles   => {},
        share     => _cohort_size( $server, $batch ),
    };
    weaken( $state->{server} );
    weaken( $state->{loop} );
    $acceptor->on(
        accept => sub ( $listener, $handle ) {
            _accepted( $state, $listener, $handle );
            return;
        }
    );
    return;
}

sub _cohort_size ( $server, $batch ) {
    return 0
      if $batch != $BURST_ACCEPT_BATCH
      || !$server->isa('Mojo::Server::Prefork');
    my $clients = $server->ioloop->max_connections;
    return int( ( $clients + $server->workers - 1 ) / $server->workers );
}

sub _accepted ( $state, $listener, $handle ) {
    _record_socket( $state, $handle );
    my $loop = $state->{loop};
    if ( !$state->{scheduled}++ ) {
        $loop->next_tick( sub { _next_turn( $state, $listener ); return; } );
    }
    return if ++$state->{accepted} < $state->{allowance};
    $state->{paused} = 1;
    $listener->stop;
    $loop->remove( $state->{id} );
    return if !$state->{share} || $state->{active} < $state->{checkpoint};

    # Reset this turn normally; only admission waits for quieter workers.
    $state->{paused} = 0;
    $loop->timer(
        $FAIR_ACCEPT_PAUSE => sub {
            _resume( $state, $listener );
            return;
        }
    );
    return;
}

sub _record_socket ( $state, $handle ) {
    return if !$state->{share};
    if ( !$state->{accepted} ) {
        $state->{active} = _live_handles( $state->{handles} );
        my $share = $state->{share};
        $state->{checkpoint} =
          $share * ( int( $state->{active} / $share ) + 1 );
        $state->{allowance} =
          min( $state->{batch}, $state->{checkpoint} - $state->{active} );
    }
    my $key = refaddr($handle);
    $state->{handles}{$key} = $handle;
    weaken( $state->{handles}{$key} );
    $state->{active}++;
    return;
}

# Raw clients that close before sending HTTP never create a transaction.
# Weak socket references include their closure without retaining streams.
sub _live_handles ($handles) {
    for my $key ( keys $handles->%* ) {
        my $handle = $handles->{$key};
        if ( !defined $handle || !defined fileno $handle ) {
            delete $handles->{$key};
        }
    }
    return scalar keys $handles->%*;
}

sub _next_turn ( $state, $listener ) {
    $state->@{qw(accepted scheduled)} = ( 0, 0 );
    return if !$state->{paused};
    $state->{paused} = 0;
    _resume( $state, $listener );
    return;
}

sub _resume ( $state, $listener ) {
    return if !$state->{server};

    # IOLoop's native connection limit and graceful-stop state govern resume.
    $state->{id} = $state->{loop}->acceptor($listener);
    $state->{server}->acceptors->[ $state->{index} ] = $state->{id};
    return;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::ConnectionAdmission - Bound native listener admission per event-loop turn.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Infrastructure::ConnectionAdmission->register($app, $config);

=head1 DESCRIPTION

At ordinary connection limits the server accepts one connection per turn.
Larger limits use bounded batches, up to 64 accepts per turn below 4097 clients
and 512 above that budget, avoiding a long admission
queue while established keep-alive clients keep the loop busy. All accept,
pause and resume operations use Mojolicious APIs. Re-registering the listener
through IOLoop preserves its connection limit and graceful shutdown.
Explicit C<single_accept> settings and TLS listeners retain native behavior.

=head1 SUBROUTINES/METHODS

=head2 batch_size

Returns the accept batch for a per-worker connection limit.

=head2 single_accept

Returns the native listener setting before cooperative admission is installed.

=head2 register

Schedules installation after listener startup, in each serving worker.

=head2 install

Attaches bounded admission to the supplied server listener indices.

=head1 DIAGNOSTICS

Native listener and event-loop errors propagate to Mojolicious.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the configured per-worker client budget and listener locations.

=head1 DEPENDENCIES

Mojolicious, L<Const::Fast>, L<List::Util> and L<Scalar::Util>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

TLS handshakes and explicitly configured native admission are not adapted.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause license.

=cut
