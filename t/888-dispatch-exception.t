# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use Test::More;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';

our $VERSION = '0.001';

const my $HTTP_SERVER_ERROR => 500;

# Request preparation is asynchronous, so dispatch runs a tick after
# Mojolicious's own exception guard has returned. A die in a plain action,
# a bridge or a hook is a programming error: it answers 500 and is logged as
# the exception it is, not as a 503 "request preparation failed".
my $test = Test::Mojo->new('GPForum');
my @logged;
$test->app->log->on(
    message => sub ( $, $level, @lines ) {
        push @logged, join q{ }, $level, @lines;
    }
);
$test->app->routes->get( '/__dispatch-die' => sub ($) { die "boom\n" } );
my $bridge = $test->app->routes->under(
    '/__bridge-die' => sub ($) {
        die "bridge boom\n";
    }
);
$bridge->get(
    q{/} => sub ($controller) { $controller->render( text => 'no' ) } );

for my $path ( '/__dispatch-die', '/__bridge-die' ) {
    @logged = ();
    $test->get_ok($path)->status_is($HTTP_SERVER_ERROR);
    ok(
        !( grep { /request preparation failed/msx } @logged ),
        "$path is not reported as a preparation failure"
    );
}

done_testing();

1;
