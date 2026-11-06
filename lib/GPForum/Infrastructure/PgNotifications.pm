# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::PgNotifications;

use Const::Fast;
use Carp qw(croak);
use Mojo::Base -base, -signatures;
use v5.40;
use English      qw(-no_match_vars);
use Scalar::Util qw(refaddr weaken);
use Mojo::IOLoop;
use Mojo::Promise;
use GPForum::Infrastructure::AsyncGate;

use GPForum::Infrastructure::Storage;

our $VERSION = '0.001';

# Per channel. A consumer that stops taking (a cache nobody reads) would
# otherwise grow its queue for as long as the process lives.
const my $DEFAULT_MAX_QUEUED => 1_000;

has asynchronous => 0;
has max_queued   => $DEFAULT_MAX_QUEUED;

# Without a schema there is no connection to listen on, and every listen
# and take reports the database unavailable, as a lost one does.
has schema => undef;    # optional: then always unavailable

# The connection the last take saw. A LISTEN lives on one backend: when the
# connection changes, every channel has to be listened for again. It is
# known by its backend PID and by the handle itself, held weakly. A PID can
# come back -- a PostgreSQL restarted in a fresh container hands out the
# same small PIDs again -- but the storage replaces the handle whenever it
# reconnects, and a handle that was freed or replaced is a new connection
# whatever its PID. All three are undef until the first take sees one.
has backend_pid => undef;               # optional: state, set by the first take
has channels    => sub { return {}; };
has connection  => undef;               # optional: state, set by the first take
has connections_seen => 0;
has handle           => undef;          # optional: state, set by the first take
has sync_needed      => 1;
has stats            => sub {
    return {
        dropped         => 0,
        gaps            => 0,
        listen_failures => 0,
        overflowed      => 0,
        received        => 0,
        relistens       => 0,
        unavailable     => 0,
    };
};

sub listen_to ( $self, $channel ) {
    if ( $self->_native ) {
        $self->channels->{$channel} //=
          { connection => undef, failed => 0, gap => 0, queue => [] };
        $self->ensure_p->catch( sub { return; } );
        return $self->listening($channel);
    }
    my $entry = $self->channels->{$channel};
    if ( !$entry ) {
        $entry = { connection => undef, failed => 0, gap => 0, queue => [] };
        $self->channels->{$channel} = $entry;
        $self->sync_needed(1);
    }

    my $dbh = $self->_dbh;
    if ($dbh) {
        $self->_sync($dbh);
    }

    # With no handle, or a transaction open, no LISTEN was issued, and the
    # consumer goes on as if it had been: the cache bus fills L1. What is
    # raised until a take issues it reaches nobody here, so that take
    # reports a gap, as for a LISTEN that failed.
    my $listening = $self->listening($channel);
    if ( !$listening ) {
        $entry->{failed} = 1;
    }

    return $listening;
}

sub unlisten ( $self, $channel ) {
    if ( $self->_native ) {
        delete $self->channels->{$channel};
        $self->ensure_p->then(
            sub {
                return if !$self->{async_db};
                return $self->{async_gate}->run_p(
                    sub {
                        return $self->{async_db}->query_p( 'UNLISTEN '
                              . $self->{async_db}
                              ->dbh->quote_identifier($channel) );
                    }
                );
            }
        )->catch( sub { return; } );
        return 1;
    }
    my $entry = delete $self->channels->{$channel};
    if ( !$entry || !defined $entry->{connection} ) {
        return 1;
    }

    # A LISTEN dies with its backend, so on another one there is nothing
    # left to undo.
    my $dbh = $self->_dbh;
    if (   !$dbh
        || !$dbh->{AutoCommit}
        || $self->_identify($dbh) ne $entry->{connection} )
    {
        return 1;
    }

    my $unlistened = 0;
    try {
        $dbh->do( 'UNLISTEN ' . $dbh->quote_identifier($channel) );
        $unlistened = 1;
    }
    catch ($error) {
        $unlistened = 0;
    };

    return $unlistened;
}

sub registered ( $self, $channel ) {
    return exists $self->channels->{$channel} ? 1 : 0;
}

