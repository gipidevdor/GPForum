# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
use v5.40;
use Config;
use JSON::MaybeXS;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use lib 'lib';
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Operations::LocalCache;

{
    package GPForum::Review::Handle;
    use Mojo::Base -base, -signatures;
    use v5.40;
    sub storage ($self) { return $self; }
    sub debug ($self) { return 0; }
    sub dbh_do ($self, $code) { return $code->($self, $self); }
    sub prepare_cached ($self, @) { return $self; }
    sub execute ($self, @) { return 1; }
    sub state ($self) { return q{}; }
    sub fetchall_arrayref ($self, @) {
        return [ { post_id => '018f1003-0001-7000-8000-000000000001' } ];
    }
}

my $layer = GPForum::Infrastructure::SqlFunction->new(schema => GPForum::Review::Handle->new);
my $values = {
    after_position => undef, after_post_id => undef, row_limit => 26,
    standing => 'member', thread_id => '018f1004-0001-7000-8000-000000000001',
    viewer_user_id => '018f1002-0001-7000-8000-000000000001',
};
my $likes = {
    post_ids => [ map { sprintf '018f1003-%04x-7000-8000-%012x', $_, $_ } 1 .. 25 ],
    viewer_user_id => $values->{viewer_user_id},
};
my $cache = GPForum::Service::Operations::LocalCache->new(ttl_seconds => 300);
my $options = { tags => ['bench'] };
$cache->put('hot', 1, $options);
my @cases = (
    ['sql_bind', 100_000, sub { return $layer->statement('forum_thread_page_posts', $values); }],
    ['sql_rows_stub_no_database', 50_000, sub { return $layer->rows('forum_thread_page_posts', $values); }],
    ['sql_answer_key_25_posts', 50_000, sub { return $layer->answer_key('community_post_likes', $likes); }],
    ['local_cache_get', 500_000, sub { return $cache->get('hot'); }],
    ['local_cache_replace', 50_000, sub { return $cache->put('hot', 1, $options); }],
);
my @results;
for my $case (@cases) {
    my ($name, $iterations, $code) = @{$case};
    my $sink;
    for (1 .. 100) { $sink = $code->(); }
    for my $repetition (1 .. 3) {
        my $started = clock_gettime(CLOCK_MONOTONIC);
        for (1 .. $iterations) { $sink = $code->(); }
        my $seconds = clock_gettime(CLOCK_MONOTONIC) - $started;
        push @results, { name => $name, repetition => $repetition, iterations => $iterations,
            seconds => $seconds, operations_per_second => $iterations / $seconds };
    }
    die "Invalid cache result\n" if $name eq 'local_cache_get' && $sink != 1;
}
print JSON::MaybeXS->new(canonical => 1, utf8 => 1, pretty => 1)->encode({
    perl => "$^V", architecture => $Config{archname}, platform => $^O,
    method => 'Three fixed-iteration batches after 100 untimed warmups; wall-clock monotonic time; SQL row case uses a bounded stub without PostgreSQL or statement history.',
    results => \@results,
});
