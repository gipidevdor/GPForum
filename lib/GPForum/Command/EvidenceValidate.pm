# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Command::EvidenceValidate;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Command::Usage;
use GPForum::Service::Operations::EvidenceValidate;
use GPForum::X::Io;

our $VERSION = '0.001';

# Each flag sets one option to one value.
const my %FLAG_OPTIONS => (
    '--json'   => [ format => 'json' ],
    '--human'  => [ format => 'human' ],
    '--strict' => [ strict => 1 ],
);

has validate => undef;    # optional: a test's double; else the real one

sub run ( $self, @arguments ) {
    return GPForum::Command::Usage->help( \*STDOUT, _usage() )
      if GPForum::Command::Usage->wants_help(@arguments);
    return GPForum::Command::Usage->evidence_command(
        sub { return _options(@arguments); },
        sub ($options) { return $self->_run($options); },
        sub ($options) { return { check => 'evidence_validate' }; },
    );
}

sub _run ( $self, $options ) {
    my $service  = $self->_service;
    my $evidence = $service->run($options);
    print $service->format_evidence( $evidence, $options->{format} )
      or GPForum::X::Io->throw(
        message => 'failed to write evidence-validate evidence' );

    return $service->exit_status($evidence);
}

sub _service ($self) {
    return $self->validate if $self->validate;

    return GPForum::Service::Operations::EvidenceValidate->new;
}

sub _options (@arguments) {
    my %options = (
        format => 'json',
        strict => 0,
        paths  => [],
    );

    for my $argument (@arguments) {
        if ( exists $FLAG_OPTIONS{$argument} ) {
            my ( $name, $value ) = @{ $FLAG_OPTIONS{$argument} };
            $options{$name} = $value;
            next;
        }
        if ( $argument =~ /\A-/msx ) {
            GPForum::Command::Usage->misuse( 'cli.misuse.unknown_option',
                { option => $argument }, _usage() );
        }
        push @{ $options{paths} }, $argument;
    }

    return \%options;
}

# Public so the Mojolicious command adapter in GPForum::CLI can show the same
# text `--help` prints, instead of a second copy that drifts.
sub usage_text ($class) {
    return _usage();
}

sub _usage {
    return <<'USAGE';
Usage: gpforum evidence-validate [options] FILE [FILE...]

Validate archived private-beta *preparation* evidence JSON. Rejects obvious
secrets and readiness claims. With --strict, also require modern redaction /
residual_gaps markers. Does not claim private-beta readiness.

  --json     report as JSON (default)
  --human    short plain-text report
  --strict   fail on missing residual_gaps / secrets_redacted markers
  --help     show this help
USAGE
}

1;

__END__

=head1 NAME

GPForum::Command::EvidenceValidate - Validate archived ops evidence JSON CLI.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    exit GPForum::Command::EvidenceValidate->new->run(@ARGV);

=head1 DESCRIPTION

Operator CLI for non-destructive evidence archive validation.

=head1 SUBROUTINES/METHODS

=head2 validate

The validator to run; a test passes a double. Without one, a
L<GPForum::Service::Operations::EvidenceValidate>.

=head2 run

Runs the command with its arguments; returns the exit status.

=head2 usage_text

The usage text, for the front door.

=head1 DIAGNOSTICS

Misuse exits 2 with the usage on standard error. An error the validator raises
instead of reporting exits 1 with its reason, redacted, on standard error
and, with C<--json> (the default), evidence on standard output with
C<status> C<fail> and the reason in C<error>.

=head1 CONFIGURATION AND ENVIRONMENT

None: everything comes from the arguments.

=head1 DEPENDENCIES

L<GPForum::Service::Operations::EvidenceValidate>,
L<GPForum::Command::Usage>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The secret and readiness checks are patterns: they catch the obvious
cases, not every way a secret can be written.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
