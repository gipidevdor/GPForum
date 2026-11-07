# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Operations::EvidenceHost;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use English    qw(-no_match_vars);
use Exporter   qw(import);
use IPC::Open3 qw(open3);
use Mojo::File qw(path);

our $VERSION = '0.001';

our @EXPORT_OK = qw(
  evidence_capture
  evidence_executable
  evidence_repository_root
  evidence_trimmed
);

const my $EXIT_SHIFT       => 8;
const my $REPO_ROOT_MARKER => 'cpanfile';
const my $ROOT_WALK_LIMIT  => 8;

# A command run with its output and its errors on one handle, read to the
# end, so a command that writes much to either never waits on the other:
# { ok, exit, output }. ok only when it exited 0 -- one a signal killed did
# not succeed, whatever its exit code reads.
sub evidence_capture ($command) {
    my $pid = open3( my $input, my $output, undef, @{$command} );
    close $input or croak "cannot close the input of $command->[0]: $OS_ERROR";
    my $text = do { local $INPUT_RECORD_SEPARATOR = undef; <$output> };
    close $output
      or croak "cannot close the output of $command->[0]: $OS_ERROR";
    waitpid $pid, 0;

    return {
        ok     => $CHILD_ERROR == 0 ? 1 : 0,
        exit   => $CHILD_ERROR >> $EXIT_SHIFT,
        output => $text // q{},
    };
}

# The first executable file of that name on PATH, or undef.
sub evidence_executable ($name) {
    for my $directory ( split /:/msx, $ENV{PATH} // q{} ) {
        next if !length $directory;
        my $candidate = path( $directory, $name )->to_string;
        return $candidate if -f $candidate && -x _;
    }

    return undef;
}

# The checkout this code is part of: the nearest directory above it that
# holds a cpanfile, or undef when there is none.
sub evidence_repository_root {
    my $cursor = path(__FILE__)->realpath->dirname;
    for ( 1 .. $ROOT_WALK_LIMIT ) {
        return $cursor->to_string if -f $cursor->child($REPO_ROOT_MARKER);
        last                      if "$cursor" eq $cursor->dirname->to_string;
        $cursor = $cursor->dirname;
    }

    return undef;
}

# An error, or a command's output, as evidence keeps it: as text, without
# the blank lines and spaces it ends with.
sub evidence_trimmed ($text) {
    return ( defined $text ? "$text" : q{} ) =~ s/\s+\z//msxr;
}

1;

__END__

=head1 NAME

GPForum::Service::Operations::EvidenceHost - What the evidence commands
ask of the host.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    use GPForum::Service::Operations::EvidenceHost qw(
      evidence_capture
      evidence_executable
    );

    my $nginx = evidence_executable('nginx');
    my $test  = evidence_capture( [ $nginx, '-t', '-c', $config ] );

=head1 DESCRIPTION

The host probes the staging and deploy drills share: running a command and
keeping what it said, finding a tool on C<PATH>, finding the checkout, and
trimming an error for the evidence. The functions are exported on request.

=head1 SUBROUTINES/METHODS

=head2 evidence_capture

Takes a command as an array reference and runs it, its standard output and
standard error on one handle. Returns C<< { ok, exit, output } >>: C<ok> is
1 only when the command exited 0, not when a signal ended it; C<exit> is its
exit code; C<output> what it printed.

=head2 evidence_executable

Takes a name and returns the first executable file of that name in a
directory of C<PATH>, or undef.

=head2 evidence_repository_root

Returns the nearest directory above this module that holds a C<cpanfile>,
or undef when there is none within eight levels.

=head2 evidence_trimmed

Takes an error or some output and returns it as text without its trailing
whitespace; undef reads as the empty string.

=head1 DIAGNOSTICS

L</evidence_capture> croaks when it cannot close the command's handles, and
lets L<IPC::Open3>'s error through when the command cannot be run.

=head1 CONFIGURATION AND ENVIRONMENT

C<PATH>, for L</evidence_executable>.

=head1 DEPENDENCIES

L<IPC::Open3>, L<Mojo::File>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

L</evidence_capture> keeps the whole output in memory.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
