# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Identity::Audit;
use GPForum::Service::Identity::MailToken;
use GPForum::Test::Id;
use GPForum::Test::IdentityMailer;
use GPForum::Test::Schema;
use GPForum::Worker::Handler::IdentityMail;

our $VERSION = '0.001';

const my $TOKEN    => 'reset-token-the-member-follows';
const my $TOKEN_ID => '018f1000-0000-7000-8000-000000000501';
const my $SECRET   => 'a session secret long enough for the test only';

# A password reset, an email change and an email verification are mailed
# through the outbox, and the outbox kept each link's token in clear until
# the mail went: in the table, its backups, and a dead letter's payload,
# whoever could read those could reset the member's password. The outbox
# now holds the token sealed with a key derived from the application's
# signing secrets, bound to its token id, and the worker opens it only to
# send the mail.
my $sealer = GPForum::Service::Identity::MailToken->new( secrets => [$SECRET] );
my $schema = GPForum::Test::Schema->new;
GPForum::Service::Identity::Audit->new(
    id_service => GPForum::Test::Id->new,
    mail_token => $sealer,
    schema     => $schema,
)->record_mail(
    {
        kind     => 'password_reset',
        to       => 'member@example.test',
        token    => $TOKEN,
        token_id => $TOKEN_ID,
        user_id  => 'user-1',
    }
);
my $mail = $schema->created_for('OutboxMessage')->[0]{payload}{mail};
ok( !exists $mail->{token}, 'the outbox holds no token in clear' );
unlike( join( q{ }, values %{$mail} ),
    qr/\Q$TOKEN\E/msx, 'nor anywhere in the mail it queues' );
is( $mail->{token_id}, $TOKEN_ID, 'it names the token it is about' );
ok( $mail->{sealed_token}, 'and holds it sealed' );

is( _sent( $sealer, $mail ), $TOKEN, 'the worker mails the token itself' );
is(
    _sent(
        GPForum::Service::Identity::MailToken->new(
            secrets => [ 'a newer secret', $SECRET ]
        ),
        $mail
    ),
    $TOKEN,
    'and still after the secret is rotated, while the old one is kept'
);
is(
    _sent(
        GPForum::Service::Identity::MailToken->new(
            secrets => ['another secret']
        ),
        $mail
    ),
    undef,
    'a worker without the secret mails nothing'
);
is(
    _sent(
        $sealer,
        { %{$mail}, token_id => '018f1000-0000-7000-8000-000000000502' }
    ),
    undef,
    'nor does one asked to send it for another token'
);

my $configured = GPForum::Service::Identity::MailToken->new;
is( $configured->unseal( $configured->seal( $TOKEN, $TOKEN_ID ), $TOKEN_ID ),
    $TOKEN, 'by default it seals with the configured signing secrets' );

done_testing();

# The token the worker gave the mailer for this mail, or undef.
sub _sent ( $mail_token, $mail ) {
    my $mailer = GPForum::Test::IdentityMailer->new;
    GPForum::Worker::Handler::IdentityMail->new(
        mail_token => $mail_token,
        mailer     => $mailer,
    )->handle(
        {
            event_id   => 'event-1',
            event_type => 'identity.mail.requested',
            mail       => $mail,
        }
    );
    my ($sent) = @{ $mailer->sent };

    return $sent ? $sent->{token} : undef;
}

1;
