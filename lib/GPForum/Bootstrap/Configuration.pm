# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Bootstrap::Configuration;

use v5.40;
use GPForum::Schema;
use GPForum::Service::Admin::Configuration;

our $VERSION = '0.001';

sub load ( $class, $base ) {
    my $schema    = GPForum::Schema->connect_from_config($base);
    my $effective = $base;
    try {
        $effective = GPForum::Service::Admin::Configuration->new(
            schema      => $schema,
            base_config => $base
        )->effective_config;
    }
    catch ($error) { $effective = $base; };
    $schema->storage->disconnect;
    return $effective;
}

1;

__END__

=head1 NAME

GPForum::Bootstrap::Configuration - Administrator GUI configuration boundary.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Wired by GPForum bootstrap and the administrator routes.

=head1 DESCRIPTION

Implements core-owned GUI settings. Provider modules receive no access to
this service, its database or credentials. See docs/integrations.md.

=head1 SUBROUTINES/METHODS

=head2 load

Loads durable forum settings at startup over installation configuration; initial setup remains possible before the migration exists.

=head1 DIAGNOSTICS

Writes return explicit ok, invalid, conflict, forbidden or unavailable states.
Database errors follow the application's normal error boundary. Secrets and
submitted values are not included in diagnostics.

=head1 CONFIGURATION AND ENVIRONMENT

Installation configuration remains the bootstrap source. Durable overrides
are stored in PostgreSQL through versioned functions and administrator writes.

=head1 DEPENDENCIES

Uses the core configuration and authorization boundaries and PostgreSQL API.

=head1 INCOMPATIBILITIES

Requires the administrator configuration migration for editable settings.

=head1 BUGS AND LIMITATIONS

Host bootstrap settings remain deployment-owned; settings marked for restart
are read during service startup. A failed write never reports success.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
