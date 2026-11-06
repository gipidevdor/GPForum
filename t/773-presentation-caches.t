# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use utf8;
use lib 'lib', 't/lib';
use Const::Fast;
use Mojo::DOM;
use Test::Fatal qw(exception);
use Test::Mojo;
use Test::More;
use GPForum::Service::Integration::Registry;
use GPForum::Service::Integration::SourceLinks;
use GPForum::Service::Integration::Spotify;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use GPForum::Web::IconSet;

our $VERSION = '0.001';
const my $SOURCE_LIMIT => 50_000;
const my $MANY         => 100;
const my $URL   => 'https://open.spotify.com/track/0Lr4kGOYn9l83EjuK6cZFQ';
const my $OTHER => 'https://example.test/other';
const my $ENTRY_LIMIT      => 3;
const my $CHARACTER_LIMIT  => 120;
const my $SPRITE_ESCAPES   => 3;
const my $LABEL_ESCAPES    => 7;
const my $VALIDATION_CALLS => 3;

subtest 'decorative icons are reused per request and returned independently' =>
  sub {
    my $test   = Test::Mojo->new('GPForum');
    my $sprite = '/icons.svg?v=one';
    $test->app->helper( ui_asset_url => sub { return $sprite; } );
    my $controller = $test->app->build_controller;
    my $escape     = GPForum::Web::IconSet->can('xml_escape');
    my $escapes    = 0;
    with_replaced_subs(
        'GPForum::Web::IconSet',
        {
            xml_escape => sub { ++$escapes; return $escape->(@_); },
        },
        sub {
            my $first = $controller->ui_icon('reply');
            my $again = $controller->ui_icon('reply');
            is( "$again", "$first", 'a hit preserves the markup' );
            isnt( refaddr($again), refaddr($first),
                'a hit returns a separate byte stream' );
            is( $escapes, 1, 'decorative markup is escaped only once' );
            $first->xml_escape;
            like( $controller->ui_icon('reply')->to_string,
                qr{<svg\b}msx, 'caller mutation cannot poison the cache' );
            my $other = $test->app->build_controller;
            $other->ui_icon('reply');
            is( $escapes, 2, 'another request builds its own markup' );
            $sprite = '/forum/icons.svg?v=two&safe=1';
            my $changed_request = $test->app->build_controller;
            my $changed = Mojo::DOM->new( $changed_request->ui_icon('reply') );
            is( $changed->at('use')->attr('href'), "$sprite#reply",
'a new request with a changed base or fingerprint gets fresh markup'
            );
            is( $escapes, $SPRITE_ESCAPES, 'the new sprite URL is escaped' );

            for my $label ( 'First <label>', 'Second & label' ) {
                my $dom =
                  Mojo::DOM->new( $controller->ui_icon( 'reply', $label ) );
                is( $dom->at('svg')->attr('aria-label'),
                    $label, 'explicit labels remain fresh and escaped' );
                is( $dom->at('svg')->attr('role'),
                    'img',
                    'an explicit label cannot inherit decorative semantics' );
            }
            is( $escapes, $LABEL_ESCAPES, 'labelled markup bypasses reuse' );
            ok( exception { $controller->ui_icon('reply" onload="bad') },
                'unknown icons still fail closed' );
        }
    );
  };

subtest 'source scanning preserves syntax, order, duplicates and bounds' =>
  sub {
    my $cache = GPForum::Service::Integration::SourceLinks->new;
    is_deeply( $cache->urls(undef), [],
        'missing source has no candidate URLs' );
    my $source = join "\r\n", $URL, "[$OTHER]($OTHER)", $URL,
      '```text', $OTHER, '```', "> $OTHER", "- $OTHER", "inline $OTHER";
    is_deeply(
        $cache->urls($source),
        [ $URL, $OTHER, $URL ],
        'only standalone links outside code are extracted'
    );
    my $copy = $cache->urls($source);
    $copy->[0] = 'poison';
    push @{$copy}, 'injected';
    is_deeply(
        $cache->urls($source),
        [ $URL, $OTHER, $URL ],
        'returned arrays cannot poison stored candidates'
    );
    is_deeply(
        $cache->urls("$source\n$OTHER"),
        [ $URL, $OTHER, $URL, $OTHER ],
        'a source edit is visible immediately'
    );
    is_deeply( $cache->urls( ( 'x' x $SOURCE_LIMIT ) . "\n$URL" ),
        [], 'URLs beyond the original source limit remain ignored' );
    is_deeply( $cache->urls("````\n$URL\n```\n$OTHER"),
        [$URL], 'the original fence grammar is preserved' );
    $cache->urls( q{è} x $SOURCE_LIMIT );
    ok(
        $cache->held_characters <= $cache->max_characters,
        'Unicode accounting stays inside the character budget'
    );

    my $small = GPForum::Service::Integration::SourceLinks->new(
        max_entries    => $ENTRY_LIMIT,
        max_characters => $CHARACTER_LIMIT
    );
    my $counted = GPForum::Service::Integration::SourceLinks->new(
        max_entries => $ENTRY_LIMIT );
    for my $number ( 1 .. $MANY ) {
        $small->urls("https://example.test/$number");
        $counted->urls("https://example.test/$number");
        cmp_ok( scalar keys %{ $counted->entries },
            '<=', $ENTRY_LIMIT, 'entry count is bounded' );
        cmp_ok( $small->held_characters, '<=', $CHARACTER_LIMIT,
            'source and candidate characters are bounded' );
    }
    my $kept      = { %{ $small->entries } };
    my $held      = $small->held_characters;
    my $oversized = 'x' x ( $CHARACTER_LIMIT + 1 );
    $small->urls($oversized);
    ok(
        !exists $small->entries->{$oversized},
        'an oversized entry is not kept'
    );
    is_deeply( $small->entries, $kept,
        'a rejected entry preserves reusable candidates' );
    is( $small->held_characters, $held,
        'a rejected entry preserves budget accounting' );
    my $disabled =
      GPForum::Service::Integration::SourceLinks->new( max_entries => 0 );
    is_deeply( $disabled->urls($URL),
        [$URL], 'disabled storage still extracts normally' );
    is( scalar keys %{ $disabled->entries },
        0, 'disabled storage holds no entries' );
  };

