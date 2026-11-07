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
const my $STAT_SIZE     => 7;
const my $STAT_MTIME    => 9;
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
    $self->_bind_cancellation($context);
    my $weak = $self;
    weaken($weak);
    $class->gate->run_p(
        sub {
            croak 'file reader closed before admission'
              if !$weak || $weak->closed;
            return $weak->_start_child( $path, $expected );
        },
        { cancellation => $self->cancellation }
    )->then(
        sub {
            if ($weak) { $weak->_ended('file reader closed'); }
            return;
        },
        sub ($error) {
            if ($weak) { $weak->_ended($error); }
            return;
        }
    );
    return $self;
}

sub _bind_cancellation ( $self, $context ) {
    my $external = $context ? $context->{cancellation} : undef;
    return if !$external;
    my $weak = $self;
    weaken($weak);
    $self->{external_cancellation} = $external;
    $self->{external_subscription} = $external->subscribe(
        sub {
            if ($weak) { $weak->release_stream; }
            return;
        }
    );
    $self->cancellation->deadline( $external->deadline );
    return;
}

sub _start_child ( $self, $path, $expected ) {
    my $process = GPForum::Infrastructure::Subprocess->new(
        serialize   => \&nfreeze,
        deserialize => \&thaw
    );
    $self->process($process);
    my $weak = $self;
    weaken($weak);
    $process->on(
        spawn => sub ($child) {
            if ( !$weak || $weak->closed ) {
                $child->write_command( _quit_command() );
            }
            return;
        }
    );
    $process->on(
        progress => sub ( $, $message ) {
            if ( $weak && !$weak->closed ) { $weak->_progress($message); }
            return;
        }
    );
    return $process->run_p(
        sub ($child) { return _read_loop( $child, "$path", $expected ); } );
}

sub _progress ( $self, $message ) {
    if ( $message->{metadata} ) {
        return $self->ready->resolve( $message->{metadata} );
    }
    my $current = $self->active;
    $self->active(undef);
    if ($current) { $current->{promise}->resolve( $message->{bytes} ); }
    $self->_pump;
    return;
}

sub _quit_command { return 'Q' . pack 'Q>Q>', 0, 0; }

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
    my $command = pack 'Q>Q>', $current->{offset}, $current->{length};
    $self->process->write_command("R$command");
    return;
}

sub _ended ( $self, $error ) {
    $self->closed(1);
    if ( my $external = delete $self->{external_cancellation} ) {
        $external->unsubscribe( delete $self->{external_subscription} );
    }
    $self->process(undef);
    if ( !$self->ready->AWAIT_IS_READY ) { $self->ready->reject($error); }
    my $active = $self->active;
    $self->active(undef);
    if ($active) { $active->{promise}->reject($error); }
    for my $pending_job ( @{ $self->pending } ) {
        $pending_job->{promise}->reject($error);
    }
    $self->pending( [] );
    return;
}

sub release_stream ($self) {
    return if $self->closed || $self->owner != $PROCESS_ID;
    $self->closed(1);
    $self->cancellation->cancel;
    if ( my $process = $self->process ) {
        if ( $process->{channel} ) {
            $process->write_command( _quit_command() );
        }
    }
    $self->_ended('file reader closed');
    return;
}

sub DESTROY ($self) {
    if ( ${^GLOBAL_PHASE} ne 'DESTRUCT' ) { $self->release_stream; }    ## no critic (Variables::ProhibitPunctuationVars) -- Perl exposes its destruction phase through this special variable
    return;
}

sub _read_loop ( $child, $path, $expected ) {
    open my $file, '<:raw', $path or croak 'file unavailable';          ## no critic (InputOutput::RequireBriefOpen) -- one descriptor lives for this bounded stream and closes on quit or EOF
    my $metadata = _metadata( $file, $path );
    if ($expected) { _verify( $metadata, $expected ); }
    $child->progress( { metadata => $metadata } );
    while ( defined( my $command = _command( $child->{writer} ) ) ) {
        last                                if substr( $command, 0, 1 ) eq 'Q';
        croak 'invalid file reader command' if substr( $command, 0, 1 ) ne 'R';
        $child->progress(
            { bytes => _read_chunk( $file, $path, $metadata, $command ) } );
    }
    CORE::close $file or croak 'cannot close streamed file';
    return 1;
}

sub _metadata ( $file, $path ) {
    my @stat = stat $file;
    croak 'file unavailable' if !@stat || !-f _;
    return {
        path   => $path,
        device => $stat[0],
        inode  => $stat[1],
        size   => $stat[$STAT_SIZE],
        mtime  => $stat[$STAT_MTIME]
    };
}

sub _read_chunk ( $file, $path, $metadata, $command ) {
    my $payload = substr $command, 1;
    my ( $offset, $length ) = unpack 'Q>Q>', $payload;
    croak 'invalid file read range'
      if $length > $MAX_CHUNK
      || $offset > $metadata->{size}
      || $length > $metadata->{size} - $offset;
    _verify( _metadata( $file, $path ), $metadata );
    _verify( _metadata( $path, $path ), $metadata );
    defined( sysseek $file, $offset, 0 ) or croak 'cannot seek streamed file';
    my $bytes = q{};
    while ( length($bytes) < $length ) {
        my $remaining = $length - length $bytes;
        my $part      = q{};
        my $count     = read $file, $part, $remaining;
        croak 'file changed while streaming' if !defined $count || !$count;
        $bytes .= $part;
    }
    return $bytes;
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
        my $remaining = $COMMAND_BYTES - length $command;
        my $part      = q{};
        my $count     = read $socket, $part, $remaining;
        croak 'cannot read file reader command' if !defined $count;
        return undef                            if !$count && !length $command;
        croak 'incomplete file reader command'  if !$count;
        $command .= $part;
    }
    return $command;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::FileReader - Backpressured file reads in one child.

=head1 DESCRIPTION

Two readers per web process may hold a streaming lease. One isolated child
opens each regular file and returns metadata, then reads only the ranges the
parent requests. Commands carry a byte and two unsigned 64-bit big-endian
integers; responses use Subprocess's bounded progress framing and Storable
codec so binary bytes keep their original encoding flags.

At most one 256 KiB read is active per reader. Both the descriptor and named
path must retain their device, inode, size and mtime. An EOF, explicit release,
request cancellation or child failure closes the stream. Subprocess retains
responsibility for nonblocking child reaping, including after a client leaves.

=head1 SUBROUTINES/METHODS

C<start> admits a reader and C<ready> resolves its metadata. C<read_p> queues
a bounded range. C<release_stream> stops queued admission or asks an active
reader to exit; it never waits for the child on the HTTP reactor.

=cut
