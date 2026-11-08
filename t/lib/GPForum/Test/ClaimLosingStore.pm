# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::ClaimLosingStore;

use Carp qw(croak);
use Mojo::Base 'GPForum::Test::IdempotencyStore';
use v5.40;

our $VERSION = '0.001';

# An idempotency store that hands out a token per claim and can lose the
# database after the handler ran (break_done) or when releasing a claim
# (break_failed). A release records the token it was given, last.
has break_done   => 0;
has break_failed => 0;

sub begin ( $self, $key, @ ) {
    $self->SUPER::begin($key) or return 0;
    return "token-$key";
}

sub mark_done ( $self, $key, $result, $token = undef ) {
    croak "database gone\n" if $self->break_done;
    return $self->SUPER::mark_done( $key, $result );
}

sub mark_failed ( $self, $key, $error, $token = undef ) {
    croak "database gone\n" if $self->break_failed;
    $self->SUPER::mark_failed( $key, $error );
    push @{ $self->events }, [ failed => $key, $error, $token ];
    return 1;
}

1;
