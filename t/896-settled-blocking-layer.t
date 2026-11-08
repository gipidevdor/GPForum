# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Mojo::Promise;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::X::Unavailable;
use GPForum::Test::SettlingService;

our $VERSION = '0.001';

const my $ANSWER => 42;
const my $HALF   => 21;

# ADR 0177: a blocking method is its promise method run on a blocking call
# layer, whose promises are settled when they are made. settled reads such a
# promise's answer, raises its failure as it was, and refuses one still
# pending: blocking code never waits on the event loop.
my $class = 'GPForum::Infrastructure::SqlFunction';

is( $class->settled($ANSWER), $ANSWER, 'a plain value is answered as it is' );
is( $class->settled( Mojo::Promise->resolve('done') ),
    'done', 'a settled promise answers its value' );

my $failure = GPForum::X::Unavailable->new( message => 'gone' );
my $raised;
try { $class->settled( Mojo::Promise->reject($failure) ); }
catch ($error) { $raised = $error; };
is( $raised, $failure, 'a rejected promise raises its failure as it was' );

my $refused;
try { $class->settled( Mojo::Promise->new ); }
catch ($error) { $refused = "$error"; };
like( $refused, qr/still [ ] running/msx, 'a pending promise is refused' );

# settle runs the promise method on a copy whose call layer blocks, and the
# copy's awaits finish without an event loop.
my $service = GPForum::Test::SettlingService->new(
    functions => GPForum::Test::SettlingService::Layer->new );
is_deeply(
    $class->settle( $service, double_p => $HALF ),
    { blocking => 1, value => $ANSWER },
    'settle answers the promise method on the blocking layer'
);
ok( !$service->functions->blocking, 'and leaves the service as it was' );

my $nothing = GPForum::Test::SettlingService->new( functions => undef );
is_deeply(
    $class->settle( $nothing, double_p => 2 ),
    { blocking => 0, value => 4 },
    'a service without a call layer runs as it is'
);

done_testing();

1;
