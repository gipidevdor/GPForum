# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';

use GPForum::Infrastructure::CalendarDate;
use GPForum::Service::Forum::PageWindow;

our $VERSION = '0.001';

# A day or a time from a URL that PostgreSQL would read: one of the right
# shape that does not exist failed the request there (the audit viewer's
# date window, every list's cursor).

const my $DATES => 'GPForum::Infrastructure::CalendarDate';
const my $ID    => '018f1000-0000-7000-8000-000000000001';

for my $case (
    [ '2026-02-28', 1, 'an ordinary day' ],
    [ '2024-02-29', 1, 'the 29th of February of a leap year' ],
    [ '2000-02-29', 1, 'and of a fourth century' ],
    [ '2100-02-29', 0, 'not of another century' ],
    [ '2026-02-30', 0, 'the 30th of February' ],
    [ '2026-04-31', 0, 'the 31st of a short month' ],
    [ '2026-13-01', 0, 'a thirteenth month' ],
    [ '2026-00-10', 0, 'a month nought' ],
    [ '0000-01-01', 0, 'a year nought' ],
    [ '2026-1-01',  0, 'a month of one digit' ],
    [ "\N{ARABIC-INDIC DIGIT TWO}026-01-01", 0, 'digits beyond ASCII' ],
    [ undef,                                 0, 'nothing' ],
  )
{
    my ( $text, $exists, $what ) = @{$case};
    is( $DATES->is_day($text), $exists, "is_day: $what" );
}

for my $case (
    [ '2026-10-31T23:59:59Z',             1, 'a UTC time' ],
    [ '2026-10-31 23:59:59.123456+02:00', 1, 'with decimals and an offset' ],
    [ '2026-10-31T10:00:00+0530',         1, 'an offset without a colon' ],
    [ '2026-10-31T10:00:00+15:59',        1, 'the last valid offset minute' ],
    [ '2026-10-31T10:00:00-0030',         1, 'a negative fractional offset' ],
    [ '2026-10-31T10:00:00+02',           1, 'an offset in whole hours' ],
    [ '2026-10-31T10:00:00',              1, 'no zone' ],
    [ '2026-02-30T10:00:00Z',             0, 'a day that does not exist' ],
    [ '2026-10-31T24:00:00Z',             0, 'the 24th hour' ],
    [ '2026-10-31T23:60:00Z',             0, 'the 60th minute' ],
    [ '2026-10-31T23:59:60Z',             0, 'a leap second' ],
    [ '2026-10-31T10:00:00+16',           0, 'an offset past 15 hours' ],
    [ '2026-10-31T10:00:00+00:60',        0, 'the 60th offset minute' ],
    [ '2026-10-31T10:00:00-0060',         0, 'an invalid compact offset' ],
    [
        '2026-10-31T10:00:00+15:99', 0,
        'invalid minutes at the last offset hour'
    ],
    [ '2026-10-31', 0, 'a day alone' ],
  )
{
    my ( $text, $exists, $what ) = @{$case};
    is( $DATES->is_timestamp($text), $exists, "is_timestamp: $what" );
}

ok(
    GPForum::Service::Forum::PageWindow->acceptable_cursor(
        '2026-10-31T10:00:00Z', $ID, 'timestamp'
    ),
    'a cursor at a time that exists is a cursor'
);
ok(
    !GPForum::Service::Forum::PageWindow->acceptable_cursor(
        '2026-02-30T10:00:00Z', $ID, 'timestamp'
    ),
    'one at a time that does not is none, and shows the first page'
);
ok( GPForum::Service::Forum::PageWindow->acceptable_cursor( '12', $ID ),
    'a position is still one' );

for my $offset (qw(+00:60 -0060 +15:99)) {
    ok(
        !GPForum::Service::Forum::PageWindow->acceptable_cursor(
            "2026-10-31T10:00:00$offset", $ID, 'timestamp'
        ),
        "an impossible $offset offset is not passed to a query"
    );
}

done_testing();

1;
