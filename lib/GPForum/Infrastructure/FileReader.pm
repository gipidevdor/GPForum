# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Infrastructure::FileReader;
use Mojo::Base -base, -signatures;
use v5.40;
use Carp qw(croak);
use Const::Fast;
use English      qw(-no_match_vars);
use Scalar::Util qw(weaken);
use Storable     qw(nfreeze thaw);
use GPForum::Infrastructure::AsyncGate;
use GPForum::Infrastructure::Subprocess;
use GPForum::Infrastructure::Cancellation;
use Mojo::Promise;

our $VERSION = '0.001';
const my $COMMAND_BYTES => 17;
const my $MAX_CHUNK     => 262_144;
const my $MAX_PENDING   => 16;
has process      => undef;    # optional: assigned only after admission
has ready        => sub { return Mojo::Promise->new; };
has pending      => sub { return []; };
has active       => undef;                       # optional: one in-flight chunk
has closed       => 0;
has owner        => sub { return $PROCESS_ID; };
has cancellation => sub { return GPForum::Infrastructure::Cancellation->new; };

sub gate ($class) {
    state $gate = GPForum::Infrastructure::AsyncGate->new( concurrency => 2 );
    return $gate;
}

sub start ( $class, $path, $expected = undef, $context = undef ) {
    my $self = $class->new;
    my $weak = $self;
    weaken($weak);
    my $external = $context ? $context->{cancellation} : undef;
    my $subscription =
        $external
      ? $external->subscribe( sub { $weak->close if $weak; } )
      : undef;
    my $cancel = $self->cancellation;
    $cancel->deadline( $external->deadline ) if $external;
    $class->gate->run_p(
        sub {
            croak 'file reader closed before admission'
              if !$weak || $weak->closed;
            my $process = GPForum::Infrastructure::Subprocess->new(
                serialize   => \&nfreeze,
                deserialize => \&thaw
            );
            $weak->process($process);
            $process->on(
                spawn => sub ($child) {
                    $child->send( 'Q' . pack( 'Q>Q>', 0, 0 ) )
                      if !$weak || $weak->closed;
                    return;
                }
            );
            $process->on(
                progress => sub ( $, $message ) {
                    return if !$weak || $weak->closed;
                    if ( $message->{metadata} ) {
                        $weak->ready->resolve( $message->{metadata} );
                    }
                    else {
                        my $current = $weak->active;
                        $weak->active(undef);
                        $current->{promise}->resolve( $message->{bytes} )
                          if $current;
                        $weak->_pump;
                    }
                    return;
                }
            );
            return $process->run_p(
                sub ($child) {
                    return _read_loop( $child, "$path", $expected );
                }
            );
        },
        { cancellation => $cancel }
    )->then(
        sub {
            $weak->_ended('file reader closed')   if $weak;
            $external->unsubscribe($subscription) if $external;
            return;
        },
        sub ($error) {
            $weak->_ended($error)                 if $weak;
            $external->unsubscribe($subscription) if $external;
            return;
        }
    );
    return $self;
}

sub read_p ( $self, $offset, $length ) {
    return Mojo::Promise->reject('file reader closed') if $self->closed;
    croak 'invalid file read range'
      if $offset < 0 || $length < 0 || $length > $MAX_CHUNK;
    return $self->ready->then(
        sub {
            croak 'file reader closed' if $self->closed;
            croak 'file reader queue is full'
              if @{ $self->pending } >= $MAX_PENDING;
            my $promise = Mojo::Promise->new;
            push @{ $self->pending },
              { offset => $offset, length => $length, promise => $promise };
            $self->_pump;
            return $promise;
        }
    );
}

sub _pump ($self) {
    return if $self->closed || $self->active || !@{ $self->pending };
    my $current = shift @{ $self->pending };
    $self->active($current);
    $self->process->send(
        'R' . pack( 'Q>Q>', $current->{offset}, $current->{length} ) );
    return;
}

sub _ended ( $self, $error ) {
    $self->closed(1);
    $self->process(undef);
    $self->ready->reject($error) if !$self->ready->AWAIT_IS_READY;
    my $active = $self->active;
    $self->active(undef);
    $active->{promise}->reject($error) if $active;
    $_->{promise}->reject($error) for @{ $self->pending };
    $self->pending( [] );
    return;
}

sub close ($self) {
    return if $self->closed || $self->owner != $PROCESS_ID;
    $self->closed(1);
    $self->cancellation->cancel;
    if ( my $process = $self->process ) {
        $process->send( 'Q' . pack( 'Q>Q>', 0, 0 ) ) if $process->{channel};
    }
    $self->_ended('file reader closed');
    return;
}

sub DESTROY ($self) { $self->close if ${^GLOBAL_PHASE} ne 'DESTRUCT'; }

sub _read_loop ( $child, $path, $expected ) {
    open my $file, '<:raw', $path or croak 'file unavailable';
    my @stat = stat $file;
    croak 'file unavailable' if !@stat || !-f $file;
    my $metadata = {
        path   => $path,
        device => $stat[0],
        inode  => $stat[1],
        size   => $stat[7],
        mtime  => $stat[9]
    };
    _verify( $metadata, $expected ) if $expected;
    $child->progress( { metadata => $metadata } );
    while ( defined( my $command = _command( $child->{writer} ) ) ) {
        last                                if substr( $command, 0, 1 ) eq 'Q';
        croak 'invalid file reader command' if substr( $command, 0, 1 ) ne 'R';
        my ( $offset, $length ) = unpack( 'Q>Q>', substr( $command, 1 ) );
        croak 'invalid file read range'
          if $length > $MAX_CHUNK
          || $offset > $metadata->{size}
          || $length > $metadata->{size} - $offset;
        my @current = stat $file;
        my @named   = stat $path;
        _verify(
            {
                device => $current[0],
                inode  => $current[1],
                size   => $current[7],
                mtime  => $current[9]
            },
            $metadata
        );
        _verify(
            {
                device => $named[0],
                inode  => $named[1],
                size   => $named[7],
                mtime  => $named[9]
            },
            $metadata
        );
        defined( sysseek $file, $offset, 0 )
          or croak 'cannot seek streamed file';
        my $bytes = q{};

        while ( length($bytes) < $length ) {
            my $count = read( $file, my $part, $length - length($bytes) );
            croak 'file changed while streaming' if !defined $count || !$count;
            $bytes .= $part;
        }
        $child->progress( { bytes => $bytes } );
    }
    CORE::close $file or croak 'cannot close streamed file';
    return 1;
}

sub _verify ( $actual, $expected ) {
    for my $key (qw(device inode size mtime)) {
        croak 'file changed while streaming'
          if !defined $actual->{$key}
          || $actual->{$key} != $expected->{$key};
    }
    return;
}

sub _command ($socket) {
    my $command = q{};
    while ( length($command) < $COMMAND_BYTES ) {
        my $count =
          read( $socket, my $part, $COMMAND_BYTES - length($command) );
        croak 'cannot read file reader command' if !defined $count;
        return undef                            if !$count && !length $command;
        croak 'incomplete file reader command'  if !$count;
        $command .= $part;
    }
    return $command;
}

1;
