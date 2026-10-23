# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- Mojolicious command name
package GPForum::CLI::mail_in;
## use critic

use Mojo::Base 'Mojolicious::Command', -signatures;
use v5.40;
use Const::Fast;
use Carp       qw(croak);
use List::Util qw(any);
use GPForum::Command::Usage;

our $VERSION = '0.001';

const my $INPUT_CHUNK_BYTES => 65_536;
const my $MAX_MAIL_BYTES    => 1_048_576;
has description => 'Post a MIME reply read from standard input';
has usage =>
"Usage: gpforum mail-in [--json]\n\nRead one email from stdin and post its authenticated reply.\n";

sub run ( $self, @arguments ) {
    return GPForum::Command::Usage->help( \*STDOUT, $self->usage )
      if GPForum::Command::Usage->wants_help(@arguments);
    return GPForum::Command::Usage->front_door(2)
      if any { $_ ne '--json' } @arguments;
    my $status;
    try {
        croak 'reply by email is disabled'
          if !length $self->app->gp_config->mail_reply_address;
        my $raw        = _read_message();
        my $controller = $self->app->build_controller;
        my $result     = $controller->gp_mail_in->receive($raw);
        if (@arguments) {
            GPForum::Command::Usage->json(
                \*STDOUT,
                {
                    ok         => $result->{ok} ? 1 : 0,
                    status     => $result->{status},
                    idempotent => $result->{idempotent} ? 1 : 0
                }
            );
        }
        $status = $result->{ok} ? 0 : 1;
    }
    catch ($error) { $status = GPForum::Command::Usage->failure($error); };
    return GPForum::Command::Usage->front_door($status);
}

sub _read_message {
    binmode STDIN or croak 'cannot read email input';
    my $raw = q{};
    while (1) {
        my $chunk;
        my $read = read STDIN, $chunk, $INPUT_CHUNK_BYTES;
        croak 'cannot read email input' if !defined $read;
        last                            if !$read;
        $raw .= $chunk;
        croak 'email exceeds one MiB' if length($raw) > $MAX_MAIL_BYTES;
    }
    return $raw;
}

1;

__END__

=head1 NAME

GPForum::CLI::mail_in - Accept one authenticated reply from a local mail alias.

=head1 SYNOPSIS

    gpforum mail-in < reply.eml
    gpforum mail-in --json < reply.eml

=head1 DESCRIPTION

Set GPFORUM_MAIL_REPLY_ADDRESS and deliver that local address to this
command through the mail server. It needs the same environment file and
service account as the forum. In-Reply-To must contain the complete
recipient-specific Message-ID from a notification. From alone is never
authentication. A public archive Message-ID does not authorize posting.

=head1 EXIT STATUS

Zero means accepted, held for moderation, or already processed. One means
rejected or unavailable. Two means invalid arguments. A local MTA should
quarantine failures for operator review rather than bounce automated mail.

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
