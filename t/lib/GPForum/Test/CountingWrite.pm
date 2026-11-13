# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::CountingWrite;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use Mojo::Util qw(monkey_patch);

our $VERSION = '0.001';

__PACKAGE__->requires(qw(inner));
has create_post_calls   => 0;
has create_thread_calls => 0;

sub create_post {
    my ( $self, $command ) = @_;

    $self->create_post_calls( $self->create_post_calls + 1 );

    return $self->inner->create_post($command);
}

sub create_thread {
    my ( $self, $command ) = @_;

    $self->create_thread_calls( $self->create_thread_calls + 1 );

    return $self->inner->create_thread($command);
}

# The other writes pass through to the inner store, uncounted.
monkey_patch __PACKAGE__,
  map { $_ => _passed($_) }
  qw(edit_post delete_post restore_post edit_thread move_thread
  delete_thread restore_thread);

sub _passed ($method) {
    return
      sub ( $self, @arguments ) { return $self->inner->$method(@arguments); };
}

1;
