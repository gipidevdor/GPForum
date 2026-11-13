# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::AuditCallFailure;

use Carp qw(croak);
use Mojo::Base 'GPForum::Infrastructure::EventRecorder';
use v5.40;

our $VERSION = '0.001';

# An event recorder whose audit fails to build, as a statement or lock
# timeout would fail its write: after the caller has written the change and
# its event in the same transaction.
sub audit_call ( $self, %input ) {
    croak 'audit write failed';
}

1;
