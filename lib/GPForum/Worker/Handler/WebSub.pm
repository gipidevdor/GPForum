# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Worker::Handler::WebSub;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;

our $VERSION = '0.001';
__PACKAGE__->requires('publisher');
const my %AGGREGATES => ( post => 1, thread => 1 );
const my %EVENTS => map { $_ => 1 }
  qw(created updated deleted hidden restored undeleted moved locked unlocked);

sub supports ( $self, $event ) {
    my ( $kind, $action, $extra ) = split /[.]/msx, $event->{event_type} // q{};
    return 0 if defined $extra;
    return
         $self->publisher->enabled
      && exists $AGGREGATES{ $kind // q{} }
      && exists $EVENTS{ $action   // q{} } ? 1 : 0;
}

sub handle ( $self, $event ) { return $self->publisher->publish; }

1;
