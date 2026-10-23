#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

use v5.40;
use Const::Fast;
use FindBin;
use lib "$FindBin::Bin/../lib";
use GPForum;
use JSON::MaybeXS qw(encode_json);
use Mojo::IOLoop;
use Mojolicious ();

# Only this benchmark entrypoint changes cache lifetime. The normal application
# configuration, including its positive TTL contract, remains untouched. A
# negative TTL stores then immediately expires the SSR entry; category read
# models retain the same warm local cache in both scenarios.
const my $COMPLETE_HTTP_LIMIT => 100_000_000;
my $app = GPForum->new;
if (($ENV{GPFORUM_PERFORMANCE_FULL_HTTP} // '') eq '1') {
    die 'complete HTTP benchmark requires its disposable database'
        if ($ENV{GPFORUM_DATABASE_DSN} // '') !~ /dbname=gpforum_perf_http_[[:digit:]]+(?:;|\z)/msx;
    # Raise admission quotas only in this benchmark entrypoint. PostgreSQL
    # counters, authorization, CSRF and command idempotency still execute.
    my $check = GPForum::Service::Operations::RateLimiter->can('check');
    no warnings 'redefine'; ## no critic (TestingAndDebugging::ProhibitNoWarnings) -- opt-in admission quota override in the disposable benchmark entrypoint
    *GPForum::Service::Operations::RateLimiter::check = sub ($self, $input) {
        return $check->($self, {%$input, limit => $COMPLETE_HTTP_LIMIT});
    };
    $app->hook(after_dispatch => sub ($c) {
        $c->res->headers->header('X-GPForum-Bench-Route' => $c->current_route // 'unknown');
        $c->res->headers->header('X-GPForum-Bench-Worker' => $$);
    });
}
if (($ENV{GPFORUM_PERFORMANCE_CACHE_MODE} // '') eq 'miss') {
    $app->helper(gp_public_http_cache => sub ($controller) {
        return GPForum::Web::PublicHttpCache->new(
            cache => $controller->gp_local_cache, ttl_seconds => -1,
        );
    });
}

# The manager's reactor does not prove what handles requests after a fork.
# Record once from each serving worker, before its first dispatch. No extra
# HTTP route, database write or per-request metrics header is introduced.
my $recorded;
$app->hook(before_dispatch => sub ($controller) {
    return if $recorded && $recorded == $$;
    $recorded = $$;
    my $directory = $ENV{GPFORUM_PERFORMANCE_TELEMETRY_DIR}
        or die 'benchmark telemetry directory is required';
    my $reactor = ref Mojo::IOLoop->singleton->reactor;
    my $backend;
    if ($reactor eq 'Mojo::Reactor::EV') {
        $backend = EV::backend();
    }
    open my $file, '>', "$directory/worker-$$.json"
        or die 'cannot write benchmark worker telemetry';
    print {$file} encode_json({pid => 0 + $$, reactor => $reactor,
        ev_backend => $backend, perl => "$^V",
        mojolicious => Mojolicious->VERSION});
    close $file or die 'cannot close benchmark worker telemetry';
});

no warnings 'void';
$app;
