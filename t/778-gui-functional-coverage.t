# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Const::Fast;
use Test::More;
use Test::Mojo;
use Mojo::File qw(path);
use List::Util qw(any);
our $VERSION = '0.001';
const my $HTTP_OK => 200;

# A menu-only check misses mutations, nested pages and generated form URLs.
# Inspect the actual router, including the five security routes made in a loop.
my $test    = Test::Mojo->new('GPForum');
my @pending = ( $test->app->routes );
my %routes;
while (@pending) {
    my $route = shift @pending;
    push @pending, @{ $route->children };
    my $name = $route->name;
    if ( defined $name && length $name ) { $routes{$name} = 1; }
}
my @templates =
  path('templates')->list_tree( { dir => 0 } )->grep(qr/[.]ep\z/msx)->each;
my @sources = map { $_->slurp } @templates;
push @sources, path('lib/GPForum/Web/Navigation.pm')->slurp;

# These protocols are reached by consumers rather than human-facing controls.
# Their policy and authentication remain in the endpoint's own controller.
my %protocol = (
    push_worker =>
      'browser Service Worker resource, registered from device settings',
    push_configuration =>
      'authenticated browser configuration and consent state',
    push_confirm =>
      'encrypted subscription receipt proof from the Service Worker',
    robots           => 'crawler policy',
    sitemap          => 'crawler sitemap index',
    sitemap_page     => 'crawler sitemap page',
    websub_subscribe => 'feed hub subscription protocol',
    security_txt     => 'security contact discovery',
    health           => 'operator health API; displayed by the status console',
    health_live      => 'liveness probe',
    health_ready     => 'readiness probe',
    metrics          => 'monitoring collector; displayed by the status console',
    openid_callback  => 'external identity provider callback',
    thread_canonical => 'canonical redirect destination from thread navigation',
);

# A redirect or delivered token is a real entrance to these screens.
my %flow = (
    login_second_factor =>
      [ 'lib/GPForum/Controller/Identity.pm', 'login_second_factor' ],
    password_reset_form =>
      [ 'lib/GPForum/Service/Identity/Mailer.pm', '/password/reset/' ],
    email_confirm_form =>
      [ 'lib/GPForum/Service/Identity/Mailer.pm', '/email/confirm/' ],
    email_verify_form =>
      [ 'lib/GPForum/Service/Identity/Mailer.pm', '/email/verify/' ],
    unsubscribe =>
      [ 'lib/GPForum/Worker/Handler/NotificationMail.pm', '/unsubscribe/' ],
);

# Controller-generated destinations need a producer and a form consuming them.
my %produced = (
    pending_post_withdraw => [
        'lib/GPForum/Controller/Forum/Pending.pm',
        'templates/forum/pending.html.ep',
        'withdraw_url'
    ],
    draft_delete => [
        'lib/GPForum/Controller/Forum/Drafts.pm',
        'templates/forum/drafts.html.ep',
        'delete_url'
    ],
    moderation_review_approve => [
        'lib/GPForum/Controller/Moderation/Review.pm',
        'templates/moderation/review.html.ep',
        'approve_url'
    ],
    moderation_review_reject => [
        'lib/GPForum/Controller/Moderation/Review.pm',
        'templates/moderation/review.html.ep',
        'reject_url'
    ],
);
for my $name ( sort keys %routes ) {
    next if _special_binding($name);
    my $present =
      any { /['"]\Q$name\E['"]|\$paths->[{]\Q$name\E[}]/msx } @sources;
    ok( $present,
        "$name has a menu, link, form or browser enhancement binding" );
}
for my $classified ( sort keys %protocol, keys %flow, keys %produced ) {
    ok( $routes{$classified}, "classified route $classified still exists" );
}

sub _special_binding ($name) {
    if ( $protocol{$name} ) {
        pass("$name: $protocol{$name}");
        return 1;
    }
    if ( my $flow = $flow{$name} ) {
        my ( $file, $marker ) = @{$flow};
        like( path($file)->slurp, qr/\Q$marker\E/msx,
            "$name has a redirect or delivered-link entrance" );
        return 1;
    }
    if ( my $binding = $produced{$name} ) {
        my ( $producer, $consumer, $field ) = @{$binding};
        like( path($producer)->slurp,
            qr/\Q$name\E/msx, "$name URL is produced" );
        like(
            path($consumer)->slurp,
            qr/action=[^\n]*\Q$field\E/msx,
            "$name is submitted by its GUI form"
        );
        return 1;
    }
    if ( $name eq 'push_register' || $name eq 'push_revoke' ) {
        like( path('templates/identity/settings.html.ep')->slurp,
            qr/data-push-settings/msx, "$name has a device settings control" );
        my $marker =
          $name eq 'push_register' ? 'write("register"' : 'write("revoke"';
        like( path('assets/js/push.js')->slurp,
            qr/\Q$marker\E/msx,
            "$name is submitted by the browser enhancement" );
        return 1;
    }
    return 0;
}

subtest 'every asset named by the GUI is actually served' => sub {
    my %assets = map { $_ => 1 }
      map { /ui_asset_url[(]'([^']+)'[)]/gmsx } @sources;
    my $controller = $test->app->build_controller;
    my $reachable  = scalar keys %assets ? 1 : 0;
    for my $asset ( sort keys %assets ) {
        my $url = $controller->ui_asset_url($asset);
        $test->get_ok("$url")
          ->status_is( $HTTP_OK, "$asset reaches the browser" );
        $reachable &&= $test->tx->res->code == $HTTP_OK;
    }
    ok( $reachable, 'GUI assets are all reachable' );
};
done_testing();
1;
