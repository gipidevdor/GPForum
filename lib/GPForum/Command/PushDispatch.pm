# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Command::PushDispatch;

use Mojo::Base -base, -signatures;
use v5.40;
use Carp         qw(croak);
use Getopt::Long qw(GetOptionsFromArray);
use Mojo::IOLoop;
use Mojo::JSON qw(encode_json);
use Mojo::Promise;
use GPForum::Command::Usage;

our $VERSION = '0.001';
has app => undef;  # optional: help and injected-worker runs need no application
has worker => undef;   # optional: application composition supplies it otherwise
has output => sub { return \*STDOUT; };

sub usage_text { return "Usage: gpforum push [--once|--loop]\n"; }

sub run ( $self, @arguments ) {
    if ( GPForum::Command::Usage->wants_help(@arguments) ) {
        print { $self->output } usage_text() or croak 'cannot print Push usage';
        return 0;
    }
    my $loop = 0;
    return GPForum::Command::Usage->error( undef, usage_text() )
      if !GetOptionsFromArray(
        \@arguments,
        'loop' => \$loop,
        'once' => sub { $loop = 0; }
      ) || @arguments;
    try { $self->_dispatch_loop($loop); }
    catch ($error) { return GPForum::Command::Usage->failure($error); };
    return 0;
}

sub _dispatch_loop ( $self, $loop ) {
    my $running = 1;
    local $SIG{TERM} = sub { $running = 0; };
    local $SIG{INT}  = sub { $running = 0; };
    my $controller = $self->app ? $self->app->build_controller : undef;
    my $worker     = $self->worker // $controller->gp_push_worker;
    while ($running) {
        my ( $result, $failure );
        my $pending = $worker->dispatch_p;
        $pending =
          $pending->then( sub ($value) { $result = $value; return; } );
        $pending->catch( sub ($error) { $failure = $error; return; } )->wait;
        if ( defined $failure ) { croak $failure; }
        if ( !$loop || $result->{selected} ) {
            print { $self->output } encode_json($result), "\n"
              or croak 'cannot print Push result';
        }
        last if !$loop || $result->{disabled} || !$running;

        # Drain full batches without a fixed throughput ceiling. Idle
        # batches yield for one second.
        if ( !( $result->{selected} // 0 ) ) {
            my $pause = Mojo::Promise->new;
            Mojo::IOLoop->timer( 1 => sub { $pause->resolve; } );
            $pause->wait;
        }
    }
    return;
}

1;
