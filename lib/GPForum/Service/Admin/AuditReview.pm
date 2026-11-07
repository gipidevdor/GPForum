# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Admin::AuditReview;

use Const::Fast;
use MIME::Base64 qw(decode_base64url encode_base64url);
use Scalar::Util qw(blessed);
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Row qw(rows_in);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow::Audit;

use GPForum::Infrastructure::CalendarDate;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::Keyset;
use GPForum::Service::Forum::PageWindow;

our $VERSION = '0.001';

const my $DEFAULT_LIMIT => 50;
const my $UUID          => GPForum::Infrastructure::Id->uuid_pattern;
const my $WORD          => qr/\A [[:alnum:]_.:-]{1,100} \z/msx;
const my @FILTERS =>
  qw(actor_id action target_type target_id correlation_id from until);
const my %UUID_FILTER  => map { $_ => 1 } qw(actor_id target_id correlation_id);
const my %DAY_FILTER   => map { $_ => 1 } qw(from until);
const my $CURSOR_PARTS => 2;

# What an entry of the audit viewer carries: the columns of
# api.admin_audit_entry_v1, which the resultset path selects too, so the two
# paths read the same row (the chain columns of ADR 0156 are not shown).
const my @ENTRY_COLUMNS => qw(
  audit_id action schema_version actor_id target_type target_id
  correlation_id previous_hash record_hash metadata created_at
);

__PACKAGE__->requires(qw(schema));

# The dashboard's recent activity.
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

sub recent ( $self, $options ) {
    if ( $self->functions ) {
        return _audit_rows(
            $self->functions->rows( _recent_values($options) ) );
    }
    return [
        _rows(
            $self->schema->resultset('AuditLog')->search_rs(
                {},
                {
                    columns  => [@ENTRY_COLUMNS],
                    order_by => _newest_first(),
                    rows     => $options->{limit} || $DEFAULT_LIMIT,
                }
            )
        )
    ];
}

# The dashboard's and the audit viewer's reads on the worker's pooled
# asynchronous connections, not a forked child with a connection of its own.
async sub recent_p ( $self, $options, $context = undef ) {
    return $self->recent($options) if !$self->functions;
    return _audit_rows(
        await $self->functions->rows_p( _recent_values($options), $context ) );
}

async sub page_p ( $self, $filters, $page, $context = undef ) {
    return $self->page( $filters, $page ) if !$self->functions;
    my $limit = $page->{limit} || $DEFAULT_LIMIT;
    return _paged(
        $limit,
        @{
            _audit_rows(
                await $self->functions->rows_p(
                    _page_values( $filters, $page, $limit ), $context
                )
            )
        }
    );
}

sub _recent_values ($options) {
    return ( 'admin_audit_recent',
        { row_limit => $options->{limit} || $DEFAULT_LIMIT } );
}

sub _page_values ( $filters, $page, $limit ) {
    return (
        'admin_audit_page',
        {
            filters   => $filters,
            after     => scalar _decode_cursor( $page->{after} ),
            row_limit => $limit + 1
        }
    );
}

sub _audit_rows ($rows) {
    return [ map { GPForum::Infrastructure::ResultRow::Audit->from($_) }
          @{$rows} ];
}

# The audit viewer's filters, as ADR 0079 requires them: actor, action,
# target, correlation id and a UTC date window. Returns the filters to apply
# and the ones that could not be: a value that is not a uuid never reaches a
# uuid column, where PostgreSQL would reject the whole query.
sub filters ( $class, $input ) {
    my ( %filters, %errors );
    for my $name (@FILTERS) {
        my $value = $input->{$name};
        next if !defined $value || !length $value;

        if ( _acceptable( $name, $value ) ) {
            $filters{$name} = $value;
        }
        else {
            $errors{$name} = $value;
        }
    }

    return { filters => \%filters, errors => \%errors };
}

# A uuid, a day that exists (the 30th of February reached PostgreSQL and
# failed the page), or a word.
sub _acceptable ( $name, $value ) {
    return $value =~ $UUID ? 1 : 0 if exists $UUID_FILTER{$name};
    return GPForum::Infrastructure::CalendarDate->is_day($value)
      if exists $DAY_FILTER{$name};

    return $value =~ $WORD ? 1 : 0;
}

# One page, newest first, and the cursor of the next page if there is one.
sub page ( $self, $filters, $page ) {
    my $limit = $page->{limit} || $DEFAULT_LIMIT;
    return _paged(
        $limit,
        $self->functions
        ? @{
            _audit_rows(
                $self->functions->rows(
                    _page_values( $filters, $page, $limit )
                )
            )
          }
        : _rows( $self->page_resultset( $filters, $page ) )
    );
}

