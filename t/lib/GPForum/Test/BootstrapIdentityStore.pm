# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::BootstrapIdentityStore;

use Mojo::Base -base;
use v5.40;

our $VERSION = '0.001';

# An identity store whose only valid session is "valid"; it keeps every
# validation it was asked for.

has validations => sub { return []; };

sub validate_session {
    my ( $self, $input ) = @_;

    push @{ $self->validations }, $input;
    return { ok => 1 } if $input->{session_id} eq 'valid';

    return { ok => 0, error => 'revoked' };
}

1;
