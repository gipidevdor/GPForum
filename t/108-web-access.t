# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use lib 'lib';
use lib 't/lib';

use GPForum::Test::ResponderController;
use GPForum::Web::Access;
use Test::More;

our $VERSION = '0.001';

my $controller = GPForum::Test::ResponderController->new(
    accept_header   => 'application/json',
    session_user_id => 'user-1',
);
my $access = GPForum::Web::Access->new;

ok( !$access->csrf_invalid($controller),
    'csrf_invalid is false when the token is present' );

$controller->csrf_error(1);
ok( $access->csrf_invalid($controller),
    'csrf_invalid is true when CSRF protection reports an error' );
$controller->csrf_error(0);

is( $access->user_id($controller),
    'user-1', 'user_id reads the cookie-session identity' );
ok( $access->wants_json($controller),
    'wants_json follows the request preference' );
ok( $access->has_text('it'),   'has_text accepts a non-empty string' );
ok( !$access->has_text(undef), 'has_text rejects undef' );
ok( !$access->has_text(q{}),   'has_text rejects an empty string' );

is( $access->safe_return_to('/t/thread-1?page=2'),
    '/t/thread-1?page=2', 'safe_return_to keeps a path of this site' );
is( $access->safe_return_to('//evil.test/'),
    undef, 'and refuses a protocol-relative one' );
is( $access->safe_return_to('https://evil.test/'), undef, 'another origin' );
is( $access->safe_return_to("/t/thread-1\r\nSet-Cookie: a=b"),
    undef, 'a header-splitting one' );
is( $access->safe_return_to('/\\evil.test'), undef, 'a backslash' );
is( $access->safe_return_to('t/thread-1'),   undef, 'a relative one' );
is( $access->safe_return_to(q{}),            undef, 'nothing' );
is( $access->safe_return_to(undef),          undef, 'and undef' );

done_testing();

1;
