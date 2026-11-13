# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::UnavailableWrite;

use Mojo::Base -base;
use v5.40;

use Mojo::Promise;

use GPForum::Service::Operations::CommandIdempotency;

our $VERSION = '0.001';

sub assign_report {
    my ($self) = @_;

    return $self->_fail;
}

sub create_suspension {
    my ($self) = @_;

    return $self->_fail;
}

sub revoke_suspension {
    my ($self) = @_;

    return $self->_fail;
}

sub create_post {
    my ($self) = @_;

    return $self->_fail;
}

sub create_report {
    my ($self) = @_;

    return $self->_fail;
}

sub hide_post {
    my ($self) = @_;

    return $self->_fail;
}

sub mark_thread_read {
    my ($self) = @_;

    return $self->_fail;
}

# The export Privacy::Workflow awaits (ADR 0177).
sub request_user_export_p {
    my ($self) = @_;

    return $self->_fail;
}

# The command log's run_p, its database gone: the promise is rejected
# before the command runs.
sub run_p {
    my ($self) = @_;

    my $promise;
    try { $self->_fail; }
    catch ($error) { $promise = Mojo::Promise->reject($error); };

    return $promise;
}

# The workflows reach run_p() through CommandIdempotency's result_of_p: run
# the real one, so a regression that turned run_p()'s failure into a refusal
# would show.
sub result_of_p {
    my ( $self, @arguments ) = @_;

    return GPForum::Service::Operations::CommandIdempotency::result_of_p( $self,
        @arguments );
}

sub _fail {
    die "DBI connect: could not connect to server\n";
}

1;
