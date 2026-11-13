# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::Embedding;
use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;
use GPForum::Infrastructure::Embedding;
our $VERSION = '0.001';
const my $DIMENSIONS => 384;
has model_key       => 'fixture-v1';
has before_embed    => undef;
has fail            => 0;
has calls           => 0;
has vector_override => undef;

sub embed ( $self, $text ) {
    $self->calls( $self->calls + 1 );
    return $self->vector_override if defined $self->vector_override;
    if ( $self->fail )         { die "fixture embedding unavailable\n"; }
    if ( $self->before_embed ) { $self->before_embed->(); }
    my @vector = (0) x $DIMENSIONS;
    $vector[ $text =~ /zoologia/msx ? 1 : 0 ] = 1;
    return GPForum::Infrastructure::Embedding->vector_literal( \@vector );
}
1;
