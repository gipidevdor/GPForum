# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Admin::AuditReview;

use Const::Fast;
use MIME::Base64 qw(decode_base64url encode_base64url);
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow::Audit;

use GPForum::Infrastructure::CalendarDate;
use GPForum::Infrastructure::Id;
use GPForum::Service::Forum::PageWindow;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $DEFAULT_LIMIT => 50;
const my $UUID          => GPForum::Infrastructure::Id->uuid_pattern;
const my $WORD          => qr/\A [[:alnum:]_.:-]{1,100} \z/msx;
const my @FILTERS =>
  qw(actor_id action target_type target_id correlation_id from until);
const my %UUID_FILTER  => map { $_ => 1 } qw(actor_id target_id correlation_id);
const my %DAY_FILTER   => map { $_ => 1 } qw(from until);
const my $CURSOR_PARTS => 2;

__PACKAGE__->requires(qw(schema));

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each read is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(qw(recent page));

# The dashboard's recent activity.
async sub recent_p ( $self, $options, $context = undef ) {
    return _audit_rows(
        await $self->_functions->rows_p(
            'admin_audit_recent',
            { row_limit => $options->{limit} || $DEFAULT_LIMIT }, $context
        )
    );
}

# One page, newest first, read one row past the page to learn whether there
# is another, and the cursor of the next page if there is one.
async sub page_p ( $self, $filters, $page, $context = undef ) {
    my $limit = $page->{limit} || $DEFAULT_LIMIT;
    my @rows  = @{
        _audit_rows(
            await $self->_functions->rows_p(
                'admin_audit_page',
                {
                    filters   => $filters,
                    after     => scalar _decode_cursor( $page->{after} ),
                    row_limit => $limit + 1
                },
                $context
            )
        )
    };
    my $next;
    if ( @rows > $limit ) {
        splice @rows, $limit;
        $next = _cursor( $rows[-1] );
    }

    return { rows => \@rows, next_cursor => $next };
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

sub _cursor ($row) {
    return encode_base64url(
        join q{|},
        column_of( $row, 'created_at' ),
        column_of( $row, 'audit_id' )
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

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'the audit viewer needs the PostgreSQL function layer' );
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

=head2 recent_p

Takes a hash reference of options, of which only C<limit> is read (50 when
missing), and an optional query context. Resolves with the newest audit
rows, for the dashboard (C<api.admin_audit_recent>). C<recent> is its
blocking twin.

=head2 filters

Splits request parameters into filters to apply and values rejected because
they do not have the column's shape (a uuid, a C<YYYY-MM-DD> date, a word).

=head2 page_p

Takes the filters L</filters> accepted, a page (C<limit>, and C<after>, the
cursor of the page before) and an optional query context. Resolves with one
page of rows, newest first, and the C<next_cursor>, or undef on the last
page (C<api.admin_audit_page>). C<page> is its blocking twin.

=head1 DIAGNOSTICS

Invalid filter values are returned as errors, never queried; an invalid cursor
is ignored. Throws L<GPForum::X::Unavailable> without the function layer.

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
