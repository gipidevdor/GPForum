# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::LiveSessions;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# A session store that answers live_session_ids from the set it is given,
# records each question, and dies while broken.
has live   => sub { return {}; };
has asked  => sub { return []; };
has broken => 0;

sub live_session_ids ( $self, $session_ids ) {
    push @{ $self->asked }, [ sort @{$session_ids} ];
    die "store unavailable\n" if $self->broken;

    return { map { $_ => 1 } grep { $self->live->{$_} } @{$session_ids} };
}

1;
