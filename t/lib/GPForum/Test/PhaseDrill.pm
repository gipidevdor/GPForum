# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::PhaseDrill;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# One phase of staging-drill-attachments that answers with the status it was
# given, or with no status at all when it was given none -- or with the
# whole evidence a real drill gave.
has status   => undef;    # optional: a phase may answer without one
has evidence => undef;    # optional: answered as it is when given

sub run ( $self, $options ) {
    return $self->evidence if defined $self->evidence;
    return {}              if !defined $self->status;

    return { status => $self->status };
}

1;
