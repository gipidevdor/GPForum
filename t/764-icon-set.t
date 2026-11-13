# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use utf8;

use Const::Fast;
use Mojo::DOM;
use Mojo::File qw(path);
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';
use GPForum::Test::ForumWebServices;
use GPForum::Web::IconSet;
use GPForum::X::Argument;

our $VERSION = '0.001';

const my $HTTP_OK          => 200;
const my $HTTP_BAD_REQUEST => 400;
const my $SYMBOL_COUNT     => 36;
const my $UNSAFE_ELEMENTS =>
  qr{<(?:script|style|foreignObject|image|animate|a)\b}imsx;
const my $EVENT_HANDLER => qr{\bon\w+\s*=}imsx;
const my $EXTERNAL_URL  => qr{https?://(?!www[.]w3[.]org)}imsx;

my $names   = GPForum::Web::IconSet->names;
my $sprite  = path('assets/img/gpforum-icons.svg')->slurp;
my $dom     = Mojo::DOM->new->xml(1)->parse($sprite);
my @symbols = $dom->find('symbol')->map( sub { $_->attr('id') } )->each;
is( scalar @symbols, $SYMBOL_COUNT, 'all approved vectors are shipped' );
is_deeply(
    [ sort @symbols ],
    [ sort @{$names} ],
    'every supported name resolves, without duplicate or orphan symbols'
);
unlike(
    $sprite,
    qr{$UNSAFE_ELEMENTS|$EVENT_HANDLER|$EXTERNAL_URL}msx,
    'the sprite has no script, animation or external content'
);

for my $symbol ( $dom->find('symbol')->each ) {
    is( $symbol->attr('viewBox'),
        '0 0 24 24', $symbol->attr('id') . ' shares the optical grid' );
}

my $test       = Test::Mojo->new('GPForum');
my $controller = $test->app->build_controller;
my $decorative = Mojo::DOM->new( $controller->ui_icon('reply') )->at('svg');
is( $decorative->attr('aria-hidden'),
    'true', 'an adjacent label is not repeated' );
is( $decorative->attr('focusable'),
    'false', 'SVG never becomes an extra tab stop' );
like(
    $decorative->at('use')->attr('href'),
    qr{\A/gpforum-icons[.]svg[?]v=[[:xdigit:]]{12}[#]reply\z}msx,
    'the symbol uses a fingerprinted local sprite'
);
my $label = q{A <warning> & "attention"};
my $informative =
  Mojo::DOM->new( $controller->ui_icon( 'warning', $label ) )->at('svg');
is( $informative->attr('role'), 'img',
    'a standalone symbol has an image role' );
is( $informative->attr('aria-label'),
    $label, 'an informative label round-trips escaped' );
ok( !$informative->attr('aria-hidden'), 'an informative symbol is not hidden' );

my $favicon = Mojo::DOM->new->xml(1)
  ->parse( GPForum::Web::IconSet->document( 'orbit', $label ) );
is( $favicon->at('title')->text,
    $label, 'the browser icon preserves its escaped site title' );
my $orbit_symbol = $dom->at('symbol[id="orbit"]');
is_deeply(
    [ $favicon->find('path')->map( sub { $_->attr('d') } )->each ],
    [ $orbit_symbol->find('path')->map( sub { $_->attr('d') } )->each ],
    'the browser icon uses the approved orbit geometry, not another drawing'
);
unlike(
    path('assets/css/gpforum-ssr.css')->slurp,
    qr{data:image/svg|[.]reading-step__icon}msx,
    'no independent inline-SVG or CSS-drawn reading icon remains'
);

for my $bad ( q{<script>}, q{reply" onload="alert(1)},
    'https://example.test/x', undef )
{
    my $error;
    try { $controller->ui_icon($bad); }
    catch ($caught) { $error = $caught; };
    ok( GPForum::X::Argument->caught($error),
        'unrecognised names fail closed' );
}

my $routes = $test->app->routes;
$routes->get('/__test/icon-reactions')->to(
    cb => sub ($c) {
        $c->stash(
            post => {
                post_id   => 'post-1',
                can_react => 1,
                reactions => [
                    {
                        reaction   => 'heart',
                        reacted    => 1,
                        count      => 3,
                        command_id => 'heart'
                    },
                    {
                        reaction   => 'laugh',
                        reacted    => 0,
                        count      => 0,
                        command_id => 'laugh'
                    },
                ],
            }
        );
        return $c->render( template => 'forum/_reactions', layout => undef );
    }
);
$test->get_ok('/__test/icon-reactions')->status_is($HTTP_OK);
$test->element_exists(
    'button[aria-pressed="true"] .post__reaction-state svg[aria-hidden="true"]'
);
$test->element_exists(
    'button[aria-pressed="false"] svg.ui-icon--emote[aria-hidden="true"]');
$test->element_exists_not('button[aria-pressed="false"] .post__reaction-state');
$test->element_exists('button[aria-pressed="true"][aria-label*="3"]');
$test->element_exists_not('button[aria-pressed="false"] .post__reaction-count');
$test->text_is( 'button[aria-pressed="true"] .post__reaction-count', '3' );
my $sprite_url = $decorative->at('use')->attr('href') =~ s/[#].*\z//rmsx;
$test->get_ok($sprite_url)->status_is($HTTP_OK);
$test->content_type_like(qr{image/svg[+]xml}msx);

# Check actual pages as well as the symbol helper: visible text, form
# controls and error semantics must survive the template integration.
my $services = GPForum::Test::ForumWebServices->new;
for my $helper (
    qw(gp_category_reader gp_search_service gp_rate_limiter gp_thread_tags))
{
    $test->app->helper( $helper => sub { return $services; } );
}
$test->get_ok( '/login' => { 'Accept-Language' => 'en' } )->status_is($HTTP_OK);
$test->element_exists(
'form[action="/login"] > button[type="submit"] svg[aria-hidden="true"] use[href$="#user"]'
);
$test->text_is( 'form[action="/login"] > button[type="submit"]', 'Login' );
my $response = $test->tx->res;
my $form     = $response->dom->at('form[action="/login"]');
my %request  = map { $_ => $form->at(qq{input[name="$_"]})->attr('value') }
  qw(csrf_token command_id);
$test->post_ok(
    '/login' => form => { %request, identifier => q{}, password => q{} } )
  ->status_is($HTTP_BAD_REQUEST);
$test->element_exists(
'#login-error-summary[role="alert"] svg[aria-hidden="true"] use[href$="#warning"]'
);
$test->element_exists('#login-error-summary a[href="#login-identifier"]');

$test->get_ok( '/categories' => { 'Accept-Language' => 'en' } )
  ->status_is($HTTP_OK);
$test->element_exists(
    '.ui-action-list a[href="/new-thread"] svg use[href$="#compose"]');
$test->element_exists(
    '.ui-action-list a[href="/search"] svg use[href$="#search"]');
$test->get_ok( '/search?q=Perl' => { 'Accept-Language' => 'en' } )
  ->status_is($HTTP_OK);
$test->element_exists(
    '.search-form button[type="submit"] svg use[href$="#search"]');

done_testing;

1;
