use v5.40;
use lib 'lib', 't/lib';
use GPForum::Service::Operations::RateLimiter;

# Rendering diagnostics measure admitted requests, as the full HTTP harness
# does. Keep the actual PostgreSQL counters and all other request checks.
my $check = GPForum::Service::Operations::RateLimiter->can('check');
{
    no warnings 'redefine';
    *GPForum::Service::Operations::RateLimiter::check = sub ($self, $input) {
        die "render diagnostic requires its owned temporary database\n"
          if ($ENV{GPFORUM_DATABASE_DSN} // q{}) !~
          /dbname=gpforum_bench_render_[[:digit:]]+(?:;|\z)/;
        return $check->($self, {%{$input}, limit => 100_000_000});
    };
}
do './script/bench-render';
die $@ || "cannot load render benchmark: $!\n";
