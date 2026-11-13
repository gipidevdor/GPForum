# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::FailingAuditRecorder;

use Carp qw(croak);
use Mojo::Base -base;
use v5.40;

use Mojo::Promise;

our $VERSION = '0.001';

# An event recorder whose audit write fails, as a statement or lock timeout
# would, after the caller has written whatever came before it.
sub record_audit {
    croak 'audit write failed';
}

# The same failure, as the rejected promise an asynchronous recorder
# answers.
sub record_audit_p {
    return Mojo::Promise->reject('audit write failed');
}

1;
