# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::OutboxCreateResultSet;

use Carp qw(croak);
use Mojo::Base 'GPForum::Test::TransactionalResultSet';
use v5.40;

use GPForum::Infrastructure::Text qw(has_text);
use GPForum::Infrastructure::UniqueConflict;

our $VERSION = '0.001';

has created => sub { return []; };

# A store failure that is not a unique violation, so a caller cannot mistake
# it for a replay it is allowed to absorb.
has fail_error  => undef;
has find_misses => 0;
has rows        => sub { return {}; };
has schema      => undef;

sub create {
    my ( $self, $row ) = @_;

    $self->assert_usable;
    if ( defined $self->fail_error ) {
        croak $self->fail_error;
    }
    $self->assert_unique_constraints($row);
    $self->rows->{ _source_key($row) } = $row;
    push @{ $self->created }, $row;

    return $row;
}

sub find {
    my ( $self, $query ) = @_;

    $self->assert_usable;
    if ( $self->find_misses ) {
        $self->find_misses( $self->find_misses - 1 );
        return undef;
    }

    return $self->rows->{ _source_key($query) };
}

sub check_unique_constraints {
    my ( $self, $row ) = @_;

    $self->_assert_letter_id_unique($row);
    $self->_assert_source_unique($row);

    return;
}

sub _assert_letter_id_unique {
    my ( $self, $row ) = @_;

    my $letter_id = $row->{dead_letter_id};
    if ( !has_text($letter_id) ) {
        return;
    }
    if ( _letter_id_taken( $self, $letter_id ) ) {
        GPForum::Infrastructure::UniqueConflict->throw('dead_letters_pkey');
    }

    return;
}

sub _letter_id_taken {
    my ( $self, $letter_id ) = @_;

    for my $existing ( @{ $self->created } ) {
        if ( _same_text( $existing->{dead_letter_id}, $letter_id ) ) {
            return 1;
        }
    }

    return 0;
}

sub _assert_source_unique {
    my ( $self, $row ) = @_;

    my $key = _source_key($row);
    if ( $key && $self->rows->{$key} ) {
        GPForum::Infrastructure::UniqueConflict->throw(
            'idx_dead_letters_source_unique');
    }

    return;
}

sub _source_key {
    my ($row) = @_;

    my $source_id    = $row->{source_id};
    my $source_table = $row->{source_table};
    if ( !defined $source_id || !defined $source_table ) {
        return q{};
    }

    return join q{:}, $source_table, $source_id;
}

sub _same_text {
    my ( $expected, $actual ) = @_;

    return ( $expected || q{} ) eq ( $actual || q{} ) ? 1 : 0;
}

1;
