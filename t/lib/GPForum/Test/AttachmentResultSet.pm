# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::AttachmentResultSet;

use List::Util qw(any);
use Mojo::Base 'GPForum::Test::TransactionalResultSet';
use v5.40;

use GPForum::Infrastructure::Text qw(has_text);
use GPForum::Test::Query;

use GPForum::Infrastructure::UniqueConflict;
use GPForum::Test::AttachmentRow;
use GPForum::Test::AttachmentSearch;

our $VERSION = '0.001';

has created => sub { return []; };
has rows    => sub { return {}; };
has schema  => undef;                # optional: see _assert_usable

sub create {
    my ( $self, $row ) = @_;

    $self->assert_usable;
    $self->assert_unique_constraints($row);
    my $object = GPForum::Test::AttachmentRow->new( data => $row );
    push @{ $self->created }, $row;
    $self->_store_row( $row, $object );

    return $object;
}

sub check_unique_constraints {
    my ( $self, $row ) = @_;

    $self->_assert_intent_unique($row);
    $self->_assert_link_id_unique($row);
    $self->_assert_link_unique($row);
    $self->_assert_variant_id_unique($row);
    $self->_assert_variant_unique($row);

    return;
}

sub find {
    my ( $self, $id ) = @_;

    $self->assert_usable;

    return $self->rows->{$id};
}

# DBIx::Class's context-proof form of search. lib/ calls it wherever it means a
# resultset, because search itself returns every row in list context.
sub search_rs {
    my ( $self, @arguments ) = @_;

    return $self->search(@arguments);
}

sub search {
    my ( $self, $query, $attrs ) = @_;

    $self->assert_usable;

    my @rows = values %{ $self->rows };
    my %seen;
    @rows = grep { !$seen{ 0 + $_ }++ } @rows;
    @rows = grep { _matches_query( $_, $query || {} ) } @rows;
    @rows =
      GPForum::Test::Query::ordered_rows( \@rows, $attrs,
        \&GPForum::Test::Query::row_column );
    @rows = GPForum::Test::Query::windowed_rows( \@rows, $attrs );

    return GPForum::Test::AttachmentSearch->new( rows => \@rows );
}

sub _store_row {
    my ( $self, $row, $object ) = @_;

    my $key = _row_key($row);

    if ( defined $key ) {
        $self->rows->{$key} = $object;
    }

    return;
}

sub _row_key {
    my ($row) = @_;

    for my $column (
        qw(
        attachment_id
        attachment_link_id
        attachment_variant_id
        event_id
        audit_id
        outbox_id
        post_id
        thread_id
        )
      )
    {
        return $row->{$column} if defined $row->{$column};
    }

    return;
}

sub _matches_query {
    my ( $row, $query ) = @_;

    for my $field ( keys %{$query} ) {
        if ( $field eq '-or' ) {
            return if !any { _matches_query( $row, $_ ) } @{ $query->{-or} };
            next;
        }
        return if !_matches_field( $row, $field, $query->{$field} );
    }

    return 1;
}

sub _matches_field {
    my ( $row, $field, $expected ) = @_;

    my $actual = $row->get_column($field);
    if ( ref $expected eq 'HASH' && exists $expected->{-in} ) {
        my %allowed = map { $_ => 1 } @{ $expected->{-in} };
        return $allowed{$actual} ? 1 : 0;
    }

    return !defined $actual if !defined $expected;

    return defined $actual && $actual eq $expected ? 1 : 0;
}

sub _assert_intent_unique {
    my ( $self, $row ) = @_;

    if ( !_intent_row($row) ) {
        return;
    }

    for my $existing ( @{ $self->created } ) {
        if ( _same_intent( $existing, $row ) ) {
            GPForum::Infrastructure::UniqueConflict->throw(
                _intent_conflict( $existing, $row ) );
        }
    }

    return;
}

sub _intent_row {
    my ($row) = @_;

    if ( !has_text( $row->{attachment_id} ) ) {
        return 0;
    }
    if ( has_text( $row->{attachment_link_id} ) ) {
        return 0;
    }
    if ( has_text( $row->{attachment_variant_id} ) ) {
        return 0;
    }

    return has_text( $row->{object_key} );
}

sub _same_intent {
    my ( $existing, $row ) = @_;

    if ( !_intent_row($existing) ) {
        return 0;
    }
    if ( _same_text( $existing->{attachment_id}, $row->{attachment_id} ) ) {
        return 1;
    }

    return _same_text( $existing->{object_key}, $row->{object_key} );
}

