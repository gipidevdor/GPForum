# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use lib 'lib';
use lib 't/lib';

use Const::Fast;
use GPForum::Test::ResponderController;
use GPForum::Web::LegalAccess;
use Test::Mojo;
use Test::More;

our $VERSION = '0.001';

const my $HTTP_OK        => 200;
const my $HTTP_NOT_FOUND => 404;
const my $NOW            => 1_793_491_200;    # 2026-11-01T00:00:00Z
const my $COOKIES        => 4;

# The four pages in the colophon, each in the order of the text it follows
# (basis_key): the terms after the Digital Services Act, the privacy notice
# after GDPR article 13, the cookie notice after the Garante's guidelines of
# 10 June 2021, the legal notice after D.Lgs. 70/2003 article 7 and the
# Act's points of contact; and security.txt after RFC 9116.

my $access = GPForum::Web::LegalAccess->new;
for my $page (qw(terms privacy cookies notice)) {
    ok( $access->known_page($page), "known_page accepts $page" );
}
ok( !$access->known_page('unknown'), 'known_page rejects an unknown page' );
is( $access->template, 'legal/page', 'template is the shared legal page' );

my $facts = {
    name      => 'Associazione Esempio',
    email     => 'info@forum.test',
    languages => [qw(Italiano English)],
};
my $payload =
  $access->page_payload( 'privacy', 'https://forum.gp/legal/privacy', $facts );
is( $payload->{basis_key},  'legal.privacy.basis', 'the page names its basis' );
is( $payload->{incomplete}, 0, 'an operator with a name is complete' );
is_deeply(
    [ map { $_->{id} } @{ $payload->{sections} } ],
    [
        map { "legal-privacy-$_" }
          qw(controller data purposes recipients transfers retention rights
          complaint provision automated)
    ],
    'the privacy notice keeps the order of GDPR article 13'
);
my ($controller) = @{ $payload->{sections} };
is_deeply(
    [
        map { [ $_->{field}, $_->{value}, $_->{href} ] }
          @{ $controller->{facts} }
    ],
    [
        [ name    => 'Associazione Esempio', undef ],
        [ address => undef,                  undef ],
        [ email   => 'info@forum.test',      'mailto:info@forum.test' ],
    ],
    'the controller is named, a missing address says so, an email links,'
      . ' and an officer nobody designated is left out'
);
is(
    $payload->{page_metadata}{canonical},
    'https://forum.gp/legal/privacy',
    'page_payload stores the canonical URL'
);
is( $access->page_payload( 'terms', undef, {} )->{incomplete},
    1, 'with no operator name the page says it is incomplete' );
ok(
    !$access->page_payload('unknown'),
    'page_payload is empty for an unknown page'
);
is_deeply(
    [
        map { $_->{id} }
          @{ $access->page_payload( 'terms', undef, $facts )->{sections} }
    ],
    [
        map { "legal-terms-$_" }
          qw(provider accounts conduct moderation automated notices reasons
          complaints changes)
    ],
    'the terms follow the Digital Services Act, articles 14 to 21'
);

my $rows = $access->cookie_rows(
    session_name       => 'mojolicious',
    session_seconds    => 2_592_000,
    visitor_seconds    => 3_600,
    locale_name        => 'gpforum_locale',
    theme_name         => 'gpforum_theme',
    device_name        => 'gpforum_device',
    preference_seconds => 31_536_000,
);
is_deeply(
    [ map { [ $_->{name}, $_->{duration} ] } @{$rows} ],
    [
        [ mojolicious    => { days => 30, hours => 1 } ],
        [ gpforum_locale => { days => 365 } ],
        [ gpforum_theme  => { days => 365 } ],
        [ gpforum_device => { days => 365 } ],
    ],
    'every cookie is listed with its lifetime'
);

