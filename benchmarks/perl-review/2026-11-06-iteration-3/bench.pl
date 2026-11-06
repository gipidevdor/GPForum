# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Config;
use JSON::MaybeXS;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use lib 'lib';
use GPForum::Infrastructure::ResultRow;
use GPForum::Service::Forum::HomePageReader;
use GPForum::Service::Search::Searcher;

{
    package GPForum::Review::HomeRows;
    use Mojo::Base -base, -signatures;
    use v5.40;
    has categories => sub {return [];};
    has threads => sub {return [];};
    sub list_categories ($self, $request) {return $self->categories;}
    sub list_public_threads ($self, $request) {return {items => $self->threads, next_cursor => undef};}
}
{
    package GPForum::Review::SearchRows;
    use Mojo::Base -base, -signatures;
    use v5.40;
    has documents => sub {return [];};
    sub rows ($self, $name, $values) {
        # Real DBI fetches new hashes. ResultRow blesses them in place.
        return [map {{%{$_}}} @{$self->documents}];
    }
}

my @category = map {{category_id => "category-$_", title => "Category $_", description => 'A forum category',
    slug => "category-$_", visibility => 'public', position => $_, thread_count => 100,
    last_activity_at => '2026-11-06T00:00:00Z'}} 1 .. 12;
my @thread = map {{thread_id => "thread-$_", category_id => 'category-1', title => "Discussion $_", slug => "discussion-$_",
    author_user_id => 'user-1', author_username => 'elena', author_display_name => 'Elena',
    created_at => '2026-11-05T00:00:00Z', last_activity_at => '2026-11-06T00:00:00Z', deleted_at => undef,
    visibility => 'public', moderation_state => 'visible', pinned => 0, reply_count => 10,
    excerpt => '<p>Forum performance &amp; database caching: a useful discussion about keeping request handling efficient.</p>'}} 1 .. 20;
my @cases;
for my $shape (qw(hash mixed_function_rows)) {
    my $rows = $shape eq 'hash' ? [map {{%{$_}}} @thread] : [map {GPForum::Infrastructure::ResultRow->from({%{$_}})} @thread];
    my $source = GPForum::Review::HomeRows->new(categories => \@category, threads => $rows);
    my $home = GPForum::Service::Forum::HomePageReader->new(category_reader => $source, thread_reader => $source);
    push @cases, ["home_${shape}_no_io", 3000, sub {return $home->home_page({});}];
}
my @documents = map {{entity_type => 'post', entity_id => "post-$_", category_id => 'category-1',
    author_user_id => 'user-1', author_username => 'elena', author_display_name => 'Elena',
    title => "Discussion $_", visibility => 'public', space_id => 'space-1',
    category_visibility => 'public', space_visibility => 'public',
    body => '<p>Forum performance and database cache request response latency throughput. &amp; More discussion.</p>' x 10,
    source_created_at => '2026-11-05T00:00:00Z', indexed_at => '2026-11-06T00:00:00Z',
    candidate_count => 25, rank_score => 1, thread_owner_user_id => undef}} 1 .. 25;
my $search = GPForum::Service::Search::Searcher->new(schema => {}, functions => GPForum::Review::SearchRows->new(documents => \@documents));
push @cases, ['ranked_search_one_term_stub_no_database', 1500, sub {return $search->ranked_search({}, 'performance', {limit => 25});}];
push @cases, ['ranked_search_eight_terms_stub_no_database', 1500, sub {return $search->ranked_search({}, 'forum performance database cache request response latency throughput', {limit => 25});}];
my @suggestions = map {my %row=%{$_}; delete @row{qw(body space_id category_visibility space_visibility candidate_count rank_score thread_owner_user_id indexed_at)}; \%row} @documents;
my $suggest = GPForum::Service::Search::Searcher->new(schema => {}, functions => GPForum::Review::SearchRows->new(documents => \@suggestions));
push @cases, ['autocomplete_stub_no_database', 5000, sub {return $suggest->autocomplete({}, 'per', {limit => 25});}];
my $empty = GPForum::Service::Search::Searcher->new(schema => {}, functions => GPForum::Review::SearchRows->new);
push @cases, ['ranked_search_empty_stub_no_database', 50_000, sub {return $empty->ranked_search({}, 'missing', {});}];
my @results;
for my $case (@cases) {
    my ($name, $iterations, $code) = @{$case};
    my $sink;
    for (1 .. 100) {$sink=$code->();}
    for my $repetition (1 .. 3) {
        my $started=clock_gettime(CLOCK_MONOTONIC);
        for (1 .. $iterations) {$sink=$code->();}
        my $seconds=clock_gettime(CLOCK_MONOTONIC)-$started;
        push @results, {name => $name, repetition => $repetition, iterations => $iterations, seconds => $seconds, operations_per_second => $iterations/$seconds};
    }
    die "Incorrect home fixture\n" if $name =~ /\Ahome_/ && @{$sink->{latest_threads}{items}} != 20;
    die "Incorrect ranked fixture\n" if $name =~ /\Aranked_search_(?:one|eight)/ && @{$sink->{results}} != 25;
    die "Incorrect empty fixture\n" if $name =~ /\Aranked_search_empty/ && @{$sink->{results}};
    die "Incorrect suggestions\n" if $name =~ /\Aautocomplete/ && @{$sink} != 25;
}
print JSON::MaybeXS->new(canonical => 1, utf8 => 1, pretty => 1)->encode({
    perl => "$^V", architecture => $Config{archname}, platform => $^O,
    method => 'Three fixed-iteration batches after 100 warmups. Monotonic wall time. Units are complete service calls, not individual rows or HTTP requests. Home has 12 categories and 20 threads; search has 25 results with fresh function-row hashes. Readers and function calls are stubs without database, permissions-engine or network cost; real PostgreSQL/HTTP is measured separately.',
    results => \@results,
});
