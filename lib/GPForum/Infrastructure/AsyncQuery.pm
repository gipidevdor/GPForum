# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::AsyncQuery;

use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::Promise;
use English qw(-no_match_vars);
use GPForum::Infrastructure::AsyncGate;

our $VERSION = '0.001';
has schema      => undef, weak => 1;
has gate        => sub { return GPForum::Infrastructure::AsyncGate->new; };
has idle        => sub { return []; };
has connections => sub { return []; };
has owner       => sub { return $PROCESS_ID; };
has generation  => 0;

sub for_schema ( $class, $schema ) {
    my $executor = $schema->{gp_async_query} //=
      $class->new( schema => $schema );
    $schema->storage->async_queries($executor);
    return $executor;
}

sub _owned ($self) {
    return if $self->owner == $PROCESS_ID;
    for my $db ( @{ $self->connections } ) {
        $db->dbh->{InactiveDestroy} = 1;
        $db->pg(undef);
        delete $db->{waiting};
        delete $db->{finish};
    }
    $self->idle( [] );
    $self->connections( [] );
    $self->owner($PROCESS_ID);
    return;
}

sub _connect ($self) {
    my $db = $self->schema->pg->db;

    # These leases stay outside Mojo::Pg's idle queue, whose checkout sends
    # a synchronous DBD::Pg ping. Failed leases are discarded, never replayed.
    $db->dbh->{private_mojo_no_reuse} = 1;
    $db->dbh->{pg_skip_deallocate}    = 1;
    push @{ $self->connections }, $db;
    return $db;
}

sub _connect_p ( $self, $context ) {
    return $self->schema->storage->database_p($context)->then(
        sub ($db) {
            push @{ $self->connections }, $db;
            return $db;
        }
    );
}

# Explicit storage disconnects retire idle leases immediately. Running work
# keeps its own handle until it settles, then retires without replaying it.
sub retire_connections ($self) {
    $self->_owned;
    $self->generation( $self->generation + 1 );
    my @idle = @{ $self->idle };
    $self->idle( [] );
    for my $db (@idle) {
        @{ $self->connections } = grep { $_ != $db } @{ $self->connections };
        $db->disconnect;
    }
    return;
}

sub prewarm ($self) {
    $self->_owned;
    $self->schema->storage->database;
    while ( @{ $self->connections } < $self->gate->concurrency ) {
        push @{ $self->idle }, $self->_connect;
    }
    return scalar @{ $self->connections };
}

sub prewarm_p ($self) {
    return $self->{warming} if $self->{warming};
    $self->_owned;
    my @leases = map {
        $self->run_p( sub { return Mojo::Promise->resolve; } );
    } 1 .. $self->gate->concurrency;
    my $promise = Mojo::Promise->all(@leases)
      ->then( sub { return scalar @{ $self->connections }; } );
    $self->{warming} = $promise;
    return $promise->finally( sub { delete $self->{warming}; return; } );
}

sub run_p ( $self, $work, $context = undef ) {
    return $self->gate->run_p(
        sub {
            my $stats =
                $self->schema->storage->debug
              ? $self->schema->storage->debugobj
              : undef;
            my $start = sub {
                $self->_owned;
                my $db;
                my $available =
                  @{ $self->idle }
                  ? Mojo::Promise->resolve( shift @{ $self->idle } )
                  : $self->_connect_p($context);
                my $failed     = 0;
                my $generation = $self->generation;
                return $available->then(
                    sub ($leased) {
                        $db = $leased;
                        my $run = sub { return $work->($db); };
                        return $stats
                          ? $stats->in_context( $context, $run )
                          : $run->();
                    }
                )->catch(
                    sub ($error) {
                        $failed = 1;
                        die $error;    ## no critic (ErrorHandling::RequireCarping) -- preserve the promise rejection
                    }
                )->finally(
                    sub {
                        return if !$db;
                        if ( $failed || $generation != $self->generation ) {
                            @{ $self->connections } =
                              grep { $_ != $db } @{ $self->connections };
                        }
                        else { push @{ $self->idle }, $db; }
                        undef $db;
                        return;
                    }
                );
            };
            return $stats ? $stats->in_context( $context, $start ) : $start->();
        }
    );
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::AsyncQuery - Lease isolated Mojo::Pg connections for asynchronous operations.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Infrastructure::AsyncQuery->for_schema($schema)
      ->run_p(sub ($db) { return $db->query_p($statement, @bind); });

=head1 DESCRIPTION

One executor belongs to a schema. Two dedicated Mojo::Pg connections serve active operations independently of synchronous workflow transactions. Keeping those handles outside Mojo::Pg's idle queue avoids its synchronous checkout ping. Worker startup warms the connections; failed leases are discarded, and inherited leases are detached after fork. The callback consumes its results before settling.

=head1 SUBROUTINES/METHODS

=head2 for_schema, run_p, prewarm, prewarm_p, retire_connections

Lease isolated Mojo::Pg connections for asynchronous operations.

=head1 DIAGNOSTICS

Failures reject promises. HTTP callers finish or reject their response through the controller's request context.

=head1 CONFIGURATION AND ENVIRONMENT

Runtime limits have safe built-in defaults. No environment setting is required.

=head1 DEPENDENCIES

Mojolicious and the modules named in the source.

=head1 INCOMPATIBILITIES

HTTP callers consume promises without starting a nested event loop.

=head1 BUGS AND LIMITATIONS

Admission is bounded per web worker, not across multiple hosts. CLI workflows keep their synchronous interfaces.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
