# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Mojo::Base -strict, -async_await;
use v5.40;
use Test::More;
use Test::Mojo;
use Const::Fast;
use List::Util qw(any);
use Mojo::File qw(path);
use lib 'lib';
use lib 't/lib';
use GPForum::Web::Navigation;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';
const my $HTTP_OK => 200;
my $menu = GPForum::Web::Navigation->new;

sub _routes ($context) {
    return [
        map {
            map { $_->{route} }
              @{ $_->{links} }
        } @{ $menu->groups($context) }
    ];
}

sub _contains ( $routes, $name ) {
    return any { $_ eq $name } @{$routes};
}

sub _matches ( $routes, $pattern ) {
    return any { $_ =~ $pattern } @{$routes};
}
my $guest = _routes( {} );
ok( !_matches( $guest, qr/\A(?:settings|moderation_|admin_)/msx ),
    'guest menu has no account or staff tools' );
ok( _contains( $guest, 'public_feed' ), 'outgoing feed is discoverable' );
my $member = _routes( { member => 1, username => 'reader' } );
for my $route (
    qw(profile settings settings_avatar settings_security settings_openid member_relations privacy_dashboard pending_posts mentions messages)
  )
{
    ok( _contains( $member, $route ), "member can find $route" );
}
my $moderator =
  _routes( { member => 1, permissions => { 'thread.moderate' => 1 } } );
ok(
    _contains( $moderator, 'moderation_media' ),
    'media moderator finds the upload review queue'
);
ok(
    !_matches( $moderator, qr/\Aadmin_/msx ),
    'moderator has no administration links'
);
ok(
    !_contains( $moderator, 'moderation_reports' ),
    'a media permission does not grant the report queue'
);
my %all = map { $_ => 1 }
  qw(admin_console.view thread.moderate report.view_queue moderation_action.view suspension.view privacy_rights.view);
my $admin = _routes( { member => 1, permissions => \%all } );
for my $route ( @{ $menu->routes } ) {
    next if $route eq 'profile';
    ok( _contains( $admin, $route ),
        "permitted administrator can find $route" );
}
my $first = $menu->groups( { member => 1, username => 'one' } );
$first->[0]{links}[0]{label_key} = 'changed';
isnt(
    $menu->groups( { member => 1, username => 'two' } )
      ->[0]{links}[0]{label_key},
    'changed',
    'one request cannot mutate another menu'
);

# Standalone pages must have a GUI destination. Login flows are reached
# through account forms; tag-filter results require the Tags form;
# machine endpoints are not ordinary menu pages.
my %special = map { $_ => 1 }
  qw(web_manifest push_worker push_configuration navigation robots site_icon sitemap security_txt signing_keys health health_live health_ready metrics notifications_summary search_autocomplete register login openid_callback login_second_factor password_reset_request email_verify_request tagged_threads);
my %catalogued   = map { $_ => 1 } @{ $menu->routes };
my $route_source = path('lib/GPForum/Bootstrap/Routes.pm')->slurp;
while ( $route_source =~
    /routes->get[(]'([^']+)'[)][^;]*?->name[(]'([^']+)'[)];/gmsx )
{
    my ( $address, $route_name ) = ( $1, $2 );
    if ( $address =~ /[:<\x23]/msx || $special{$route_name} ) { next; }
    ok( $catalogued{$route_name},
        "standalone page $route_name is reachable from the menu" );
}

my $test       = Test::Mojo->new('GPForum');
my $controller = $test->app->build_controller;
for my $group ( @{ $menu->groups( { member => 1, permissions => \%all } ) } ) {
    for my $link ( @{ $group->{links} } ) {
        ok( $test->app->routes->lookup( $link->{route} ),
            "registered route $link->{route}" );
        for my $locale (qw(en it)) {
            ok(
                $controller->i18n_service->has_key(
                    $locale, $link->{label_key}
                ),
                "$locale label $link->{label_key}"
            );
        }
    }
}
$test->get_ok('/menu')->status_is($HTTP_OK);
$test->element_exists('header a.site-menu-link[href="/menu"]');
$test->element_exists('a[href="/tags#tag-filter-form"]');
$test->element_exists_not('a[href="/tagged"]');
$test->element_exists_not('a[href="/moderation/media"]');
$test->header_is( 'Cache-Control' => 'private, no-store' );
my $routes = $test->app->routes;
$routes->get('/__test/menu/session')->to(
    cb => sub ($c) {
        $c->session( user_id => 'menu-reader' );
        return $c->render( text => 'ready' );
    }
);
my $calls = 0;
with_replaced_subs(
    'GPForum::Service::Admin::PermissionGate',
    {
        navigation_context_p => async sub {
            $calls++;
            return {
                available   => 1,
                username    => 'reader',
                permissions => { 'thread.moderate' => 1 }
            };
        },
    },
    sub {
        $test->get_ok('/__test/menu/session')->status_is($HTTP_OK);
        $test->get_ok('/menu')->status_is($HTTP_OK);
        $test->element_exists('a[href="/moderation/media"]');
        $test->element_exists('a[href="/u/reader"]');
        $test->element_exists_not('a[href="/admin"]');
        is( $calls, 1, 'one permission lookup serves the entire menu' );
        return;
    }
);
with_replaced_subs(
    'GPForum::Service::Admin::PermissionGate',
    {
        navigation_context_p => async
          sub { die "permission store unavailable\n"; },
    },
    sub {
        $test->get_ok('/menu')->status_is($HTTP_OK);
        $test->element_exists('a[href="/settings"]');
        $test->element_exists_not('a[href="/moderation/media"]');
        $test->content_like(qr/Staff[ ]tools[ ]could[ ]not[ ]be[ ]loaded/msx);
        return;
    }
);
done_testing();
1;
