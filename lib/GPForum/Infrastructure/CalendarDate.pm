# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::CalendarDate;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my $DAY        => qr/(\d{4}) - (\d{2}) - (\d{2})/amsx;
const my $TIME       => qr/(\d{2}) : (\d{2}) : (\d{2}) (?: [.] \d{1,6} )?/amsx;
const my $ZONE       => qr/(?: Z | [+-] (\d{2}) (?: :? (\d{2}) )? )?/amsx;
const my @MONTH_DAYS => ( 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 );
const my $FEBRUARY   => 2;
const my $LEAP_DAYS  => 29;
const my $LEAP_EVERY => 4;
const my $CENTURY    => 100;
const my $LEAP_CENTURY => 400;
const my $LAST_HOUR    => 23;
const my $LAST_MINUTE  => 59;
const my $LAST_ZONE    => 15;

# A day the calendar has, written YYYY-MM-DD: what PostgreSQL takes as a
# date. A day of the right shape that does not exist -- the 30th of
# February, a thirteenth month -- failed the request there.
sub is_day ( $class, $text ) {
    return 0 if !defined $text;
    my @day = $text =~ /\A $DAY \z/amsx or return 0;

    return _exists(@day);
}

# A timestamp as PostgreSQL or ISO 8601 writes it whose day, time and zone
# exist.
sub is_timestamp ( $class, $text ) {
    return 0 if !defined $text;
    my ( $year, $month, $day, $hours, $minutes, $seconds, $zone, $zone_minutes )
      = $text =~ /\A $DAY [T ] $TIME $ZONE \z/amsx
      or return 0;

    return
         _exists( $year, $month, $day )
      && $hours <= $LAST_HOUR
      && $minutes <= $LAST_MINUTE
      && $seconds <= $LAST_MINUTE
      && ( $zone         // 0 ) <= $LAST_ZONE
      && ( $zone_minutes // 0 ) <= $LAST_MINUTE ? 1 : 0;
}

sub _exists ( $year, $month, $day ) {
    return 0 if $year < 1 || $month < 1 || $month > @MONTH_DAYS || $day < 1;
    my $month_days = $MONTH_DAYS[ $month - 1 ];
    if ( $month == $FEBRUARY && _leap($year) ) {
        $month_days = $LEAP_DAYS;
    }

    return $day <= $month_days ? 1 : 0;
}

sub _leap ($year) {
    return $year % $LEAP_CENTURY == 0
      || ( $year % $LEAP_EVERY == 0 && $year % $CENTURY != 0 );
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::CalendarDate - Whether a day or a timestamp from a request exists.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Infrastructure::CalendarDate->is_day('2026-02-28');    # 1
    GPForum::Infrastructure::CalendarDate->is_day('2026-02-30');    # 0
    GPForum::Infrastructure::CalendarDate->is_timestamp(
        '2026-10-31T23:59:59.5Z');                                 # 1

=head1 DESCRIPTION

A value from a URL that PostgreSQL will read as a date or a timestamp is
checked here first: one of the right shape that names no day, or no time
of one, made PostgreSQL refuse the statement and the request answer 500.
The audit viewer's date window and every list's cursor
(L<GPForum::Service::Forum::PageWindow>) ask it.

=head1 SUBROUTINES/METHODS

=head2 is_day

Takes a text. Returns 1 when it is C<YYYY-MM-DD> in ASCII digits and that
day exists in the Gregorian calendar (year 1 onwards), 0 otherwise.

=head2 is_timestamp

Takes a text. Returns 1 when it is a day as for L</is_day>, a C<T> or a
space, C<HH:MM:SS> with up to six decimals, and an optional C<Z> or
C<+HH>, C<+HHMM> or C<+HH:MM> offset, with the hour at most 23, minutes
and seconds at most 59, the offset's hours at most 15 and its minutes at
most 59; 0 otherwise.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Const::Fast>, L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A leap second is refused: PostgreSQL would take it as the next minute, and
no value this application writes has one.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