sub _paged ( $limit, @rows ) {
    my $next;
    if ( @rows > $limit ) {
        splice @rows, $limit;
        $next = _cursor( $rows[-1] );
    }

    return { rows => \@rows, next_cursor => $next };
}

# The resultset page executes, one row past the page to learn whether there
# is another. Public so the plan tests EXPLAIN what actually runs.
sub page_resultset ( $self, $filters, $page ) {
    my $query = _query($filters);
    if ( my $after = _decode_cursor( $page->{after} ) ) {
        GPForum::Infrastructure::Keyset->after(
            $query,
            {
                direction => 'desc',
                id        => [ 'audit_id',   $after->{audit_id} ],
                sort      => [ 'created_at', $after->{created_at} ],
            }
        );
    }

    return $self->schema->resultset('AuditLog')->search_rs(
        $query,
        {
            columns  => [@ENTRY_COLUMNS],
            order_by => _newest_first(),
            rows     => ( $page->{limit} || $DEFAULT_LIMIT ) + 1,
        }
    );
}

sub _query ($filters) {
    my %query =
      map  { $_ => $filters->{$_} }
      grep { defined $filters->{$_} }
      qw(actor_id action target_type target_id correlation_id);
    my ( $from, $until ) = @{$filters}{qw(from until)};
    my %window;
    if ( defined $from ) {
        $window{q{>=}} = "${from}T00:00:00Z";
    }
    if ( defined $until ) {
        $window{q{<=}} = "${until}T23:59:59.999999Z";
    }
    if (%window) {
        $query{created_at} = \%window;
    }

    return \%query;
}

sub _newest_first {
    return [ { -desc => 'created_at' }, { -desc => 'audit_id' } ];
}

sub _cursor ($row) {
    return encode_base64url(
        join q{|},
        _column( $row, 'created_at' ),
        _column( $row, 'audit_id' )
    );
}

# A cursor that does not decode to a timestamp that exists and a uuid is
# ignored, and the first page is shown, rather than sent to PostgreSQL: one
# that only began with a day reached it and failed the page.
sub _decode_cursor ($cursor) {
    return if !defined $cursor || !length $cursor;

    my ( $created_at, $audit_id ) = split /[|]/msx,
      decode_base64url($cursor), $CURSOR_PARTS;
    return
      if !GPForum::Service::Forum::PageWindow->acceptable_cursor( $created_at,
        $audit_id, 'timestamp' );

    return { created_at => $created_at, audit_id => $audit_id };
}

sub _column ( $row, $name ) {
    return ref $row eq 'HASH' ? $row->{$name} : $row->get_column($name);
}

# The rows as the function path answers them: audit rows whose metadata is
# the decoded hash, where a DBIx::Class row's get_column is the jsonb's text.
sub _rows ($search) {
    return map { _audit_row($_) } rows_in($search);
}

sub _audit_row ($row) {
    return $row if !blessed $row || !$row->can('get_inflated_columns');

    return GPForum::Infrastructure::ResultRow::Audit->from(
        { $row->get_inflated_columns } );
}

1;

__END__

=head1 NAME

GPForum::Service::Admin::AuditReview - Read the audit log for the console.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $checked = GPForum::Service::Admin::AuditReview->filters(\%params);
    my $page    = $review->page( $checked->{filters}, { after => $cursor } );

=head1 DESCRIPTION

The audit viewer's reads (ADR 0079): filtering by actor, action, target,
correlation id and a UTC date window, newest first, a page at a time with a
keyset cursor. Audit rows are never written here.

=head1 SUBROUTINES/METHODS

=head2 recent

The newest rows, for the dashboard.

=head2 recent_p

L</recent> as a promise, with an optional query context last, read on the
worker's pooled asynchronous connections. Without SQL functions it answers
the blocking read.

=head2 filters

Splits request parameters into filters to apply and values rejected because
they do not have the column's shape (a uuid, a C<YYYY-MM-DD> date, a word).

=head2 page

One page of rows and the C<next_cursor>, or undef on the last page.

=head2 page_p

L</page> as a promise, with an optional query context last, read on the
worker's pooled asynchronous connections. Without SQL functions it answers
the blocking read.

=head2 page_resultset

The resultset C<page> executes.

=head1 DIAGNOSTICS

Invalid filter values are returned as errors, never queried; an invalid cursor
is ignored.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Const::Fast>, L<MIME::Base64>, L<GPForum::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Dates are UTC days.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
