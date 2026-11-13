# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Const::Fast;
use MIME::Base64 qw(encode_base64url);
use Test::More;
use lib 'lib', 't/lib';
use GPForum::Service::Forum::CategoryReader;
use GPForum::Service::Forum::PageWindow;
use GPForum::Service::Forum::ThreadReader;
use GPForum::Service::Search::Searcher;
use GPForum::Test::RecordingFunctions;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';
const my $CATEGORY_DEFAULT => 100;
const my $SEARCH_DEFAULT   => 20;
const my $CATEGORY_MAX     => 200;
const my $SEARCH_MAX       => 50;
const my $LARGE_LIMIT      => 1000;
const my $OVERSIZED_CURSOR => 4096;
const my $ID               => '018f1000-0000-7000-8000-000000000001';
const my $INSTANT          => '2026-11-06 01:02:03.123456+14:00';

subtest 'list limits reject Unicode digits before numeric conversion' => sub {
    my $calls    = GPForum::Test::RecordingFunctions->new;
    my $category = GPForum::Service::Forum::CategoryReader->new(
        schema    => {},
        functions => $calls
    );
    my $search = GPForum::Service::Search::Searcher->new(
        schema    => {},
        functions => $calls
    );
    my $limit_asked = sub { return $calls->calls->[-1][1]{row_limit}; };
    my @warnings;
    local $SIG{__WARN__} = sub ($warning) { push @warnings, $warning; };
    for my $invalid (
        "\N{ARABIC-INDIC DIGIT ONE}",
        "1\N{ARABIC-INDIC DIGIT ONE}",
        "1\N{FULLWIDTH DIGIT ONE}"
      )
    {
        $category->list_categories( { limit => $invalid } );
        is( $limit_asked->(), $CATEGORY_DEFAULT,
            'the category size uses its default' );
        is(
            $search->ranked_call( {}, 'term', { limit => $invalid } )
              ->[1]{row_limit},
            $SEARCH_DEFAULT,
            'the search call receives an ASCII integer default'
        );
    }
    is_deeply( \@warnings, [],
        'invalid numeric text produces no conversion warnings' );
    $category->list_categories( { limit => $LARGE_LIMIT } );
    is( $limit_asked->(), $CATEGORY_MAX, 'the category cap remains' );
    is(
        $search->ranked_call( {}, 'term', { limit => $LARGE_LIMIT } )
          ->[1]{row_limit},
        $SEARCH_MAX,
        'the search cap remains'
    );
};

subtest 'cursor decoding is bounded and a pinned cursor is decoded once' =>
  sub {
    my $window = GPForum::Service::Forum::PageWindow->new;
    my $reader = GPForum::Service::Forum::ThreadReader->new(
        schema    => {},
        functions => undef
    );
    my $decode  = MIME::Base64->can('decode_base64url');
    my $decodes = 0;
    my $count_decode =
      sub ($encoded) { ++$decodes; return $decode->($encoded); };
    with_replaced_subs(
        'GPForum::Service::Forum::PageWindow',
        { decode_base64url => $count_decode },
        sub {
            with_replaced_subs(
                'GPForum::Service::Forum::ThreadReader',
                { decode_base64url => $count_decode },
                sub {
                    my $oversized = 'A' x $OVERSIZED_CURSOR;
                    is(
                        $window->plan( { after => $oversized } )->{after},
                        undef,
'an oversized ordinary cursor falls back to the first page'
                    );
                    my $call = $reader->category_threads_call(
                        { category_id => $ID, after => $oversized } );
                    is( $call->[1]{after_thread_id}, undef,
'an oversized pinned cursor falls back to the first page'
                    );
                    is( $decodes, 0,
                        'oversized values never enter the base64 decoder' );

                    my $ordinary = encode_base64url("$INSTANT|$ID");
                    is_deeply(
                        $window->plan(
                            { after => $ordinary, sort => 'timestamp' }
                        )->{after},
                        { sort_value => $INSTANT, id => $ID },
                        'microseconds and full timezone offsets remain valid'
                    );
                    $decodes = 0;
                    my $pinned = encode_base64url("1|$INSTANT|$ID");
                    $call = $reader->category_threads_call(
                        { category_id => $ID, after => $pinned } );
                    is( $call->[1]{after_activity},
                        $INSTANT, 'the pinned timestamp remains intact' );
                    is( $call->[1]{after_thread_id},
                        $ID, 'the pinned id remains intact' );
                    is( $call->[1]{after_pinned},
                        1, 'the pinned ordering remains intact' );
                    is( $decodes, 1,
                        'the category cursor is decoded only in its own format'
                    );

                    for my $flag (qw(0 f false)) {
                        $call = $reader->category_threads_call(
                            {
                                category_id => $ID,
                                after => encode_base64url("$flag|$INSTANT|$ID")
                            }
                        );
                        is( $call->[1]{after_pinned},
                            0, 'legacy false spellings remain valid' );
                    }
                }
            );
        }
    );
  };

done_testing();
1;
