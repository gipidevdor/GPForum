# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use utf8;
use lib 'lib';
use GPForum::Service::Forum::PageWindow;
use GPForum::Controller::Forum;
use Mojo::Transaction::HTTP;
use Test::More;
our $VERSION = '0.001';
my $window = GPForum::Service::Forum::PageWindow->new;

for my $position (qw(1 25 100000 999999999999999999)) {
    my $cursor = $window->cursor_at_position($position);
    my $after  = $window->plan( { after => $cursor } )->{after};
    is(
        $after->{sort_value},
        $position - 1,
        'seek starts strictly after the preceding ordinal'
    );
    is(
        $after->{id},
        'ffffffff-ffff-ffff-ffff-ffffffffffff',
        'all ids at the preceding ordinal are skipped'
    );
}
for my $invalid ( undef, q{}, qw(0 -1 01 1.5 1e2 1000000000000000000),
    '٢٥', '25 OR 1=1' )
{
    ok(
        !defined $window->cursor_at_position($invalid),
        'invalid or oversized ordinal never reaches SQL'
    );
}
for my $query ( 'at=25', 'post=018f2000-0001-7000-8000-000000000001' ) {
    my $tx = Mojo::Transaction::HTTP->new;
    $tx->req->url->query($query);
    my $controller = GPForum::Controller::Forum->new( tx => $tx );
    ok(
        !defined $controller->_thread_cache_options('thread-1'),
        'deep navigation cannot reuse or populate the first-page public cache'
    );
}
done_testing();
1;
