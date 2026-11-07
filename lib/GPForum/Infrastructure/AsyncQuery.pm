# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::AsyncQuery;

use Mojo::Base -base, -async_await;
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
has stats       => sub {
    return { created => 0, retired_errors => 0, reused_after_refusal => 0 };
};

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
    $self->stats->{created}++;
    return $db;
}

sub _connect_p ( $self, $context ) {
    return $self->schema->storage->database_p($context)->then(
        sub ($db) {
            push @{ $self->connections }, $db;
            $self->stats->{created}++;
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
                my $generation = $self->generation;
                return $self->_run_leased_p( shift @{ $self->idle },
                    $work, $stats, $context, $generation )
                  if @{ $self->idle };
                return $self->_connect_p($context)->then(
                    sub ($leased) {
                        return $self->_run_leased_p( $leased, $work, $stats,
                            $context, $generation );
                    }
                );
            };
            return $stats ? $stats->in_context( $context, $start ) : $start->();
        },
        $context
    );
}

async sub _run_leased_p ( $self, $db, $work, $stats, $context, $generation ) {

    # One completion owns lease cleanup on success, rejection and synchronous
    # failure. Reusing an idle handle needs no intermediate promise chain.
    my ( @values, $error );
    delete $db->{gp_reusable_after_error};
    try {
        my $run     = sub { return $work->($db); };
        my @pending = $stats ? $stats->in_context( $context, $run ) : $run->();
        @values = await Mojo::Promise->resolve(@pending);
    }
    catch ($caught) { $error = $caught; };
    my $clean_refusal =
         defined $error
      && $db->{gp_reusable_after_error}
      && blessed($error)
      && ( $error->isa('GPForum::X::Argument')
        || $error->isa('GPForum::X::Conflict') )
      && $db->dbh->{Active}
      && ( $db->dbh->{pg_async_status} // 1 ) == 0;
    if ( ( defined $error && !$clean_refusal )
        || $generation != $self->generation )
    {
        @{ $self->connections } = grep { $_ != $db } @{ $self->connections };
        $self->stats->{retired_errors}++ if defined $error;
    }
    else {
        push @{ $self->idle }, $db;
        $self->stats->{reused_after_refusal}++ if $clean_refusal;
    }
    die $error if defined $error;    ## no critic (ErrorHandling::RequireCarping) -- preserve the original lease failure
    return @values;
}

sub snapshot ($self) {
    return {
        %{ $self->gate->snapshot },
        leases      => scalar @{ $self->connections },
        idle_leases => scalar @{ $self->idle },
        lease_stats => { %{ $self->stats } }
    };
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
