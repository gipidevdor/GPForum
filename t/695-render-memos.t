# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use lib 'lib', 't/lib';
use Const::Fast;
use Scalar::Util qw(refaddr);
use Test::Mojo;
use Test::More;

use GPForum::Service::I18N;
use GPForum::Service::I18N::Locale;
use GPForum::Theme::Registry;

our $VERSION = '0.001';

# What a page asks for many times is computed once and kept: a counted
# message, a time element, a theme's contract, a locale's metadata. Each is
# kept without changing what is answered, what is logged, or what a caller
# may do with the answer.

const my $SEVERAL      => 3;
const my $COUNTED_KEPT => 4_096;
const my $FALLBACK_KEY => 'demo.english_only';
const my $SIGNED_IN_AT => '2026-05-23T12:00:00Z';

sub _catalogs {
    return {
        en => {
            'demo.items' => { one => '{count} item', other => '{count} items' },
            'demo.plain' => 'Plain',
            'demo.placed' => 'Post {position}',
            $FALLBACK_KEY =>
              { one => '{count} thing', other => '{count} things' },
        },
        it => {
            'demo.items' => { one => '{count} voce', other => '{count} voci' },
            'demo.plain' => 'Semplice',
        },
    };
}

subtest 'a counted message is composed once' => sub {
    my @logged;
    my $i18n = GPForum::Service::I18N->new(
        catalogs           => _catalogs(),
        missing_key_logger => sub ($entry) { push @logged, $entry },
    );
    is(
        $i18n->translate_count( 'it', 'demo.items', $SEVERAL ),
        "$SEVERAL voci",
        'the plural form for the count'
    );
    is(
        $i18n->translate_count( 'it', 'demo.items', $SEVERAL ),
        "$SEVERAL voci",
        'and the same answer again'
    );
    is( scalar keys %{ $i18n->counted_messages },
        1, 'kept once, by locale, key and count' );

    my %variables = ( name => 'Ada' );
    $i18n->translate_count( 'it', 'demo.items', 1, \%variables );
    is( $variables{count}, 1,
        'the count still goes into the variables passed' );
    is( scalar keys %{ $i18n->counted_messages },
        1, 'and a message with other variables is not kept' );

    for ( 1 .. 2 ) {
        $i18n->translate_count( 'it', $FALLBACK_KEY, 1 );
    }
    is( scalar( grep { $_->{reason} eq 'fallback' } @logged ),
        2, 'a fallback to English is logged every time' );
    is( scalar keys %{ $i18n->counted_messages }, 1, 'because it is not kept' );

    for my $count ( 1 .. $COUNTED_KEPT ) {
        $i18n->translate_count( 'en', 'demo.items', $count );
    }
    cmp_ok( scalar keys %{ $i18n->counted_messages },
        '<=', $COUNTED_KEPT, 'the table stays within its bound' );
};

subtest 'the plain messages of a locale' => sub {
    my $i18n = GPForum::Service::I18N->new( catalogs => _catalogs() );
    is_deeply(
        $i18n->plain_messages('en'),
        { 'demo.plain' => 'Plain' },
        'plain text only: no placeholder, no plural forms'
    );
    is_deeply(
        $i18n->plain_messages('it'),
        { 'demo.plain' => 'Semplice' },
        'the locale\'s own, with nothing taken from English'
    );
    is_deeply( $i18n->plain_messages('fr'),
        {}, 'none for a locale that is not supported' );
};

subtest 'a theme and a locale are read, not rebuilt' => sub {
    my $registry = GPForum::Theme::Registry->new;
    my $theme    = $registry->theme('dark');
    $theme->{color_scheme} = 'changed';
    $theme->{tokens}{background} = 'changed';
    is( $registry->color_scheme('dark'),
        'dark',
        'a caller changing its copy of a theme changes nothing shared' );
    is(
        $registry->token( 'dark', 'background' ),
        $registry->theme('dark')->{background},
        'nor its tokens'
    );
    is_deeply(
        [ map { $_->{color_scheme} } @{ $registry->theme_options('dark') } ],
        [
            map { $registry->theme($_)->{color_scheme} }
              @{ $registry->supported_themes }
        ],
        'the options read the same contracts'
    );

    my $locales = GPForum::Service::I18N::Locale->new(
        default_locale => 'en',
        supported      => { en => 1, it => 1 },
    );
    my $metadata = $locales->metadata('it');
    $metadata->{direction} = 'changed';
    is( $locales->direction('it'),
        'ltr', 'nor does a caller changing its copy of a locale\'s metadata' );
};

subtest 'a time element is written once for what decides it' => sub {
    my $test    = Test::Mojo->new('GPForum');
    my $member  = $test->app->build_controller;
    my $visitor = $test->app->build_controller;
    $member->session( user_id => 'user-1' );
    $member->stash( ui_locale => 'en' );
    $visitor->stash( ui_locale => 'en' );
    my $signed_in = $member->ui_timestamp($SIGNED_IN_AT);
    my $anonymous = $visitor->ui_timestamp($SIGNED_IN_AT);
    isnt( "$signed_in", "$anonymous",
        'a reader signed in and a visitor do not share an element' );
    is(
        "$signed_in",
        $member->ui_timestamp($SIGNED_IN_AT)->to_string,
        'the same element for the same reader and instant'
    );
    isnt(
        refaddr($signed_in),
        refaddr( $member->ui_timestamp($SIGNED_IN_AT) ),
        'each in an object of its own, which a caller may change'
    );
};

done_testing();

1;
