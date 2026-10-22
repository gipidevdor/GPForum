# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Operations::SecurityTelemetry;
use GPForum::Test::AllowLimiter;
use GPForum::Test::AllowPermissionGate;
use GPForum::Test::ForumWebServices;
use GPForum::Test::SuspendedParticipation;
use GPForum::Web::ForumAccess;

our $VERSION = '0.001';

const my $HTTP_OK        => 200;
const my $HTTP_FORBIDDEN => 403;
const my $JSON           => { Accept => 'application/json' };
const my $POST_ID        => '018f1000-0000-7000-8000-000000000101';
const my $THREAD_ID      => '018f1000-0000-7000-8000-000000000201';
const my $ATTACHMENT_ID  => '018f1000-0000-7000-8000-000000000301';

# A suspended member takes no part in the forum: no like, no reaction, no
# report, no attachment, no words on their profile, as no post. Every one of these writes is refused with 403
# before any store sees it, and recorded as a suspended_user_block.

my $telemetry = GPForum::Service::Operations::SecurityTelemetry->new;
my $test      = Test::Mojo->new('GPForum');
$test->app->log->level(q{fatal});
_install_fakes( $test->app );

my $access = GPForum::Web::ForumAccess->new;
for my $action (qw(post.like post.unlike post.react post.unreact report.create))
{
    ok(
        $access->requires_participation($action),
        "$action needs a member who may participate"
    );
}

$test->get_ok('/__test/session/member-1')->status_is($HTTP_OK);
$test->get_ok( '/__test/csrf' => $JSON )->status_is($HTTP_OK);
my $response = $test->tx->res;
my $csrf     = $response->json->{csrf_token};

my @writes = (
    "/p/$POST_ID/like",
    "/p/$POST_ID/like/remove",
    "/p/$POST_ID/react/heart",
    "/p/$POST_ID/react/heart/remove",
    "/p/$POST_ID/report",
    "/t/$THREAD_ID/report",
    '/u/somebody/report',
    "/p/$POST_ID/attachments",
    "/p/$POST_ID/attachments/$ATTACHMENT_ID/delete",
    '/settings/profile',
);
for my $path (@writes) {
    my $before = _blocks();
    $test->post_ok(
        $path => $JSON => form => {
            command_id => '018f1000-0000-7000-8000-000000000401',
            csrf_token => $csrf,
            reason     => 'spam',
        }
    )->status_is( $HTTP_FORBIDDEN, "$path refuses a suspended member" );
    is( _blocks(), $before + 1, "$path records the suspended_user_block" );
}

done_testing();

sub _blocks {
    my $recorded = $telemetry->events->{suspended_user_block};

    return $recorded ? $recorded->{count} : 0;
}

sub _install_fakes ($application) {
    my $forum = GPForum::Test::ForumWebServices->new;
    my %fakes = (
        (
            map { $_ => $forum }
              qw(gp_post_reader gp_thread_detail_reader gp_report_store
              gp_community_workflow gp_attachment_workflow gp_profile_reader)
        ),
        gp_permission_gate    => GPForum::Test::AllowPermissionGate->new,
        gp_rate_limiter       => GPForum::Test::AllowLimiter->new,
        gp_security_telemetry => $telemetry,
        gp_suspension_store   => GPForum::Test::SuspendedParticipation->new,
    );
    for my $helper ( sort keys %fakes ) {
        my $fake = $fakes{$helper};
        $application->helper( $helper => sub { return $fake; } );
    }

    my $routes = $application->routes;
    $routes->get('/__test/session/:user_id')->to(
        cb => sub ($controller) {
            $controller->session( user_id => $controller->param('user_id') );
            return $controller->render( json => { ok => 1 } );
        }
    );
    $routes->get('/__test/csrf')->to(
        cb => sub ($controller) {
            return $controller->render(
                json => { csrf_token => $controller->csrf_token } );
        }
    );

    return;
}

1;
