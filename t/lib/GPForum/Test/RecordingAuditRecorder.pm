# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RecordingAuditRecorder;

use Mojo::Base -base;
use v5.40;

use Mojo::Promise;

our $VERSION = '0.001';

# An event recorder that keeps each audit it is asked to write, as the
# arguments it was given, and answers that it wrote it.
has audits => sub { return []; };

sub record_audit ( $self, %audit ) {
    push @{ $self->audits }, \%audit;

    return { %audit, audit_id => scalar @{ $self->audits } };
}

# The same, as the promise an asynchronous recorder answers.
sub record_audit_p ( $self, $audit, $context = undef ) {
    return Mojo::Promise->resolve( $self->record_audit( %{$audit} ) );
}

1;
