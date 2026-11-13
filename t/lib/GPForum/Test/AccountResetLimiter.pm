# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::AccountResetLimiter;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# Refuses the per-account password reset and allows every other action.
sub check ( $, $input ) {
    return {
        ok => $input->{action} eq 'identity.password_reset_account' ? 0 : 1 };
}

1;
