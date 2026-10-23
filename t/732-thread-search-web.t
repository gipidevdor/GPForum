# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use lib 'lib';
use lib 't/lib';
use Const::Fast;
use Mojo::Util qw(monkey_patch);
use Test::Mojo;
use Test::More;
use GPForum::Test::ForumWebServices;
our $VERSION = '0.001';
const my $HTTP_OK        => 200;
const my $HTTP_NOT_FOUND => 404;
const my $READABLE       => '018f2000-0001-7000-8000-000000000001';
const my $UNREADABLE     => '018f2000-0001-7000-8000-000000000002';
my $searches = 0;
my $find     = GPForum::Test::ForumWebServices->can('find_thread');
my $ranked   = GPForum::Test::ForumWebServices->can('ranked_search');
monkey_patch 'GPForum::Test::ForumWebServices', 'find_thread',
  sub ( $self, $id, @args ) {
    return $find->( $self, $id eq $READABLE ? 'thread-1' : $id, @args );
  };
monkey_patch 'GPForum::Test::ForumWebServices', 'ranked_search', sub (@args) {
    $searches++;
    return $ranked->(@args);
};
my $test     = Test::Mojo->new('GPForum');
my $services = GPForum::Test::ForumWebServices->new;
for my $helper (
    qw(gp_thread_detail_reader gp_search_service gp_rate_limiter gp_suspension_store)
  )
{
    $test->app->helper( $helper => sub { return $services; } );
}
$test->get_ok('/search?q=reply&thread_id=invalid')->status_is($HTTP_NOT_FOUND);
$test->get_ok( '/search?q=reply&thread_id=' . $UNREADABLE )
  ->status_is($HTTP_NOT_FOUND);
is( $searches, 0,
    'invalid and inaccessible targets never run an unscoped search' );
$test->get_ok( '/search?q=reply&thread_id=' . $READABLE )->status_is($HTTP_OK);
$test->element_exists(
    'input[type="hidden"][name="thread_id"][value="' . $READABLE . '"]' );
$test->element_exists(
    'a[href="/t/' . $READABLE . '?post=post-1#post-post-1"]' );
is( $searches, 1, 'readable target runs the scoped search once' );
done_testing();
1;