sub _intent_conflict {
    my ( $existing, $row ) = @_;

    if ( _same_text( $existing->{attachment_id}, $row->{attachment_id} ) ) {
        return 'attachments_pkey';
    }

    return 'attachments_object_key_key';
}

sub _assert_link_id_unique {
    my ( $self, $row ) = @_;

    if ( !_link_row($row) ) {
        return;
    }
    if ( _link_id_taken( $self, $row ) ) {
        GPForum::Infrastructure::UniqueConflict->throw('attachment_links_pkey');
    }

    return;
}

sub _assert_link_unique {
    my ( $self, $row ) = @_;

    if ( !_link_row($row) ) {
        return;
    }

    for my $existing ( @{ $self->created } ) {
        if ( _same_link_target( $existing, $row ) ) {
            GPForum::Infrastructure::UniqueConflict->throw(
                'attachment_links_target_key');
        }
    }

    return;
}

sub _link_id_taken {
    my ( $self, $row ) = @_;

    if ( !has_text( $row->{attachment_link_id} ) ) {
        return 0;
    }

    for my $existing ( @{ $self->created } ) {
        if (
            _same_text(
                $existing->{attachment_link_id},
                $row->{attachment_link_id}
            )
          )
        {
            return 1;
        }
    }

    return 0;
}

sub _link_row {
    my ($row) = @_;

    if ( !has_text( $row->{attachment_link_id} ) ) {
        return 0;
    }
    if ( !has_text( $row->{attachment_id} ) ) {
        return 0;
    }
    if ( !has_text( $row->{target_type} ) ) {
        return 0;
    }

    return has_text( $row->{target_id} );
}

sub _same_link_target {
    my ( $existing, $row ) = @_;

    if ( !_link_row($existing) ) {
        return 0;
    }

    return _same_link_scope( $existing, $row );
}

sub _same_link_scope {
    my ( $existing, $row ) = @_;

    if ( !_same_text( $existing->{attachment_id}, $row->{attachment_id} ) ) {
        return 0;
    }
    if ( !_same_text( $existing->{target_type}, $row->{target_type} ) ) {
        return 0;
    }

    return _same_text( $existing->{target_id}, $row->{target_id} );
}

sub _assert_variant_id_unique {
    my ( $self, $row ) = @_;

    if ( !_variant_row($row) ) {
        return;
    }
    if ( _variant_id_taken( $self, $row ) ) {
        GPForum::Infrastructure::UniqueConflict->throw(
            'attachment_variants_pkey');
    }

    return;
}

sub _assert_variant_unique {
    my ( $self, $row ) = @_;

    if ( !_variant_row($row) ) {
        return;
    }

    for my $existing ( @{ $self->created } ) {
        if ( _same_variant_object( $existing, $row ) ) {
            GPForum::Infrastructure::UniqueConflict->throw(
                'attachment_variants_object_key_key');
        }
        if ( _same_variant_key( $existing, $row ) ) {
            GPForum::Infrastructure::UniqueConflict->throw(
                'attachment_variants_variant_key');
        }
    }

    return;
}

sub _variant_id_taken {
    my ( $self, $row ) = @_;

    if ( !has_text( $row->{attachment_variant_id} ) ) {
        return 0;
    }

    for my $existing ( @{ $self->created } ) {
        if (
            _same_text(
                $existing->{attachment_variant_id},
                $row->{attachment_variant_id}
            )
          )
        {
            return 1;
        }
    }

    return 0;
}

sub _variant_row {
    my ($row) = @_;

    if ( !has_text( $row->{attachment_variant_id} ) ) {
        return 0;
    }
    if ( !has_text( $row->{attachment_id} ) ) {
        return 0;
    }

    return has_text( $row->{variant_type} );
}

sub _same_variant_object {
    my ( $existing, $row ) = @_;

    if ( !_variant_row($existing) ) {
        return 0;
    }

    return _same_text( $existing->{object_key}, $row->{object_key} );
}

sub _same_variant_key {
    my ( $existing, $row ) = @_;

    if ( !_variant_row($existing) ) {
        return 0;
    }
    if ( !_same_text( $existing->{attachment_id}, $row->{attachment_id} ) ) {
        return 0;
    }

    return _same_text( $existing->{variant_type}, $row->{variant_type} );
}

sub _same_text {
    my ( $stored, $candidate ) = @_;

    $stored    = defined $stored    ? $stored    : q{};
    $candidate = defined $candidate ? $candidate : q{};

    return $stored eq $candidate ? 1 : 0;
}

1;
