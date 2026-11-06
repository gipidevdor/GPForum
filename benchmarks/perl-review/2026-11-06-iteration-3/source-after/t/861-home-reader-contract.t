# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use Test::More;
use lib 'lib', 't/lib';
use GPForum::Infrastructure::ResultRow;
use GPForum::Service::Forum::HomePageReader;
use GPForum::Test::ForumWebServices;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';
const my $CATEGORY_LIMIT => 12;
const my $THREAD_LIMIT   => 20;
const my $MAX_LIMIT      => 50;
const my $OPTIONAL_READS => 3;
const my $INVALID_LIMIT  => -1;

my $services = GPForum::Test::ForumWebServices->new;
my $reader   = GPForum::Service::Forum::HomePageReader->new(
    category_reader => $services,
    thread_reader   => $services,
);
my $category = {
    category_id  => 'category-1',
    description  => 'Description',
    title        => 'Category',
    slug         => 'category',
    position     => 1,
    visibility   => 'public',
    thread_count => 0
};
my $thread = {
    thread_id           => 'thread-1',
    category_id         => 'category-1',
    author_user_id      => 'user-1',
    author_username     => 'elena',
    author_display_name => 'Elena',
    title               => 'Title',
    slug                => 'title',
    visibility          => 'public',
    reply_count         => 0,
    pinned              => 0,
    moderation_state    => 'visible',
    excerpt             => '<p>A &amp; B</p>'
};
my ( $category_request, $thread_request );
with_replaced_subs(
    'GPForum::Test::ForumWebServices',
    {
        list_categories => sub ( $self, $request ) {
            $category_request = $request;
            return [$category];
        },
        list_public_threads => sub ( $self, $request ) {
            $thread_request = $request;
            return { items => [$thread], next_cursor => 'next' };
        },
    },
    sub {
        subtest 'home limits remain positive bounded ASCII integers' => sub {
            my @warnings;
            local $SIG{__WARN__} = sub ($warning) { push @warnings, $warning; };
            for my $invalid ( undef, q{}, 'garbage', $INVALID_LIMIT, 0, '1.5',
                "\N{ARABIC-INDIC DIGIT ONE}" )
            {
                $reader->home_page(
                    { category_limit => $invalid, thread_limit => $invalid } );
                is( $category_request->{limit},
                    $CATEGORY_LIMIT,
                    'invalid category size uses the home default' );
                is( $thread_request->{limit},
                    $THREAD_LIMIT,
                    'invalid thread size uses the home default' );
            }
            is_deeply( \@warnings, [],
                'invalid sizes do not produce numeric conversion warnings' );
            $reader->home_page(
                {
                    category_limit => $MAX_LIMIT + 1,
                    thread_limit   => $MAX_LIMIT + 1
                }
            );
            is( $category_request->{limit},
                $MAX_LIMIT, 'categories stay under the cap' );
            is( $thread_request->{limit},
                $MAX_LIMIT, 'threads stay under the cap' );
            $reader->home_page(
                { category_limit => 1, thread_limit => 1, after => 'cursor' } );
            is( $category_request->{limit},
                1, 'an explicit category size remains valid' );
            is( $thread_request->{limit},
                1, 'an explicit thread size remains valid' );
            is( $thread_request->{after},
                'cursor', 'pagination input is preserved' );
        };

        subtest
'home projection reads loaded columns once without changing its output'
          => sub {
            my $expected = $reader->home_page( {} );
            $category =
              GPForum::Infrastructure::ResultRow->from( { %{$category} } );
            $thread =
              GPForum::Infrastructure::ResultRow->from( { %{$thread} } );
            my $columns =
              GPForum::Infrastructure::ResultRow->can('get_columns');
            my $column = GPForum::Infrastructure::ResultRow->can('get_column');
            my ( $snapshots, $reads ) = ( 0, 0 );
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
                    is_deeply( $reader->home_page( {} ),
                        $expected,
                        'function rows and hashes give the same page' );
                }
            );
            is( $snapshots, 2, 'one snapshot per listed row' );
            cmp_ok( $reads, '<=', $OPTIONAL_READS,
                'required values do not dispatch individual getters' );
            is( $expected->{latest_threads}{items}[0]{excerpt},
                'A & B', 'safe excerpts retain decoded text' );
            is( $expected->{categories}[0]{thread_count},
                0, 'optional zero values are preserved' );
            ok(
                exists $expected->{categories}[0]{last_activity_at},
                'missing optional values retain their keys'
            );
          };
    }
);

done_testing();
1;