my $txt = $access->security_txt(
    contact   => 'mailto:security@forum.test',
    base_url  => 'https://forum.test',
    languages => [qw(it en)],
    now       => $NOW,
);
is(
    $txt,
    join( "\n",
        'Contact: mailto:security@forum.test',
        'Expires: 2027-04-30T00:00:00Z',
        'Preferred-Languages: it, en',
        'Canonical: https://forum.test/.well-known/security.txt' )
      . "\n",
    'security.txt carries Contact, an RFC 3339 Expires under a year away,'
      . ' languages and its canonical address'
);
like(
    $access->security_txt(
        operator_email => 'info@forum.test',
        base_url       => 'https://forum.test',
        now            => $NOW,
    ),
    qr/\A Contact: [ ] mailto:info[@]forum[.]test \n/msx,
    'with no security contact the operator email is the contact'
);
ok(
    !defined $access->security_txt(
        base_url => 'https://forum.test',
        now      => $NOW
    ),
    'with no contact at all there is no security.txt'
);

my $html = GPForum::Test::ResponderController->new;
$access->render_page( $html, $payload );
is( $html->last_render->{status}, $HTTP_OK, 'render_page uses HTTP 200' );

{
    local $ENV{GPFORUM_OPERATOR_NAME}  = 'Associazione Esempio';
    local $ENV{GPFORUM_OPERATOR_EMAIL} = 'info@forum.test';
    my $test = Test::Mojo->new('GPForum');

    $test->get_ok('/legal/terms')->status_is($HTTP_OK);
    $test->text_is( 'h1' => 'Terms of use' );
    $test->content_like(
        qr/Article [ ] 14 [ ] of [ ] Regulation [ ] [(]EU[)] [ ] 2022\/2065/msx
    );
    $test->element_exists('article[aria-labelledby="legal-terms-heading"]');
    $test->element_exists('h2#legal-terms-notices');
    $test->element_exists('nav a[href="#legal-terms-complaints"]');
    $test->element_exists('a[href="/legal/notice"]');
    $test->element_exists_not('.ui-alert');
    $test->element_exists( 'link[rel="canonical"][href$' . '="/legal/terms"]' );

    $test->get_ok('/legal/privacy')->status_is($HTTP_OK);
    $test->text_is( 'h1' => 'Privacy notice' );
    $test->text_is(
        'dd a[href="mailto:info@forum.test"]' => 'info@forum.test' );
    $test->content_like(
        qr/Article [ ] 13 [ ] of [ ] Regulation [ ] [(]EU[)] [ ] 2016\/679/msx);

    $test->get_ok('/legal/cookies')->status_is($HTTP_OK);
    $test->text_is( 'h1' => 'Cookie notice' );
    $test->element_count_is( 'tbody tr', $COOKIES );
    $test->text_is( 'tbody tr:nth-child(2) th code'       => 'gpforum_locale' );
    $test->text_is( 'tbody tr:nth-child(2) td:last-child' => '365 days' );

    $test->get_ok('/legal/notice')->status_is($HTTP_OK);
    $test->text_is( 'h1' => 'Legal notice' );
    $test->text_like( 'dd' => qr/Associazione [ ] Esempio/msx );
    $test->element_exists('a[href$="/.well-known/security.txt"]');

    $test->get_ok('/.well-known/security.txt')->status_is($HTTP_OK);
    $test->content_type_like(qr{\A text/plain}msx);
    $test->content_like(qr/^Contact: [ ] mailto:info[@]forum[.]test$/msx);
    $test->content_like(qr/^Expires: [ ] \d{4}-\d\d-\d\dT00:00:00Z$/msx);

    $test->get_ok( '/legal/terms' => { Accept => 'application/json' } )
      ->status_is($HTTP_OK);
    $test->json_is( '/page'      => 'terms' );
    $test->json_is( '/basis_key' => 'legal.terms.basis' );

    $test->get_ok( '/legal/privacy' => { 'Accept-Language' => 'it' } );
    $test->text_is( 'h1' => 'Informativa privacy' );
    $test->content_like(qr/Garante [ ] per [ ] la [ ] protezione/msx);

    $test->get_ok(q{/})->element_exists('footer a[href="/legal/notice"]');
}

{
    my $test = Test::Mojo->new('GPForum');
    $test->get_ok('/legal/notice')->status_is($HTTP_OK);
    $test->element_exists('.ui-alert');
    $test->get_ok('/.well-known/security.txt')->status_is($HTTP_NOT_FOUND);
}

done_testing();

1;