sub listening ( $self, $channel ) {
    my $entry = $self->channels->{$channel};
    if ( !$entry || !defined $entry->{connection} ) {
        return 0;
    }

    return $entry->{connection} eq ( $self->connection // q{} ) ? 1 : 0;
}

# What arrived for one channel since its last take. Every take reads the
# whole libpq buffer and files each notification under its own channel, so
# one consumer draining the handle no longer swallows another's messages.
sub take ( $self, $channel ) {
    return $self->_take_native($channel) if $self->_native;
    my $entry = $self->channels->{$channel};
    if ( !$entry ) {
        return { available => 0, gap => 0, notifications => [] };
    }

    # On the handle as it stands, without a ping: a take runs on every cache
    # read, and asking PostgreSQL first whether the connection was alive cost
    # each of them a round trip. A connection the server closed is found out
    # by the read that fails on it, and replaced through the storage's own
    # ping and reconnect -- the one take where the ping is worth its round
    # trip; the new backend has no LISTEN yet, which _sync issues, reporting
    # the gap.
    my $taken = GPForum::Infrastructure::Storage->with_handle(
        $self->schema,
        sub ( $, $handle ) {
            $self->_sync($handle);
            return { handle => $handle, read => $self->_pump($handle) };
        }
    );
    my $read = $taken && $taken->{read};
    if ( $taken && !$read ) {
        $self->_read_unavailable;
        my $dbh = $self->_dbh;
        if ($dbh) {
            $self->_sync($dbh);
            $read = $self->_pump($dbh);
        }
    }
    if ( !$read ) {
        $self->stats->{unavailable} += 1;
        $self->_read_unavailable;
    }

    my @notifications = splice @{ $entry->{queue} };
    my $gap           = $entry->{gap};
    $entry->{gap} = 0;

    return {
        available     => $read ? 1 : 0,
        gap           => $gap,
        notifications => \@notifications,
    };
}

sub listen_to_p ( $self, $channel ) {
    return Mojo::Promise->resolve( $self->listen_to($channel) )
      if !$self->_native;
    $self->channels->{$channel} //=
      { connection => undef, failed => 0, gap => 0, queue => [] };
    return $self->ensure_p->then( sub { return $self->listening($channel); } );
}

sub take_p ( $self, $channel ) {
    return Mojo::Promise->resolve( $self->take($channel) ) if !$self->_native;
    return $self->ensure_p->then(
        sub { return $self->_take_native($channel); } );
}

sub _native ($self) {
    return
         $self->asynchronous
      && !$GPForum::Infrastructure::AsyncWork::IS_CHILD
      && $self->schema
      && $self->schema->isa('GPForum::Schema');
}

# One dedicated, idle LISTEN connection is shared by all consumers. Neither
# cache lookups nor the read watcher check a pooled connection out or ping it.
sub ensure_p ($self) {
    return Mojo::Promise->resolve(1) if !$self->_native;
    if ( ( $self->{async_owner} // 0 ) != $PROCESS_ID ) {
        if ( my $old = delete $self->{async_db} ) {
            $old->dbh->{InactiveDestroy} = 1;
        }
        delete $self->{async_pending};
        if ( my $socket = delete $self->{async_watch} ) {
            Mojo::IOLoop->singleton->reactor->remove($socket);
            close $socket or croak 'cannot close notification descriptor';
        }
        $self->{async_owner} = $PROCESS_ID;
        $self->{async_gate} =
          GPForum::Infrastructure::AsyncGate->new( concurrency => 1 );
        $self->_read_unavailable;
    }
    return $self->{async_pending} if $self->{async_pending};
    my $operation = $self->{async_gate}->run_p(
        sub {
            my $connected =
              $self->{async_db}
              ? Mojo::Promise->resolve( $self->{async_db} )
              : $self->schema->storage->database_p;
            return $connected->then(
                sub ($db) {
                    $self->{async_db} = $db;
                    $self->schema->storage->notifications($self);
                    my $identity = $self->_identify( $db->dbh );
                    my $chain    = Mojo::Promise->resolve;
                    for my $channel ( sort keys %{ $self->channels } ) {
                        next if $self->listening($channel);
                        $chain = $chain->then(
                            sub {
                                return $db->query_p( 'LISTEN '
                                      . $db->dbh->quote_identifier($channel) )
                                  ->then(
                                    sub {
                                        my $entry = $self->channels->{$channel};
                                        return if !$entry;
                                        if ( $entry->{failed} ) {
                                            $entry->{gap} = 1;
                                            $self->stats->{relistens}++;
                                        }
                                        $entry->{connection} = $identity;
                                        $entry->{failed}     = 0;
                                        return;
                                    }
                                  );
                            }
                        );
                    }
                    return $chain->then(
                        sub { $self->_watch_native; return 1; } );
                }
            );
        }
    )->catch( sub ($error) { $self->_drop_native; return 0; } );
    $self->{async_pending} = $operation;
    return $operation->finally(
        sub { delete $self->{async_pending}; return; } );
}

sub _watch_native ($self) {
    return if $self->{async_watch};
    my $fd = $self->{async_db}->dbh->{pg_socket};
    open my $socket, '+<&', $fd    ## no critic (InputOutput::RequireBriefOpen) -- the reactor owns this long-lived LISTEN descriptor
      or croak "Cannot watch PostgreSQL notifications: $OS_ERROR";
    $self->{async_watch} = $socket;
    my $broker = $self;
    weaken($broker);
    my $reactor = Mojo::IOLoop->singleton->reactor;
    $reactor->io(
        $socket => sub {
            return if !$broker;
            if ( !$broker->_pump( $broker->{async_db}->dbh ) ) {
                $broker->_drop_native;
            }
        }
    )->watch( $socket, 1, 0 );
    return;
}

sub retire_connections ($self) {
    if ( ( $self->{async_owner} // 0 ) == $PROCESS_ID ) { $self->_drop_native; }
    return;
}

sub _drop_native ($self) {
    if ( my $socket = delete $self->{async_watch} ) {
        Mojo::IOLoop->singleton->reactor->remove($socket);
        close $socket or croak 'cannot close notification descriptor';
    }
    if ( my $db = delete $self->{async_db} ) {
        try { $db->dbh->disconnect; } catch ($error) {
        };
    }
    $self->_read_unavailable;
    return;
}

sub _take_native ( $self, $channel ) {
    if ( ( $self->{async_owner} // 0 ) != $PROCESS_ID ) {
        $self->_read_unavailable;
        $self->ensure_p->catch( sub { return; } );
        return { available => 0, gap => 1, notifications => [] };
    }
    my $entry = $self->channels->{$channel};
    return { available => 0, gap => 0, notifications => [] } if !$entry;
    my $ready = $self->{async_db} && $self->listening($channel);
    if ( $ready && !$self->_pump( $self->{async_db}->dbh ) ) {
        $self->_drop_native;
        $ready = 0;
    }
    if ( !$ready ) {
        $self->_read_unavailable;
        $self->ensure_p->catch( sub { return; } );
    }
    my @notifications = splice @{ $entry->{queue} };
    my $gap           = $entry->{gap};
    $entry->{gap} = 0;
    return {
        available     => $ready ? 1 : 0,
        gap           => $gap,
        notifications => \@notifications
    };
}

sub snapshot ($self) {
    my %channels;
    for my $channel ( keys %{ $self->channels } ) {
        $channels{$channel} = {
            listening => $self->listening($channel),
            queued    => scalar @{ $self->channels->{$channel}{queue} },
        };
    }

    return {
        %{ $self->stats },
        backend_pid => $self->backend_pid,
        channels    => \%channels,
    };
}

# Outside a transaction only: PostgreSQL delivers nothing inside one, and a
# LISTEN issued inside one is undone by its rollback.
sub _sync ( $self, $dbh ) {
    $self->_bind_native_notifications;
    if ( !$dbh->{AutoCommit} ) {
        return;
    }

    my $connection = $self->_identify($dbh);
    return if !$self->sync_needed;

    my $pending = 0;
    for my $channel ( sort keys %{ $self->channels } ) {
        my $entry = $self->channels->{$channel};
        next
          if defined $entry->{connection}
          && $entry->{connection} eq $connection;

        $self->_listen_on( $dbh, $channel );
        if ( !$self->listening($channel) ) {
            $pending = 1;
        }
    }
    $self->sync_needed($pending);

    return;
}

# Mojo::Pg delivers notifications that arrive during a query through its
# database event. Feed that event into the same bounded channel queues as
# pg_notifies, so query completion cannot consume the invalidation stream.
sub _bind_native_notifications ($self) {
    my $storage = GPForum::Infrastructure::Storage->storage_of( $self->schema );
    return if !$storage || !$storage->isa('GPForum::Infrastructure::PgStorage');
    my $database = $storage->database;
    return if $self->{native_database} && $self->{native_database} == $database;
    $self->{native_database} = $database;
    weaken( $self->{native_database} );
    my $broker = $self;
    weaken($broker);
    $database->on(
        notification => sub ( $, @notification ) {
            if ($broker) { $broker->_route( \@notification ); }
        }
    );
    return;
}

# The token of the connection $dbh is, made anew when its PID or the handle
# changed.
sub _identify ( $self, $dbh ) {
    my $pid   = _pid_of($dbh);
    my $known = $self->handle;
    if (   defined $self->connection
        && defined $known
        && refaddr($known) == refaddr($dbh)
        && $pid eq $self->backend_pid )
    {
        return $self->connection;
    }

    $self->connections_seen( $self->connections_seen + 1 );
    $self->backend_pid($pid);
    $self->connection( join q{/}, $pid, $self->connections_seen );
    $self->handle($dbh);
    weaken( $self->{handle} );
    $self->sync_needed(1);

    return $self->connection;
}

# An unreadable socket cannot vouch for any registered channel. Retire all
# registrations, including on a handle that storage might return again, and
# keep each consumer's gap until that consumer takes it.
sub _read_unavailable ($self) {
    for my $entry ( values %{ $self->channels } ) {
        $entry->{connection} = undef;
        $entry->{failed}     = 1;
        $entry->{gap}        = 1;
        $self->stats->{gaps} += 1;
    }
    $self->sync_needed(1);
    return;
}

sub _listen_on ( $self, $dbh, $channel ) {
    my $entry = $self->channels->{$channel};

    # Until the LISTEN is in effect, a NOTIFY on the channel reaches nobody
    # here. One listened for on a connection that is gone, or one whose
    # LISTEN failed, has missed an unknown number of messages, and so has
    # one whose LISTEN fails now: the consumer is told.
    my $resumed  = defined $entry->{connection} || $entry->{failed};
    my $listened = 0;
    try {
        $dbh->do( 'LISTEN ' . $dbh->quote_identifier($channel) );
        $listened = 1;
    }
    catch ($error) {
        $listened = 0;
    };
    if ( $resumed || !$listened ) {
        $entry->{gap} = 1;
        $self->stats->{gaps} += 1;
    }
    if ( !$listened ) {
        $entry->{failed} = 1;
        $self->stats->{listen_failures} += 1;
        return;
    }

    if ($resumed) {
        $self->stats->{relistens} += 1;
    }
    $entry->{connection} = $self->connection;
    $entry->{failed}     = 0;

    return;
}

# pg_notifies sends nothing to the server: it reads what the server has
# already pushed onto the socket. At most max_queued are read per take; the
# rest wait in libpq's buffer for the next one.
# True when the socket was read, with or without notifications; false when
# the read failed, as it does on a connection the server closed. That
# failure is the signal take acts on, not something to warn about: DBI's
# warning for it, and the server's parting FATAL, which libpq hands to the
# notice processor when it arrives on an idle connection, are held while
# the read runs. A handle that is a double has no err to ask.
sub _pump ( $self, $dbh ) {
    if ( !$dbh->{AutoCommit} || !$dbh->can('pg_notifies') ) {
        return 1;
    }

    ## no critic (Variables::ProhibitLocalVars) -- the handle's own settings, held for this read alone
    local $dbh->{PrintError} = 0;
    local $dbh->{Warn}       = 0;
    ## use critic
    for ( 1 .. $self->max_queued ) {
        my $notification;
        my $failed = 0;
        try {
            $notification = $dbh->pg_notifies;
        }
        catch ($error) {
            $failed = 1;
        };
        if ( $failed
            || ( !$notification && $dbh->can('err') && $dbh->err ) )
        {
            return 0;
        }
        last if !$notification;

        $self->_route($notification);
    }

    return 1;
}

sub _route ( $self, $notification ) {
    my $channel = ref $notification eq 'ARRAY' ? $notification->[0] : undef;
    my $entry   = defined $channel ? $self->channels->{$channel}    : undef;
    if ( !$entry ) {
        $self->stats->{dropped} += 1;
        return;
    }

    $self->stats->{received} += 1;
    my $queue = $entry->{queue};
    push @{$queue}, $notification;

    # The oldest goes, and the consumer learns that something did.
    if ( @{$queue} > $self->max_queued ) {
        shift @{$queue};
        $entry->{gap} = 1;
        $self->stats->{overflowed} += 1;
    }

    return;
}

# One storage->dbh per call. The storage pings the handle there and
# reconnects when the ping fails, which is how a lost backend is noticed.
sub _dbh ($self) {
    return GPForum::Infrastructure::Storage->dbh_of( $self->schema );
}

sub _pid_of ($dbh) {
    return $dbh->{pg_pid} // q{};
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::PgNotifications - One PostgreSQL notification
queue per database handle, routed by channel.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $notifications =
      GPForum::Infrastructure::PgNotifications->new( schema => $schema );

    $notifications->listen_to('gpforum_cache_invalidation');

    my $taken = $notifications->take('gpforum_cache_invalidation');
    clear_everything() if $taken->{gap};
    handle($_) for @{ $taken->{notifications} };

=head1 DESCRIPTION

A PostgreSQL connection has one notification buffer, whatever it LISTENs
to. Each web process shares one handle between the cache invalidation bus
and the realtime listener, and each used to read that buffer whole: the
listener took cache purges and dropped them as malformed, so a worker kept
serving a hidden post from its L1, and the bus took realtime events and
counted them as empty invalidations.

This module owns the buffer. Consumers register their channel with
C<listen_to> and read only their own channel with C<take>; a notification on a
channel nobody registered is counted and dropped.

It also owns the LISTENs. A LISTEN lives on one backend, and the Mojo::Pg storage
replaces the handle after a reconnect, so the backend PID and the handle
identify the connection: when either changes, every registered channel is
listened for again and each is marked with a gap. A LISTEN that fails marks
its channel with a gap too, on that take and on the one that finally
issues it; so does one that C<listen_to> could not issue, with no handle or
inside a transaction, on the take that does. A gap tells the consumer that
notifications were lost -- raised while nobody was listening, or pushed out
of a full queue -- so it can fall back to something that does not need them.

In the web application, C<asynchronous> is enabled and one dedicated native
LISTEN connection is shared by all channels. Its reactor watcher never checks
out or pings the query pool. Explicit storage disconnects retire the listener;
forked children never pump the parent's socket. CLI consumers retain the
synchronous interface on their existing workflow connection.

=head1 SUBROUTINES/METHODS

=head2 ensure_p, listen_to_p, take_p, retire_connections

Establishes native registrations, drains a channel, or retires owned resources.
Concurrent setup calls share one connection attempt. A failed setup or reconnect
marks a gap so consumers invalidate data before admitting another local hit.

=head2 listen_to

Registers a channel and issues its LISTEN. Returns true when the LISTEN is
in effect on the current backend. A channel that could not be listened for
stays registered, every C<take> tries again, and the one that succeeds
reports a gap.

=head2 unlisten

Forgets a channel, dropping its queue, and issues UNLISTEN when its LISTEN
is still on the current connection.

=head2 registered

True when the channel has been registered with C<listen_to>.

=head2 listening

True when the channel's LISTEN is in effect on the connection the last
call saw.

=head2 take

Reads the handle's buffer and returns C<{ available, gap, notifications }>
for one channel: the notifications that arrived since its last take, as
DBD::Pg returns them (C<[ channel, sender_pid, payload ]>), and whether any
were lost. C<available> is false when the handle could not be obtained or
the read still fails after one recovery attempt. An unreadable handle
marks every registered channel with a gap and retires its LISTEN state,
including when recovery returns the same handle. Notifications are read
only outside a transaction.

=head2 snapshot

Counters, the backend PID and each channel's LISTEN state and queue length,
for the metrics surface.

=head1 DIAGNOSTICS

Never throws. A missing schema, an unreachable handle and a failed LISTEN
are counted in C<stats>.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the schema's database handle. C<max_queued> bounds each channel's
queue (1000).

=head1 DEPENDENCIES

L<Mojo::Base>, L<Const::Fast>, L<Scalar::Util>,
L<GPForum::Infrastructure::Storage>.

=head1 INCOMPATIBILITIES

Requires DBD::Pg for C<pg_notifies> and C<pg_pid>. A handle without them
yields nothing.

=head1 BUGS AND LIMITATIONS

Healthy takes read the current handle without a ping and identify its
backend on every call. Channel synchronization is repeated only after a
new registration, a changed connection or a failed LISTEN/read. A failed
read uses C<storage-E<gt>dbh> once to let storage ping and reconnect. Each
take reads at most C<max_queued> notifications; excess messages wait in
libpq for the next consumer poll.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
