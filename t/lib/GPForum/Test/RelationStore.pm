# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RelationStore;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my $MAXIMUM => 500;

# ADR 0130: the member relation store as the controllers see it. It records
# the writes and answers what the test sets.
has answer  => sub { return { ok => 1, status => 'ok', relation => {} }; };
has calls   => sub { return []; };
has listed  => sub { return []; };
has between => undef;    # optional: the reader holds no relation

sub maximum_relations ($self) { return $MAXIMUM; }

sub set_relation ( $self, $input ) {
    push @{ $self->calls }, [ set => $input ];

    return $self->answer;
}

sub remove_relation ( $self, $input ) {
    push @{ $self->calls }, [ remove => $input ];

    return { ok => 1, status => 'ok', removed => 1 };
}

sub list_for_user ( $self, $ ) { return $self->listed; }

sub relation_between ( $self, @ ) { return $self->between; }

1;
