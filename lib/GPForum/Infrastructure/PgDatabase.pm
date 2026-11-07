# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::PgDatabase;
use Mojo::Base 'Mojo::Pg::Database', -signatures;
use v5.40;

our $VERSION = '0.001';

sub DESTROY ($self) {

    # At process teardown DBI may already have destroyed its tied handles.
    # The operating system closes these private sockets; no pool requeue or
    # SQL cleanup is needed after global destruction has started.
    return if ${^GLOBAL_PHASE} eq 'DESTRUCT';    ## no critic (Variables::ProhibitPunctuationVars) -- Perl exposes the destruction phase only through this special variable
    return $self->SUPER::DESTROY;
}

sub query ( $self, $sql, @arguments ) {
    if ( @arguments && ref $arguments[-1] eq 'CODE' ) {
        my $callback = pop @arguments;
        push @arguments, sub ( $database, $error, $results ) {

            # DBD::Pg deliberately returns zero (not undef) for SQLSTATE
            # 57014. Mojo::Pg otherwise resolves cancellations as empty success.
            if ( !$error && ( $database->dbh->state // q{} ) eq '57014' ) {
                $error = $database->dbh->pg_error_field('primary')
                  // 'PostgreSQL query cancelled';
            }
            return $callback->( $database, $error, $results );
        };
    }

    # DBD::Pg chooses the simple-query protocol without bind parameters.
    # Starting an asynchronous named prepare first would leave that command
    # in flight when execute tries to send the simple query. Catalogued calls
    # without inputs carry an internal boolean bind, retaining plan protection.
    if ( @arguments == 1 && ref $arguments[0] eq 'CODE' ) {
        ## no critic (Variables::ProhibitLocalVars) -- only the native statement's synchronous preparation scope
        local $self->dbh->{pg_prepare_now} = 0;
        ## use critic
        return $self->SUPER::query( $sql, @arguments );
    }
    return $self->SUPER::query( $sql, @arguments );
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::PgDatabase - Preserve nonblocking execution for parameterless native commands.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $database->query_p('BEGIN');

=head1 DESCRIPTION

Avoids overlapping asynchronous PREPARE and simple-query execution for native
commands without bind parameters. Parameterized stored-function calls retain
named preparation from the first execution.

=head1 SUBROUTINES/METHODS

=head2 DESTROY

Avoids accessing already destroyed DBI handles during process teardown.

=head2 query

Uses the standard Mojo::Pg callback and promise contracts.

=head1 DIAGNOSTICS

Uses the native PostgreSQL error boundary.

=head1 CONFIGURATION AND ENVIRONMENT

Created by the asynchronous connection factory.

=head1 DEPENDENCIES

Mojo::Pg and DBD::Pg.

=head1 INCOMPATIBILITIES

No application-level SQL is generated here.

=head1 BUGS AND LIMITATIONS

Parameterless dynamic-result application calls must use SqlFunction's typed bind.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
