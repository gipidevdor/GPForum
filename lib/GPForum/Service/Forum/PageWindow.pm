# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::PageWindow;

use Const::Fast;
use GPForum::Infrastructure::Id;
use GPForum::X::Argument;
use MIME::Base64 qw(decode_base64url encode_base64url);
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my $DEFAULT_LIMIT => 25;
const my $MAX_LIMIT     => 100;
const my $MIN_LIMIT     => 1;
const my $CURSOR_PARTS  => 2;

# A position, or a timestamp as PostgreSQL or ISO 8601 writes it. Each list
# sorts by one of them and binds the cursor as that type, so a plan says
# which (sort => 'position' or 'timestamp'); a cursor of the other kind is
# no cursor. Both passed when the kind was not said, and a timestamp
# reached a thread page's bigint parameter, which failed the request.
const my $POSITION  => qr{\d{1,18}}msx;
const my $DAY       => qr{\d{4} - \d\d - \d\d}msx;
const my $TIME      => qr{\d\d : \d\d : \d\d (?: [.] \d{1,6} )?}msx;
const my $ZONE      => qr{Z | [+-] \d\d (?: :? \d\d )?}msx;
const my $TIMESTAMP => qr{$DAY [T ] $TIME (?: $ZONE )?}msx;
const my %SORT_VALUE => (
    position  => qr{\A $POSITION \z}msxa,
    timestamp => qr{\A $TIMESTAMP \z}msxa,
    any       => qr{\A (?: $POSITION | $TIMESTAMP ) \z}msxa,
);

# Seek by ordinal using the same indexed keyset as ordinary pagination.
# The maximal UUID excludes every row at the preceding position.
sub cursor_at_position ( $class, $position ) {
    return undef
      if !defined $position || $position !~ /\A [1-9][[:digit:]]{0,17} \z/amsx;
    return encode_base64url(
        ( $position - 1 ) . '|ffffffff-ffff-ffff-ffff-ffffffffffff' );
}

sub plan ( $self, $input ) {
    my $limit = _bounded_limit( $input->{limit} );
    my $after = _decode_cursor( $input->{after}, $input->{sort} );

    return {
        limit      => $limit,
        fetch_rows => $limit + 1,
        after      => $after,
    };
}

sub page ( $self, $rows, $limit, $cursor_columns ) {
    my @items    = @{$rows};
    my $has_next = @items > $limit ? 1 : 0;

    if ($has_next) {
        pop @items;
    }

    return {
        items       => \@items,
        has_next    => $has_next,
        next_cursor => $has_next
        ? _encode_cursor( $items[-1], $cursor_columns )
        : undef,
    };
}

sub _bounded_limit ($requested) {
    return $DEFAULT_LIMIT if !defined $requested;
    return $DEFAULT_LIMIT if $requested !~ /\A [[:digit:]]+ \z/amsx;
    return $MIN_LIMIT     if $requested < $MIN_LIMIT;
    return $MAX_LIMIT     if $requested > $MAX_LIMIT;

    return int $requested;
}

sub _encode_cursor ( $row, $columns ) {
    return undef if !$row;

    return encode_base64url( join q{|},
        map { $row->get_column($_) } @{$columns} );
}

# A cursor comes from the URL: only a timestamp or a position, and a uuid,
# may reach SQL. Anything else shows the first page. It used to reach
# PostgreSQL -- `?after=anything` failed the request on an invalid
# timestamp, and anyone could fill the error log that way.
sub acceptable_cursor ( $class, $sort_value, $id, $sort = undef ) {
    return 0 if !GPForum::Infrastructure::Id->is_uuid($id);
    return 0 if !defined $sort_value;

    my $kind = $SORT_VALUE{ $sort // 'any' } // GPForum::X::Argument->throw(
        message => "a list sorts by position or timestamp, not $sort" );

    return $sort_value =~ $kind ? 1 : 0;
}

sub _decode_cursor ( $cursor, $sort = undef ) {
    return undef if !defined $cursor || !length $cursor;

    my $decoded;
    try { $decoded = decode_base64url($cursor); }
    catch ($error) { return undef; };
    return undef if !defined $decoded;

    my @parts = split /[|]/msx, $decoded, $CURSOR_PARTS;
    return undef if @parts != $CURSOR_PARTS;
    return undef if !__PACKAGE__->acceptable_cursor( @parts, $sort );

    return {
        sort_value => $parts[0],
        id         => $parts[1],
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::PageWindow - Page size, keyset cursor and next-page cursor for a listing.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $window = GPForum::Service::Forum::PageWindow->new;
    my $plan   = $window->plan( { limit => $limit, after => $after } );

    # Fetch $plan->{fetch_rows} rows past $plan->{after}, then:
    my $page = $window->page( \@rows, $plan->{limit},
        [qw(created_at item_id)] );
    # { items => [...], has_next => 1, next_cursor => '...' }

=head1 DESCRIPTION

The shared arithmetic of a keyset-paged list. C<plan> bounds the requested
page size and decodes the C<after> cursor from the URL; the reader then
fetches one row more than the page, and C<page> uses that extra row to tell
whether there is a next page and, if so, mints its cursor from the last row
kept.

A cursor is base64url of C<sort_value|id>. Because it comes from the URL,
only a position or a timestamp and a uuid may reach SQL; anything else is
treated as no cursor, so the first page is shown. A malformed C<?after=>
used to reach PostgreSQL and fail the request on an invalid timestamp.

=head1 SUBROUTINES/METHODS

=head2 cursor_at_position

Class method. Takes a positive post position and returns the opaque keyset
cursor immediately before it, or undef for invalid input. Readers still
apply the thread's visibility and permission checks to the resulting page.

=head2 plan

Takes a hash reference with optional C<limit> and C<after>. Returns
C<< { limit, fetch_rows, after } >>: C<limit> is 25 when missing or not a
whole number, at least 1 and at most 100; C<fetch_rows> is C<limit + 1>;
C<after> is C<< { sort_value, id } >> decoded from the cursor, or undef
when there is none or it is not acceptable.

=head2 page

Takes the fetched rows (an array reference), the page limit and the cursor
columns (an array reference of column names). Returns
C<< { items, has_next, next_cursor } >>: when there are more rows than the
limit, the extra row is dropped, C<has_next> is 1 and C<next_cursor> encodes
the cursor columns of the last item kept, read with C<get_column>;
otherwise C<has_next> is 0 and C<next_cursor> undef.

=head2 acceptable_cursor

Class method. Takes a sort value and an id. Returns 1 when the id is a uuid
and the sort value is a position (up to 18 digits) or a timestamp as
PostgreSQL or ISO 8601 writes it; 0 otherwise.

=head1 DIAGNOSTICS

None. An undecodable or unacceptable cursor is ignored rather than
reported; C<page> dies only if a row cannot C<get_column>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::Id>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
