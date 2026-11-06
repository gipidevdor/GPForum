# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib', 't/lib';
use GPForum::Infrastructure::ResultRow;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use GPForum::Test::ViewModelRow;
use GPForum::ViewModel::Forum::Rows;

our $VERSION = '0.001';

const my $OPTIONAL_READ_BUDGET => 4;

my $presenter = GPForum::ViewModel::Forum::Rows->new;
my %data      = (
    author_username     => 'elena',
    author_display_name => "\N{LATIN CAPITAL LETTER E WITH ACUTE}lena",
    author_user_id      => 'user-1',
    category_id         => 'category-1',
    category_title      => 'Category',
    category_visibility => 'members',
    space_visibility    => 'private',
    description         => 'Description',
    entity_id           => 'entity-1',
    entity_type         => 'post',
    thread_id           => 'thread-1',
    source_thread_id    => 'source-thread-1',
    title               => 'Title',
    slug                => 'title',
    body                => 'Body',
    position            => 1,
    pinned              => 0,
    locked_at           => undef,
    deleted_at          => undef,
    last_activity_at    => '2026-11-06T00:00:00Z',
    indexed_at          => '2026-11-06T00:00:00Z',
    source_created_at   => '2026-11-05T00:00:00Z',
    moderation_state    => 'visible',
    visibility          => 'public',
    rank_score          => 1,
    snippet             => 'Excerpt',
    snippet_html        => '<b>Excerpt</b>',
    reply_count         => 0,
    thread_count        => 0,
);

for my $optional ( 0, 1 ) {
    my %fixture = %data;
    if ( !$optional ) {
        delete @fixture{
            qw(category_title category_visibility space_visibility
              source_thread_id last_activity_at reply_count thread_count)
        };
    }
    for my $method (qw(category thread search_result autocomplete_suggestion)) {
        subtest "$method with optional columns $optional" => sub {
            my $expected = $presenter->$method( \%fixture );
            my $fallback = GPForum::Test::ViewModelRow->new( {%fixture} );
            is_deeply( $presenter->$method($fallback),
                $expected, 'column-only rows preserve the public projection' );

            my $row  = GPForum::Infrastructure::ResultRow->from( {%fixture} );
            my $read = GPForum::Infrastructure::ResultRow->can('get_column');
            my $snapshot =
              GPForum::Infrastructure::ResultRow->can('get_columns');
            my ( $reads, $snapshots ) = ( 0, 0 );
            with_replaced_subs(
                'GPForum::Infrastructure::ResultRow',
                {
                    get_column => sub ( $record, $name ) {
                        ++$reads;
                        return $read->( $record, $name );
                    },
                    get_columns => sub ($record) {
                        ++$snapshots;
                        return $snapshot->($record);
                    },
                },
                sub {
                    is_deeply( $presenter->$method($row),
                        $expected,
                        'function rows preserve the public projection' );
                }
            );
            is( $snapshots, 1, 'loaded values are read in one snapshot' );
            cmp_ok( $reads, '<=', $OPTIONAL_READ_BUDGET,
                'only optional columns require individual reads' );
            is_deeply( { %{$row} },
                \%fixture, 'projection leaves the source row intact' );
        };
    }
}

done_testing();

1;
