# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Schema;

use Mojo::Base 'DBIx::Class::Schema', -signatures;
use v5.40;

our $VERSION = '0.001';

__PACKAGE__->load_namespaces;

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
    }
    return $class->connect( $dsn, $user, $password, $attributes );
}

1;

__END__

=head1 NAME

GPForum::Schema - DBIx::Class schema root.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $schema = GPForum::Schema->connect_from_config($config);

=head1 DESCRIPTION

Defines the Good Phorum DBIx::Class schema root and keeps database wiring outside
the Mojolicious application root.

=head1 SUBROUTINES/METHODS

=head2 connect_from_config

Creates a schema connection from a validated Good Phorum configuration object.

=head1 DIAGNOSTICS

Connection failures are reported by DBIx::Class and DBI.

=head1 CONFIGURATION AND ENVIRONMENT

Receives database connection information from L<GPForum::Config>.

=head1 DEPENDENCIES

Uses L<DBIx::Class::Schema> through L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Only foundational metadata results are present in this milestone.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