subtest 'uncacheable source cannot force rescanning a hot link' => sub {
    my $cache = GPForum::Service::Integration::SourceLinks->new(
        max_characters => $CHARACTER_LIMIT );
    my $extract   = GPForum::Service::Integration::SourceLinks->can('_extract');
    my $hot_scans = 0;
    with_replaced_subs(
        'GPForum::Service::Integration::SourceLinks',
        {
            _extract => sub ($source) {
                if ( $source eq $OTHER ) { ++$hot_scans; }
                return $extract->($source);
            },
        },
        sub {
            $cache->urls($OTHER);
            for ( 1 .. 2 ) {
                $cache->urls( 'x' x ( $CHARACTER_LIMIT + 1 ) );
                is_deeply( $cache->urls($OTHER),
                    [$OTHER], 'hot candidates stay correct' );
            }
            is( $hot_scans, 1, 'oversized misses never evict the hot source' );
        }
    );
};

subtest 'candidate hits never bypass current policy or response validation' =>
  sub {
    my $extract  = GPForum::Service::Integration::SourceLinks->can('_extract');
    my $validate = GPForum::Service::Plugin::Contract->can('response_v1');
    my ( $scans, $responses ) = ( 0, 0 );
    my $base = GPForum::Service::Integration::Registry->new(
        providers => [ GPForum::Service::Integration::Spotify->new ] );
    with_replaced_subs(
        'GPForum::Service::Integration::SourceLinks',
        {
            _extract => sub { ++$scans; return $extract->(@_); },
        },
        sub {
            with_replaced_subs(
                'GPForum::Service::Plugin::Contract',
                {
                    response_v1 =>
                      sub { ++$responses; return $validate->(@_); },
                },
                sub {
                    my $embed = $base->configured( { enabled => ['spotify'] } );
                    ok(
                        $embed->for_source($URL)->[0]{embed},
                        'enabled provider renders an embed'
                    );
                    my $link = $base->configured(
                        {
                            enabled => ['spotify'],
                            modes   => { spotify => 'link' }
                        }
                    );
                    ok(
                        !$link->for_source($URL)->[0]{embed},
                        'a hit immediately follows link-only policy'
                    );
                    is( $scans, 1,
                        'fresh request registries share syntax extraction only'
                    );
                    is( $responses, 2,
                        'each provider response is validated again' );
                    my $off = $base->configured( { enabled => [] } );
                    is_deeply( $off->for_source($URL),
                        [],
                        'a warm candidate cannot enable a disabled provider' );
                    is( $responses, 2, 'disabled providers are not called' );
                    $embed->for_source('ordinary text');
                    $link->for_source('ordinary text');
                    is( $scans, 2, 'empty results are reused too' );
                    my $resolve = GPForum::Service::Integration::Spotify->can(
                        'resolve_link_v1');
                    with_replaced_subs(
                        'GPForum::Service::Integration::Spotify',
                        {
                            resolve_link_v1 => sub (@args) {
                                my $result = $resolve->(@args);
                                $result->{embed}{url} =
                                  'https://evil.example/frame';
                                return $result;
                            },
                        },
                        sub {
                            is_deeply( $embed->for_source($URL), [],
'a later invalid provider response is rejected on a candidate hit'
                            );
                        }
                    );
                    is( $responses, $VALIDATION_CALLS,
                        'the invalid response also crosses validation' );
                    my $other = GPForum::Service::Integration::Registry->new(
                        providers =>
                          [ GPForum::Service::Integration::Spotify->new ],
                        enabled => ['spotify']
                    );
                    $other->for_source('ordinary text');
                    is( $scans, $VALIDATION_CALLS,
                        'independent applications do not share source caches' );
                }
            );
        }
    );
  };

done_testing();
1;
