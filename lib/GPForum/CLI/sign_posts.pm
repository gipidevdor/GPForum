# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- Mojolicious command name
package GPForum::CLI::sign_posts;
## use critic

use Mojo::Base 'Mojolicious::Command', -signatures;
use v5.40;
use List::Util qw(any);
use GPForum::Service::Forum::PostAttestor;
use GPForum::Command::Usage;

our $VERSION = '0.001';
has description =>
  'Attest existing unsigned post revisions with the server key';
has usage =>
"Usage: gpforum sign-posts [--json]\n\nAttest existing revisions as they are now; existing signatures are never replaced.\n";

sub run ( $self, @arguments ) {
    return GPForum::Command::Usage->front_door(2)
      if any { $_ ne '--json' } @arguments;
    my $status = 0;
    try {
        my $controller = $self->app->build_controller;
        my $result     = GPForum::Service::Forum::PostAttestor->new(
            schema => $controller->gp_schema,
            signer => $controller->gp_post_signer
        )->run;
        GPForum::Command::Usage->json( \*STDOUT, $result );
    }
    catch ($error) { $status = GPForum::Command::Usage->failure($error); };
    return GPForum::Command::Usage->front_door($status);
}

1;

__END__

=head1 NAME

GPForum::CLI::sign_posts - Attest existing unsigned post revisions.

=head1 SYNOPSIS

    gpforum sign-posts --json

=head1 DESCRIPTION

After migrating, run this once as the service account to attest legacy
content. The operation signs batches of one hundred revisions, skips races
with erasure or edits, and is safe to repeat. New posts and edits are signed
in their write transaction automatically. No existing attestation is ever
replaced, including one that now fails verification.

=head1 VERSION

Version 0.001.

=head1 SUBROUTINES/METHODS

=head2 run

Parses the command arguments, runs the operation and reports its exit status.

=head1 DIAGNOSTICS

Invalid arguments exit with status 2. Operational failures are reported on standard error.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the same GPForum environment file and application services as the HTTP process.

=head1 DEPENDENCIES

Mojolicious and the GPForum services named in this module.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

See the operation description and docs/ops/community-protocols.md.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
