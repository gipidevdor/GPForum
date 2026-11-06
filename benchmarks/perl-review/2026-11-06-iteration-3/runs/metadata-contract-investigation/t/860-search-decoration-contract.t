# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use Test::More;
use lib 'lib', 't/lib';
use GPForum::Infrastructure::ResultRow;
use GPForum::Service::Search::Searcher;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use GPForum::ViewModel::Forum::Rows;

our $VERSION = '0.001';
const my $RESULTS        => 3;
const my $PREFIX_REPEATS => 60;

sub _search ( $query, $bodies ) {
    my @rows = map {
        GPForum::Infrastructure::ResultRow->from(
            {
                entity_type         => 'post',
                entity_id           => "post-$_",
                category_id         => 'category-1',
                author_user_id      => 'user-1',
                author_username     => 'elena',
                author_display_name => 'Elena',
                title               => 'Thread title',
                body                => $bodies->[ $_ - 1 ],
                visibility          => 'public',
                source_thread_id    => 'thread-1',
                rank_score          => 1,
            }
        )
    } 1 .. @{$bodies};
    my $searcher = GPForum::Service::Search::Searcher->new(
        schema    => {},
        functions => undef
    );
    return with_replaced_subs(
        'GPForum::Service::Search::Searcher',
        {
            search_resultset => sub { return \@rows; },
        },
        sub { return $searcher->ranked_search( {}, $query, {} ); }
    );
}

subtest 'Unicode matches determine both the excerpt and its highlighting' =>
  sub {
    my $word = "Stra\N{LATIN SMALL LETTER SHARP S}e";
    my $short =
      _search( 'STRASSE', ["$word & caf\N{LATIN SMALL LETTER E WITH ACUTE}"] )
      ->{results}[0];
    is(
        $short->{snippet_html},
        "<mark>$word</mark> &amp; caf\N{LATIN SMALL LETTER E WITH ACUTE}",
        'case folds that change length are marked while text is escaped'
    );
    my $long = _search( 'STRASSE', [ ( 'prima ' x $PREFIX_REPEATS ) . $word ] )
      ->{results}[0];
    like( $long->{snippet}, qr/\Q$word\E/msx,
        'the excerpt includes the Unicode match beyond its first window' );
    like(
        $long->{snippet_html},
        qr/<mark>\Q$word\E<\/mark>/msx,
        'the same match is highlighted'
    );
  };

subtest 'source thread links survive result decoration' => sub {
    my $result = _search( 'forum', ['forum'] )->{results}[0];
    is( $result->{source_thread_id},
        'thread-1', 'search preserves the already loaded thread id' );
    is(
        GPForum::ViewModel::Forum::Rows->new->search_result($result)
          ->{thread_id},
        'thread-1', 'the view can link a post result to its discussion'
    );
};

subtest 'query preparation and row reads have a per-page budget' => sub {
    my $terms   = GPForum::Service::Search::Searcher->can('_terms');
    my $columns = GPForum::Infrastructure::ResultRow->can('get_columns');
    my $column  = GPForum::Infrastructure::ResultRow->can('get_column');
    my ( $preparations, $snapshots, $reads ) = ( 0, 0, 0 );
    my $page;
    with_replaced_subs(
        'GPForum::Service::Search::Searcher',
        {
            _terms =>
              sub ($query) { ++$preparations; return $terms->($query); },
        },
        sub {
            with_replaced_subs(
                'GPForum::Infrastructure::ResultRow',
                {
                    get_columns =>
                      sub ($row) { ++$snapshots; return $columns->($row); },
                    get_column => sub ( $row, $name ) {
                        ++$reads;
                        return $column->( $row, $name );
                    },
                },
                sub {
                    $page = _search( 'for forum FORUM',
                        [ ('forum FOR') x $RESULTS ] );
                }
            );
        }
    );
    is( $preparations, 1,        'terms are prepared once for the whole page' );
    is( $snapshots,    $RESULTS, 'one loaded snapshot per result' );
    cmp_ok(
        $reads, '<=',
        $RESULTS + 1,
        'only the candidate count and optional thread ids need getters'
    );
    is(
        $page->{results}[0]{snippet_html},
        '<mark>for</mark>um <mark>FOR</mark>',
        'term order and prefix matching remain compatible'
    );
    is_deeply(
        $page->{results}[0]{highlight_terms},
        [ 'for', 'forum' ],
        'terms retain order and deduplication'
    );
    $page->{results}[0]{highlight_terms}[0] = 'poison';
    is_deeply(
        $page->{results}[1]{highlight_terms},
        [ 'for', 'forum' ],
        'callers receive independent term arrays'
    );
};

subtest 'markup remains escaped and punctuation has no highlight terms' => sub {
    my $result =
      _search( 'forum', ['&lt;script&gt;forum&lt;/script&gt; &amp;'] )
      ->{results}[0];
    is(
        $result->{snippet_html},
        '&lt;script&gt;<mark>forum</mark>&lt;/script&gt; &amp;',
        'decoded text is escaped around generated mark tags'
    );
    is( _search( '!!!', ['a & b'] )->{results}[0]{snippet_html},
        'a &amp; b', 'empty term lists still escape the whole snippet' );
};

done_testing();
1;
