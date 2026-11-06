# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Config;
use JSON::MaybeXS;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use lib 'lib';
use GPForum::Infrastructure::ResultRow;
use GPForum::Service::Integration::SourceLinks;
use GPForum::Service::Realtime::PgListener;
use GPForum::ViewModel::Forum::Rows;

{
    package GPForum::Review::Hub;
    use Mojo::Base -base, -signatures;
    use v5.40;
    sub broadcast_event ($self, $event) {
        return {ok => 1, delivered => 0, failed => 0};
    }
}

my $presenter = GPForum::ViewModel::Forum::Rows->new;
my %spec = (
    category => {
        category_id => 'category-1', description => 'Category description',
        last_activity_at => '2026-11-06T00:00:00Z', thread_count => 20,
        position => 1, slug => 'category', title => 'Category', visibility => 'public',
    },
    thread => {
        author_username => 'elena', author_display_name => 'Elena', author_user_id => 'user-1',
        category_id => 'category-1', category_title => 'Category', category_visibility => 'public',
        space_visibility => 'public', last_activity_at => '2026-11-06T00:00:00Z',
        locked_at => undef, moderation_state => 'visible', pinned => 0, reply_count => 30,
        slug => 'a-thread', thread_id => 'thread-1', title => 'A thread', deleted_at => undef,
        visibility => 'public',
    },
    search_result => {
        author_username => 'elena', author_display_name => 'Elena', author_user_id => 'user-1',
        body => 'Searchable text ' x 30, category_id => 'category-1', entity_id => 'post-1',
        entity_type => 'post', indexed_at => '2026-11-06T00:00:00Z', rank_score => 1,
        snippet => 'Searchable text', snippet_html => '<b>Searchable</b> text',
        source_created_at => '2026-11-05T00:00:00Z', source_thread_id => 'thread-1',
        title => 'A thread', visibility => 'public',
    },
    autocomplete_suggestion => {
        author_username => 'elena', author_display_name => 'Elena', author_user_id => 'user-1',
        category_id => 'category-1', entity_id => 'thread-1', entity_type => 'thread',
        source_created_at => '2026-11-05T00:00:00Z', title => 'A thread', visibility => 'public',
    },
);
my @cases;
for my $method (sort keys %spec) {
    for my $shape (qw(hash function_row)) {
        my $data = $spec{$method};
        my $row = $shape eq 'hash' ? {%$data} : GPForum::Infrastructure::ResultRow->from({%$data});
        push @cases, ["projection_${method}_${shape}", 100_000, sub {return $presenter->$method($row);}];
    }
}
my $hot = join "\n", map {"https://example.test/item/$_"} 1 .. 10;
my $oversized = 'x' x 1025;
my $cache = GPForum::Service::Integration::SourceLinks->new(max_characters => 1024);
my $ordinary = GPForum::Service::Integration::SourceLinks->new;
$cache->urls($hot);
$ordinary->urls($hot);
push @cases, ['source_hit_default', 100_000, sub {return $ordinary->urls($hot);}];
push @cases, ['source_mixed_small_budget', 30_000, sub {
    $cache->urls($oversized);
    return $cache->urls($hot);
}];
my $listener = GPForum::Service::Realtime::PgListener->new(hub => GPForum::Review::Hub->new);
my $summary = {delivered => 0, failed => 0, duplicates => 0};
my $event = {type => 'thread.update', event_id => 'same-event'};
$listener->_deliver_event($summary, $event);
push @cases, ['realtime_duplicate_stub_no_io', 200_000, sub {
    $listener->_deliver_event($summary, $event);
    return $summary;
}];
my $sequence = 0;
push @cases, ['realtime_success_stub_no_io', 100_000, sub {
    $listener->_deliver_event($summary, {type => 'thread.update', event_id => ++$sequence});
    return $summary;
}];
my @results;
for my $case (@cases) {
    my ($name, $iterations, $code) = @$case;
    my $sink;
    for (1 .. 100) {$sink = $code->();}
    for my $repetition (1 .. 3) {
        my $started = clock_gettime(CLOCK_MONOTONIC);
        for (1 .. $iterations) {$sink = $code->();}
        my $seconds = clock_gettime(CLOCK_MONOTONIC) - $started;
        push @results, {name => $name, repetition => $repetition, iterations => $iterations,
            seconds => $seconds, operations_per_second => $iterations / $seconds};
    }
    die "Unexpected source candidates\n" if $name =~ /\Asource_/ && @$sink != 10;
    die "Missing projection\n" if $name =~ /\Aprojection_/ && ref $sink ne 'HASH';
}
print JSON::MaybeXS->new(canonical => 1, utf8 => 1, pretty => 1)->encode({
    perl => "$^V", architecture => $Config{archname}, platform => $^O,
    method => 'Three fixed-iteration batches per case, after 100 untimed warmups. Monotonic wall time. Projection inputs match selected page columns. Realtime uses a successful no-IO hub stub. Mixed source case uses a configured 1024-character cache, not its default budget. No HTTP or database in microbenchmarks. The orchestration records known competing jobs separately.',
    results => \@results,
});
