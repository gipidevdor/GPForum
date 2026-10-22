# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use lib 'lib';
use lib 't/lib';

use Encode qw(decode);
use Email::Sender::Transport::Test;
use GPForum::Service::Identity::MailToken;
use GPForum::Service::Identity::Mailer;
use GPForum::Test::IdentityMailer;
use GPForum::Worker::Handler::IdentityMail;
use Test::More;

our $VERSION = '0.001';

# The mails that carry a link with a token -- a password reset, an email
# change, an email verification -- were English whatever the member reads,
# while the notices about the same account were in the member's language.
# The mailer sends each in the locale it is given, English without one, and
# the worker gives it the locale the mail was queued with.

my %SENT = (
    email_change => {
        en   => qr/Confirm [ ] the [ ] new [ ] email [ ] address/msx,
        it   => qr/Conferma [ ] il [ ] nuovo [ ] indirizzo [ ] email/msx,
        path => '/email/confirm/',
    },
    email_verification => {
        en   => qr/Verify [ ] this [ ] email [ ] address/msx,
        it   => qr/Verifica [ ] questo [ ] indirizzo [ ] email/msx,
        path => '/email/verify/',
    },
    password_reset => {
        en   => qr/A [ ] password [ ] reset [ ] was [ ] requested/msx,
        it   => qr/reimpostazione [ ] della [ ] password/msx,
        path => '/password/reset/',
    },
);

for my $kind ( sort keys %SENT ) {
    for my $locale ( undef, 'en', 'it' ) {
        my $transport = Email::Sender::Transport::Test->new;
        my $mailer    = GPForum::Service::Identity::Mailer->new(
            from_address    => 'noreply@forum.test',
            public_base_url => 'http://forum.test/',
            transport       => $transport,
        );
        my $method = "send_$kind";
        $mailer->$method(
            {
                locale => $locale,
                to     => 'member@example.test',
                token  => 'the-token',
            }
        );
        my ($delivery) = $transport->deliveries;
        my $email      = $delivery->{email};
        my $body       = decode( 'UTF-8',       $email->get_body );
        my $subject    = decode( 'MIME-Header', $email->get_header('Subject') );
        my $named      = $locale // 'no locale';
        my $words      = $SENT{$kind}{ $locale // 'en' };
        like( $body, $words, "$kind in $named is in that language" );
        like(
            $body,
            qr{\Qhttp://forum.test$SENT{$kind}{path}the-token\E}msx,
            "$kind in $named carries its link"
        );
        ok( length $subject, "$kind in $named has a subject" );

        if ( ( $locale // q{} ) eq 'it' ) {
            unlike(
                $subject,
                qr/\A (?:Reset|Confirm|Verify) [ ]/msx,
                "$kind in Italian has an Italian subject"
            );
        }
    }
}

# The worker hands the mailer the locale the outbox payload carries.
my $mail_token = GPForum::Service::Identity::MailToken->new(
    secrets => ['identity mail language secret'] );
my $handler = GPForum::Worker::Handler::IdentityMail->new(
    mail_token => $mail_token,
    mailer     => GPForum::Test::IdentityMailer->new,
);
$handler->handle(
    {
        event_id   => 'event-1',
        event_type => 'identity.mail.requested',
        mail       => {
            kind         => 'password_reset',
            locale       => 'it',
            sealed_token => $mail_token->seal( 'the-token', 'token-1' ),
            to           => 'member@example.test',
            token_id     => 'token-1',
        },
    }
);
is( $handler->mailer->sent->[0]{locale},
    'it', 'the worker sends the mail in the locale it was queued with' );

done_testing();

1;
