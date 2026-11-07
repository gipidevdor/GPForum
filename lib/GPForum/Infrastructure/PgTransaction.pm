# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::PgTransaction;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Carp qw(croak);
use GPForum::Infrastructure::AsyncGate;
use Mojo::Promise;

our $VERSION = '0.001';
__PACKAGE__->requires('database');
has context  => undef;   # optional: commands outside HTTP have no request token
has stats    => undef;   # optional: observers can be disabled
has level    => 0;
has sequence => 0;
has gate =>
  sub { return GPForum::Infrastructure::AsyncGate->new( concurrency => 1 ); };

sub query_p ( $self, $work ) { return $self->gate->run_p($work); }

sub run_p ( $self, $work, $readonly = 0 ) {
    my $nested = $self->level;
    my $savepoint =
      'gp_async_' . ( $self->sequence( $self->sequence + 1 )->sequence );
    my $begin =
        $nested   ? "SAVEPOINT $savepoint"
      : $readonly ? 'BEGIN READ ONLY'
      :             'BEGIN';
    my $commit = $nested ? "RELEASE SAVEPOINT $savepoint" : 'COMMIT';
    return $self->_control_p($begin)->then(
        sub {
            $self->level( $nested + 1 );
            if ( !$nested ) { $self->_observe('txn_begin'); }
            return Mojo::Promise->resolve->then($work);
        }
    )->then(
        sub (@values) {
            return $self->_control_p($commit)->then(
                sub ($result) {
                    croak 'transaction was rolled back before commit'
                      if !$nested
                      && ( $result->sth->{pg_cmd_status} // q{} ) eq 'ROLLBACK';
                    $self->level($nested);
                    if ( !$nested ) { $self->_observe('txn_commit'); }
                    return @values;
                }
            );
        }
    )->catch(
        sub ($error) {
            my $rolled_back = 0;
            my $rollback =
              $nested ? "ROLLBACK TO SAVEPOINT $savepoint" : 'ROLLBACK';
            return $self->_control_p($rollback)->then(
                sub {
                    $rolled_back = 1 if !$nested;
                    return $nested ? $self->_control_p($commit) : undef;
                }
            )->catch( sub { return; } )->then(
                sub {
                    $self->level($nested);
                    if ( !$nested ) { $self->_observe('txn_rollback'); }
                    $self->database->{gp_reusable_after_error} = 1
                      if $rolled_back
                      && blessed($error)
                      && ( $error->isa('GPForum::X::Argument')
                        || $error->isa('GPForum::X::Conflict') );
                    die $error;    ## no critic (ErrorHandling::RequireCarping) -- preserve the original error, never retry an ambiguous commit
                }
            );
        }
    );
}

sub _control_p ( $self, $sql ) {
    return $self->query_p( sub { return $self->database->query_p($sql); } );
}

sub _observe ( $self, $method ) {
    return if !$self->stats;
    $self->stats->in_context( $self->context,
        sub { $self->stats->$method; return; } );
    return;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::PgTransaction - Own an asynchronous PostgreSQL transaction and its savepoints.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $transaction->run_p(sub { return $work_p->(); });

=head1 DESCRIPTION

Runs BEGIN, COMMIT, ROLLBACK and nested savepoint control through native
Mojo::Pg promises. Queries sharing the owned connection are serialized. A failed
commit is never replayed, and rollback failure preserves the original rejection.

=head1 SUBROUTINES/METHODS

=head2 run_p

Owns a transaction for the lifetime of a promise. Nested calls use savepoints.

=head2 query_p

Serializes a query-producing callback on this transaction's connection.

=head1 DIAGNOSTICS

Database failures reject the promise with the original cause.

=head1 CONFIGURATION AND ENVIRONMENT

The caller supplies an exclusively leased database and optional request observer.

=head1 DEPENDENCIES

Mojolicious and Mojo::Pg.

=head1 INCOMPATIBILITIES

A scope cannot be shared by unrelated concurrent transactions.

=head1 BUGS AND LIMITATIONS

The owning executor retires connections after failed transactions.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
