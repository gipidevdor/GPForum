# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use lib 'lib';
use Carp qw(croak);
use Const::Fast;
use Mojolicious;
use Test::More;
use GPForum::Web::Warmup;

our $VERSION = '0.001';

const my $OK    => 200;
const my $PAGES => 4;
my $app = Mojolicious->new;
$app->log->level('fatal');
my @warming;
for my $path (qw(/ /categories /login /register)) {
    $app->routes->get($path)->to(
        cb => sub ($controller) {
            push @warming, $controller->stash('gpforum.warming');
            return $controller->render( text => 'warmed' );
        }
    );
}

my $report;
{
    local *Mojo::IOLoop::new = sub {
        croak 'warmup must not create another event loop';
    };
    local *Mojo::IOLoop::server = sub {
        croak 'warmup must not open a local listener';
    };
    $report = GPForum::Web::Warmup->new( application => $app )->run;
}
is_deeply(
    [ map { $_->{status} } @{ $report->{pages} } ],
    [ ($OK) x @warming ],
    'all warmup pages run through the normal handler without network I/O'
);
is_deeply(
    \@warming,
    [ (1) x $PAGES ],
    'all four requests are marked as warming'
);
ok(
    !exists $app->defaults->{'gpforum.warming'},
    'subsequent requests are not marked as warming'
);

done_testing();

1;
