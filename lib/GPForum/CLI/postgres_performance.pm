# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
# Mojolicious derives the command name from the lower-case basename.
package GPForum::CLI::postgres_performance;
## use critic
use Mojo::Base 'Mojolicious::Command', -signatures;
use v5.40;
use GPForum::CLI::FrontDoor::Launcher;
use GPForum::Command::PostgresPerformance;
use GPForum::Command::Usage;
our $VERSION = '0.001';
has description =>
  'Inspect, plan, apply and verify PostgreSQL performance settings';
has usage => sub { return GPForum::Command::PostgresPerformance->usage_text; };

# A relative --plan, --restore, --journal or --output reads from where the
# operator typed the command, which the front door remembers before it
# moves to the code directory.
sub run ( $self, @arguments ) {
    my $typed_in = GPForum::CLI::FrontDoor::Launcher->typed_in;

    return GPForum::Command::Usage->front_door(
        GPForum::Command::PostgresPerformance->new(
            defined $typed_in ? ( directory => $typed_in ) : ()
        )->run(@arguments)
    );
}
1;

__END__

=head1 NAME

GPForum::CLI::postgres_performance - Mojolicious adapter for PostgreSQL performance administration.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    gpforum postgres-performance inspect

=head1 DESCRIPTION

Delegates to GPForum::Command::PostgresPerformance without starting the application.

=head1 SUBROUTINES/METHODS

run delegates arguments to the administrative command.

=head1 DIAGNOSTICS

Failures name missing evidence, nonconforming settings or refused authorization.

=head1 CONFIGURATION AND ENVIRONMENT

Receives PostgreSQL settings through L<GPForum::Config>.

=head1 DEPENDENCIES

Uses the existing Good Phorum configuration, OS and database infrastructure.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Resource estimates require an operator budget; measurements remain necessary.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
