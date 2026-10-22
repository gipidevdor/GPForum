# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Identity::Audit;
use GPForum::Service::Identity::MailToken;
use GPForum::Infrastructure::OutboxMessageBuilder;
use GPForum::Test::Id;
use GPForum::Test::IdentityMailer;
use GPForum::Test::Schema;
use GPForum::Worker::Handler::IdentityMail;
use Test::More;

our $VERSION = '0.001';

my $events_id  = GPForum::Test::Id->new;
my $schema     = GPForum::Test::Schema->new;
my $mail_token = GPForum::Service::Identity::MailToken->new(
    secrets => ['identity mail test secret'] );
my $audit = GPForum::Service::Identity::Audit->new(
    id_service => $events_id,
    mail_token => $mail_token,
    schema     => $schema,
);
$audit->record_mail(
    {
        kind     => 'password_reset',
        to       => 'member@example.test',
        token    => 'secret-reset',
        token_id => 'tok-1',
        user_id  => 'user-1',
    }
);

my $event = $schema->created_for('EventLog')->[0];
is( $event->{event_type},
    'identity.mail.requested', 'record_mail writes the mail event' );
is_deeply(
    $event->{payload},
    { kind => 'password_reset', token_id => 'tok-1' },
    'EventLog payload omits the raw token'
);

my $outbox = $schema->created_for('OutboxMessage')->[0];
ok(
    !exists $outbox->{payload}{mail}{token},
    'outbox payload holds no raw token'
);
is(
    $mail_token->unseal(
        $outbox->{payload}{mail}{sealed_token},
        $outbox->{payload}{mail}{token_id}
    ),
    'secret-reset',
    'it keeps the token sealed to its id until delivery'
);
is( $outbox->{payload}{mail}{to},
    'member@example.test', 'outbox payload keeps the recipient' );
is( $outbox->{payload}{event_type},
    'identity.mail.requested', 'outbox payload keeps the mail event type' );

my $builder = GPForum::Infrastructure::OutboxMessageBuilder->new(
    id_service => GPForum::Test::Id->new, );
my $merged = $builder->for_event(
    {
        actor_id          => 'user-1',
        aggregate_id      => 'user-1',
        aggregate_type    => 'user',
        aggregate_version => 1,
        correlation_id    => 'corr-1',
        event_id          => 'event-1',
        event_type        => 'identity.mail.requested',
        idempotency_key   => 'identity.mail.requested:tok-1',
        metadata          => {},
        payload           => { kind => 'password_reset', token_id => 'tok-1' },
        schema_version    => 1,
    },
    {
        mail => {
            kind  => 'password_reset',
            to    => 'member@example.test',
            token => 'builder-token',
        },
    }
);
is( $merged->{payload}{mail}{token},
    'builder-token', 'message builder merges outbox-only mail extras' );
is( $merged->{payload}{payload}{token_id},
    'tok-1', 'message builder keeps the EventLog payload beside mail extras' );

my $mailer  = GPForum::Test::IdentityMailer->new;
my $handler = GPForum::Worker::Handler::IdentityMail->new(
    mail_token => $mail_token,
    mailer     => $mailer,
);
ok( $handler->supports( { event_type => 'identity.mail.requested' } ),
    'handler supports identity mail events' );
ok( !$handler->supports( { event_type => 'post.created' } ),
    'handler ignores forum events' );

my $delivered = $handler->handle(
    {
        event_id   => 'event-mail-1',
        event_type => 'identity.mail.requested',
        mail       => {
            kind         => 'email_verification',
            sealed_token => $mail_token->seal( 'verify-secret', 'tok-2' ),
            to           => 'member@example.test',
            token_id     => 'tok-2',
        },
    }
);
ok( $delivered->{delivered}{ok}, 'handler delivers a complete mail payload' );
is( $mailer->sent->[0]{kind},
    'email_verification', 'handler sends verification mail' );
is( $mailer->sent->[0]{token},
    'verify-secret', 'handler gives the mailer the raw token' );

my $skipped = $handler->handle(
    {
        event_id   => 'event-mail-2',
        event_type => 'identity.mail.requested',
    }
);
ok( $skipped->{skipped}, 'handler skips a mail event without a payload' );

my $from_eventlog = $handler->handle(
    {
        event_id   => 'event-mail-3',
        event_type => 'identity.mail.requested',
        payload    => {
            kind     => 'password_reset',
            token_id => 'tok-1',
        },
    }
);
ok( $from_eventlog->{skipped},
    'handler skips an EventLog payload without mail extras' );
is( scalar @{ $mailer->sent },
    1, 'EventLog-only retry does not invent a raw token' );

done_testing();

1;
