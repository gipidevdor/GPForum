# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::LiveSessions;

use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Test::SettledTwins;

our $VERSION = '0.001';

# A session store that answers live_session_ids from the set it is given,
# records each question, and dies while broken.
has live   => sub { return {}; };
has asked  => sub { return []; };
has broken => 0;

# A call layer, when a test gives one: then a blocking twin of the hub runs
# on a copy of the hub, as it does with the identity store.
has functions => undef;

sub live_session_ids ( $self, $session_ids ) {
    push @{ $self->asked }, [ sort @{$session_ids} ];
    die "store unavailable\n" if $self->broken;

    return { map { $_ => 1 } grep { $self->live->{$_} } @{$session_ids} };
}

GPForum::Test::SettledTwins->install( __PACKAGE__, live_session_ids => 1 );

1;
