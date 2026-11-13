# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::LosingRestore;

use Mojo::Base -base, -signatures;
use v5.40;

use DBI;

use GPForum::Service::Operations::StagingDrill::PgTools;

our $VERSION = '0.001';

# The host's pg_dump and pg_restore, as BackupVerifier calls them.
has tools =>
  sub { return GPForum::Service::Operations::StagingDrill::PgTools->find; };

sub dump_database ( $self, @arguments ) {
    return $self->tools->dump_database(@arguments);
}

sub rewrite_dsn ( $self, @arguments ) {
    return $self->tools->rewrite_dsn(@arguments);
}

# The host's pg_restore, then the newest migration row taken out of what it
# restored: a restore that loses a row, for the verifier to count.
sub restore_database ( $self, $dsn, $dump ) {
    $self->tools->restore_database( $dsn, $dump );
    my $restored = DBI->connect(
        $dsn,
        $ENV{GPFORUM_DATABASE_USER}     // q{},
        $ENV{GPFORUM_DATABASE_PASSWORD} // q{},
        { AutoCommit => 1, PrintError => 0, RaiseError => 1 }
    );
    $restored->do( 'DELETE FROM schema_versions WHERE version ='
          . ' (SELECT max(version) FROM schema_versions)' );
    $restored->disconnect;

    return;
}

1;

__END__

=head1 NAME

GPForum::Test::LosingRestore - PostgreSQL tools whose restore loses a row.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $tools = GPForum::Test::LosingRestore->new( tools => $found );

=head1 DESCRIPTION

The host's C<pg_dump> and C<pg_restore> (its C<tools>, found on the host
unless given), with the newest C<schema_versions> row deleted from each
restored database, so a verification that counts the
restore finds one row fewer.

=head1 SUBROUTINES/METHODS

=head2 tools

The L<GPForum::Service::Operations::StagingDrill::PgTools> it runs.

=head2 dump_database

=head2 rewrite_dsn

As its C<tools> do.

=head2 restore_database

Restores as its C<tools> do, then deletes the newest migration row.

=head1 DIAGNOSTICS

None of its own.

=head1 CONFIGURATION AND ENVIRONMENT

C<GPFORUM_DATABASE_USER> and C<GPFORUM_DATABASE_PASSWORD>, for the
connection to the restored database.

=head1 DEPENDENCIES

L<DBI>, L<GPForum::Service::Operations::StagingDrill::PgTools>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

For tests only.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
