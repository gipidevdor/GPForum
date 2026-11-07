# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use utf8;

use Const::Fast;
use Mojo::File qw(path);
use Test::More;
use Test::Mojo;

use lib 'lib';
use lib 't/lib';

use GPForum::Config;
use GPForum::Service::I18N;
use GPForum::Service::Identity::Mailer;
use GPForum::Test::ForumWebServices;
use GPForum::Web::SiteIcon;

our $VERSION = '0.001';

const my $HTTP_OK => 200;

# An installation is called by its own name, not the software's: every page,
# mail and notification says the name it is given, and nothing the reader
# sees names the code that runs it.

my $defaults = GPForum::Config->from_environment( {} );
is( $defaults->site_name,        'Forum', 'a forum not yet named is "Forum"' );
is( $defaults->site_description, q{},     'and has no line under its name' );

my $named = GPForum::Config->from_environment(
    {
        GPFORUM_SITE_NAME        => 'Circolo Fotografico',
        GPFORUM_SITE_DESCRIPTION => 'Fotografia a Roma.',
    }
);
is( $named->site_name,        'Circolo Fotografico', 'the name is a setting' );
is( $named->site_description, 'Fotografia a Roma.',  'and so is its line' );

my $i18n = GPForum::Service::I18N->new( site_name => 'Circolo' );
is( $i18n->translate( 'en', 'app.name' ), 'Circolo', 'the name is the name' );
is(
    $i18n->translate( 'it', 'notifications.digest.subject.daily' ),
    'Il tuo riepilogo giornaliero di Circolo',
    'a message says it where it said the software'
);
is(
    $i18n->translate( 'en', 'mentions.email_subject', { actor => '@ada' } ),
    '@ada mentioned you on Circolo',
    'beside the variables the message is given'
);
is( $i18n->plain_messages('en')->{'app.name'},
    'Circolo', 'and a page reads it as plain text' );

is(
    GPForum::Service::Identity::Mailer->new( config => $named )
      ->i18n->translate( 'en', 'app.name' ),
    'Circolo Fotografico',
    'mail says the configured name'
);

for my $locale (qw(en it)) {
    my $catalog = path("locale/$locale.po")->slurp;
    $catalog =~ s/^[#].*$//gmsx;
    $catalog =~ s/^"Project-Id-Version:.*$//gmsx;
    unlike( $catalog, qr/GPForum|BSD/msx,
        "$locale.po names neither the software nor its licence" );
}

like(
    GPForum::Web::SiteIcon->svg('circolo'),
    qr{<title[^>]*>circolo</title>}msx,
    'the approved icon keeps the site name'
);
like( GPForum::Web::SiteIcon->svg('<x>'),
    qr{>&lt;x&gt;</title>}msx, 'escaped as XML' );
like( GPForum::Web::SiteIcon->svg('Écoles'),
    qr{>Écoles</title>}msx, 'the complete Unicode name is preserved' );

{
    local $ENV{GPFORUM_SITE_NAME}        = 'Officina';
    local $ENV{GPFORUM_SITE_DESCRIPTION} = 'Perl e server fatti in casa.';
    my $test = Test::Mojo->new('GPForum');
    $test->app->helper(
        gp_home_page_reader => sub {
            return GPForum::Test::ForumWebServices->new;
        }
    );

    $test->get_ok(q{/})->status_is($HTTP_OK);
    $test->text_is( 'title' => 'Officina', 'the page is titled by the name' );
    $test->text_is( 'h1'    => 'Officina', 'and headed by it' );
    $test->text_is( '.brand__name' => 'Officina', 'and so is the bar' );
    $test->text_is(
        '.ui-page-description' => 'Perl e server fatti in casa.',
        'with the line under it'
    );
    $test->element_exists_not( 'img[src*="gpforum"]',
        'the software mark is not shown' );

    # What the forum says of itself -- its head, bar and foot -- never names
    # the software or its licence. What members wrote is theirs: the test
    # forum has a member whose display name is "GPForum Contributors".
    my $dom = $test->tx->res->dom;
    for my $part ( 'head', '.site-header', '.site-footer' ) {
        unlike( $dom->at($part)->to_string,
            qr/BSD|GPForum/msx,
            "$part names neither the software nor its licence" );
    }

    $test->get_ok('/icon.svg')->status_is($HTTP_OK);
    $test->content_type_like(qr{image/svg[+]xml}msx);
    $test->content_like( qr{>Officina</title>}msx,
        'the browser icon names the site' );
}

done_testing();

1;
