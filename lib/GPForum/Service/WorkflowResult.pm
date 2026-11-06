# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::WorkflowResult;

use v5.40;

use Exporter qw(import);

use GPForum::Infrastructure::Text qw(trimmed);

our $VERSION = '0.001';

our @EXPORT_OK = qw(log_error missing_command_id workflow_result);

# What a workflow answers: its status, ok when that is ok, and the error,
# the errors and what it stored. Eight workflows each kept this copy.
sub workflow_result (%input) {
    return {
        error  => $input{error},
        errors => $input{errors},
        ok     => ( $input{status} || q{} ) eq 'ok' ? 1 : 0,
        status => $input{status} || 'failed',
        stored => $input{stored},
    };
}

# The answer to a command without its command_id, or undef when it has one.
sub missing_command_id ($input) {
    return undef if length trimmed( $input->{command_id} );

    return workflow_result(
        errors => { command_id => 'command_id is required' },
        status => 'invalid',
    );
}

# A workflow's failure, logged when it was given a logger.
sub log_error ( $logger, $message ) {
    if ($logger) {
        $logger->error($message);
    }

    return;
}

1;

__END__

=head1 NAME

GPForum::Service::WorkflowResult - What the service workflows answer with.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    use GPForum::Service::WorkflowResult
      qw(log_error missing_command_id workflow_result);

    my $missing = missing_command_id($input);
    return $missing if $missing;
    ...
    return workflow_result( status => 'ok', stored => $row );

=head1 DESCRIPTION

The result shape and the two helpers the admin, attachment, community,
identity, moderation, notification, privacy and read workflows share.
Exported on request.

=head1 SUBROUTINES/METHODS

=head2 workflow_result

Takes C<status>, C<error>, C<errors> and C<stored> and returns
C<< { status, ok, error, errors, stored } >>: C<ok> is 1 when the status is
C<ok>, and a missing status reads as C<failed>.

=head2 missing_command_id

Takes a command's input and returns an C<invalid> result naming
C<command_id> when it has none, or undef.

=head2 log_error

Takes a logger, which may be undef, and a message, and logs the message as
an error when there is a logger.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::Text>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
