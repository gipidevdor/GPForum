# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Schema;

use Mojo::Base -base, -signatures;
use v5.40;
use GPForum::Infrastructure::PgStorage;

our $VERSION = '0.001';

has storage => sub { return GPForum::Infrastructure::PgStorage->new; };

sub connect ( $class, @info ) {    ## no critic (Subroutines::ProhibitBuiltinHomonyms) -- retain the established connection factory API
    my $self = $class->new;
    $self->storage->connect_info( \@info );
    return $self;
}

sub pg           ($self)          { return $self->storage->pg; }
sub txn_do       ( $self, @args ) { return $self->storage->txn_do(@args); }
sub txn_begin    ($self)          { return $self->storage->txn_begin; }
sub txn_commit   ($self)          { return $self->storage->txn_commit; }
sub txn_rollback ($self)          { return $self->storage->txn_rollback; }

sub connect_from_config ( $class, $config ) {
    my ( $dsn, $user, $password, $attributes ) = $config->database_connect_info;
    if (   $config->is_production
        || $config->environment eq 'staging'
        || $config->postgres_strict )
    {
        $attributes->{on_connect_call} = sub ($storage) {
            require GPForum::Infrastructure::PostgresPerformance;
            GPForum::Infrastructure::PostgresPerformance->new(
                config => $config,
                dbh    => $storage->dbh,
            )->enforce;
            return;
        };
        $attributes->{on_connect_call_p} = sub ( $storage, $db ) {
            return GPForum::Infrastructure::PostgresPerformance->new(
                config => $config,
                dbh    => $db->dbh,
            )->enforce_p($db);
        };
    }
    return $class->connect( $dsn, $user, $password, $attributes );
}

1;

__END__

=head1 NAME

GPForum::Schema - Mojo::Pg connection and transaction boundary.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $schema = GPForum::Schema->connect_from_config($config);

=head1 DESCRIPTION

Keeps PostgreSQL wiring outside the Mojolicious application root. Runtime
services use the versioned stored-function catalogue through Mojo::Pg; this
class provides no ORM, resultsets or SQL generator.

=head1 SUBROUTINES/METHODS

=head2 connect_from_config

Creates a schema connection from a validated Good Phorum configuration object.

=head1 DIAGNOSTICS

Connection failures are reported by Mojo::Pg and DBD::Pg.

=head1 CONFIGURATION AND ENVIRONMENT

Receives database connection information from L<GPForum::Config>.

=head1 DEPENDENCIES

L<Mojo::Pg>, L<GPForum::Infrastructure::PgStorage>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Existing synchronous workflows remain synchronous. Switching the transport
does not automatically turn a workflow into a promise-based HTTP handler.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
