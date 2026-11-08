# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use File::Find;
use Mojo::File qw(path);
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

our $VERSION = '0.001';

# A controller reaches a service through call_p. A service that holds a
# database connection and has no METHOD_p twin (nor async_call_p) fails the
# request at run time -- the HTTP loop never queries synchronously. This
# finds every literal call_p( $self->gp_helper, 'method' ) in the controllers
# and checks the twin exists, so the gap shows here, not in production.

my %calls;
find(
    {
        no_chdir => 1,
        wanted   => sub {
            return if $File::Find::name !~ /[.]pm\z/msx;
            my $source = path($File::Find::name)->slurp;
            while (
                $source =~ m{call_p [(] \s* \$self->(gp_\w+) \s*,
                    \s* '(\w+)'}gmsx
              )
            {
                push @{ $calls{$1}{$2} }, $File::Find::name;
            }
        },
    },
    'lib/GPForum/Controller'
);
ok( scalar keys %calls, 'the controllers call services through call_p' );

my $test = Test::Mojo->new('GPForum');
$test->app->log->level(q{fatal});
my $controller = $test->app->build_controller;
my @missing;
for my $helper ( sort keys %calls ) {
    my $service = eval { $controller->$helper };
    next if !$service || !ref $service;
    next if $service->can('async_call_p');
    for my $method ( sort keys %{ $calls{$helper} } ) {
        next if $service->can( $method . '_p' );
        push @missing, ref($service) . "::${method}_p ($helper)";
    }
}
is_deeply( \@missing, [], 'every service a controller calls has its _p twin' );

done_testing();

1;
