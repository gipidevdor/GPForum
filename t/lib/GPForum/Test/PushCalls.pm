# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::PushCalls;
use Mojo::Base -base, -signatures;
use v5.40;
our $VERSION = '0.001';
has jobs => sub { return []; };
has seen => sub { return []; };

sub rows ( $self, $name, $input ) {
    push @{ $self->seen }, [ $name, $input ];
    return $self->jobs
      if $name eq 'notification_push_claim'
      || $name eq 'notification_push_refresh';
    return [ map { { changed => 1, outcome => $_->{outcome} } }
          @{ $input->{outcomes} } ]
      if $name eq 'notification_push_finish_batch';
    return [ { removed => 0 } ] if $name eq 'notification_push_cleanup';
    return [];
}
sub row ( $self, $name, $input ) { return $self->rows( $name, $input )->[0]; }

1;
