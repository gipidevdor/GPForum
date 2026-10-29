# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Email::Sender::Transport::Test;
use Encode qw(decode);
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Identity::Event;
use GPForum::Service::Identity::Mailer;
use GPForum::Test::AllowLimiter;
use GPForum::Test::CommandIdempotency;
use GPForum::Test::IdentitySecurityAudit;
use GPForum::Test::IdentityStore;
use GPForum::Worker::Handler::IdentityMail;

our $VERSION = '0.001';

const my $HTTP_FOUND => 302;
const my $PASSWORD   => 'correct horse battery staple';

# Whoever held a member's session could move the account to an address of
# their own: the change asked for no password, and the address it left was
# told nothing, so the member learnt of it when they could no longer reset
# their password. The change now asks for the current password, and the
# address it leaves is told, with the way to stop it.

subtest 'the change asks for the current password' => sub {
    my $store = GPForum::Test::IdentityStore->new;
    my $test  = _client($store);
    $test->get_ok('/__test/fixate-session');

    $test->post_ok(
        '/settings/email' => form => {
            command_id => 'email-change-1',
            csrf_token => _csrf_token($test),
            email      => 'new@example.test',
        }
      )
      ->status_is( $HTTP_FOUND,
        'without it the change is refused, back to the settings page' );
    $test->header_like( Location => qr{/settings\z}msx );
    is( scalar @{ $store->lifecycle_calls }, 0, 'before the store is asked' );

    $test->post_ok(
        '/settings/email' => form => {
            command_id       => 'email-change-2',
            csrf_token       => _csrf_token($test),
            current_password => $PASSWORD,
            email            => 'new@example.test',
        }
    )->status_is($HTTP_FOUND);
    my ($call) = @{ $store->lifecycle_calls };
    is( $call->{method}, 'request_email_change', 'with it the store is asked' );
    is( $call->{input}{current_password},
        $PASSWORD, 'and given the password to check' );
};

subtest 'the address it leaves is told, in the member language' => sub {
    my $transport = Email::Sender::Transport::Test->new;
    my $handler   = GPForum::Worker::Handler::IdentityMail->new(
        mailer => GPForum::Service::Identity::Mailer->new(
            from_address    => 'noreply@forum.test',
            public_base_url => 'http://forum.test/',
            transport       => $transport,
        ),
    );
    my @tasks = map {
        $handler->handle(
            {
                event_id   => "event-notice-$_",
                event_type => 'identity.mail.requested',
                mail       => {
                    kind   => 'email_change_notice',
                    locale => $_,
                    to     => 'old@example.test',
                },
            }
        )
    } qw(en it);
    ok( $tasks[0]{delivered}{ok}, 'sent without a token of its own' );

    my ( $english, $italian ) = map { $_->{email} } $transport->deliveries;
    is( $english->get_header('To'), 'old@example.test', 'to the old address' );
    like(
        decode( 'MIME-Header', $english->get_header('Subject') ),
        qr/email \s address/imsx,
        'an English subject for an English member'
    );
    my $body = decode( 'UTF-8', $english->get_body );
    like(
        $body,
        qr{http://forum[.]test/password/reset\b}msx,
        'the way to stop it: a password reset'
    );
    unlike( $body, qr{/email/confirm/}msx, 'and no way to confirm it' );
    like( decode( 'MIME-Header', $italian->get_header('Subject') ),
        qr/indirizzo/msx, 'Italian for an Italian member' );
    like( decode( 'UTF-8', $italian->get_body ),
        qr/Reimpostala/msx, 'all of it' );

    my $events   = GPForum::Service::Identity::Event->new;
    my %about    = ( token_id => 'tok-1', user_id => 'user-1' );
    my %envelope = map {
        $_ =>
          $events->mail_envelope( { %about, kind => $_ } )->{idempotency_key}
    } qw(email_change email_change_notice);
    isnt( $envelope{email_change_notice},
        $envelope{email_change},
        'a message of its own beside the confirmation about the same token' );
};

done_testing();

sub _client ($store) {
    my $test = Test::Mojo->new('GPForum');
    $test->app->helper( gp_identity_store => sub { return $store; } );
    $test->app->helper(
        gp_rate_limiter => sub { return GPForum::Test::AllowLimiter->new; } );
    $test->app->helper(
        gp_command_idempotency => sub {
            return GPForum::Test::CommandIdempotency->new;
        }
    );
    $test->app->helper(
        gp_identity_security_audit => sub {
            return GPForum::Test::IdentitySecurityAudit->new;
        }
    );
    my $routes = $test->app->routes;
    $routes->get('/__test/fixate-session')->to(
        cb => sub ($controller) {
            $controller->session(
                session_id    => 'session-1',
                session_token => 'session-token-1',
                user_id       => 'user-1',
            );
            return $controller->render( text => 'ok' );
        }
    );

    return $test;
}

sub _csrf_token ($test) {
    $test->get_ok('/login');
    my ($token) =
      $test->tx->res->body =~ /name="csrf_token" [^>]+ value="([^"]+)"/msx;

    return $token // q{};
}

1;
