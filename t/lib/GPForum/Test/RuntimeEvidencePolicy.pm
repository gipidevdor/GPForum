# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RuntimeEvidencePolicy;

use Mojo::Base -base;
use v5.40;

our $VERSION = '0.001';

# A runtime policy whose report is the one it was given, so OS::RuntimeEvidence
# can be read against a Hypnotoad configuration chosen by the test.

has report => sub { return { status => 'ok' }; };

1;
