# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- Mojolicious command name
package GPForum::CLI::mail_in;
## use critic

use Mojo::Base 'Mojolicious::Command', -signatures;
use v5.40;
use Const::Fast;
use Carp qw(croak);
use GPForum::Command::Usage;
use GPForum::Service::Operations::DatabaseFailure;
use GPForum::X::Unavailable;
use GPForum::X::Io;

our $VERSION = '0.001';

const my $INPUT_CHUNK_BYTES => 65_536;
const my $MAX_MAIL_BYTES    => 1_048_576;

# sysexits.h EX_TEMPFAIL: the mail server keeps the message and tries again,
# where any other failure status bounces it to its sender.
const my $EX_TEMPFAIL => 75;
has description => 'Post a MIME reply read from standard input';
has usage =>
"Usage: gpforum mail-in [--json]\n\nRead one email from stdin and post its authenticated reply.\n";

sub run ( $self, @arguments ) {
    return GPForum::Command::Usage->help( \*STDOUT, $self->usage )
      if GPForum::Command::Usage->wants_help(@arguments);
    my $options = GPForum::Command::Usage->read_arguments(
        $self->usage,
        sub {
            return GPForum::Command::Usage->parse_options(
                \@arguments,
                {},
                {
                    switches => { '--json' => { json => 1 } },
                    usage    => $self->usage
                }
            );
        }
    );
    return GPForum::Command::Usage->front_door($options) if !ref $options;
    my $status;
    try {
        croak 'reply by email is disabled'
          if !length $self->app->gp_config->mail_reply_address;
        my $raw        = _read_message();
        my $controller = $self->app->build_controller;
        my $result     = $controller->gp_mail_in->receive($raw);
        if ( $options->{json} ) {
            GPForum::Command::Usage->json(
                \*STDOUT,
                {
                    ok         => $result->{ok} ? 1 : 0,
                    status     => $result->{status},
                    idempotent => $result->{idempotent} ? 1 : 0
                }
            );
        }
        $status =
            $result->{ok}                            ? 0
          : ( $result->{status} // q{} ) eq 'failed' ? $EX_TEMPFAIL
          :                                            1;
    }
    catch ($error) {
        $status = GPForum::Command::Usage->failure($error);
        if ( __PACKAGE__->temporary( $error, $status ) ) {
            $status = $EX_TEMPFAIL;
        }
    };
    return GPForum::Command::Usage->front_door($status);
}

# Whether the reply failed for now rather than for good: the database or
# the forum is unavailable, its settings need the operator, or the member is
# over the reply rate. A reply refused for what it is (no capability, the
# wrong sender, no text) is not.
sub temporary ( $, $error, $status ) {
    return 1 if $status == $GPForum::Command::Usage::EXIT_CONFIG;
    return 1 if GPForum::X::Unavailable->caught($error);
    return
      defined GPForum::Service::Operations::DatabaseFailure->new->classify(
        "$error") ? 1 : 0;
}

sub _read_message {
    binmode STDIN
      or GPForum::X::Io->throw( message => 'cannot read email input' );
    my $raw = q{};
    while (1) {
        my $chunk;
        my $read = read STDIN, $chunk, $INPUT_CHUNK_BYTES;
        if ( !defined $read ) {
            GPForum::X::Io->throw( message => 'cannot read email input' );
        }
        last if !$read;
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
rejected for good: no reply capability, the wrong sender, no text. Two means
invalid arguments. 75 (EX_TEMPFAIL) means not now -- the database or the
forum unavailable, settings needing the operator, or the member over the
reply rate -- and the mail server keeps the message and retries it.

=head1 VERSION

Version 0.001.

=head1 SUBROUTINES/METHODS

=head2 run

Parses the command arguments, runs the operation and reports its exit status.

=head2 temporary

True for a failure the mail server should retry -- an unavailable forum or
database, settings needing the operator (the status
C<$GPForum::Command::Usage::EXIT_CONFIG>), the reply rate -- and false for a
reply refused for what it is.

=head1 DIAGNOSTICS

Invalid arguments exit with status 2. Operational failures are reported on standard error.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the same Good Phorum environment file and application services as the HTTP process.

=head1 DEPENDENCIES

Mojolicious and the Good Phorum services named in this module.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

See the operation description and docs/ops/community-protocols.md.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause license.

=cut
