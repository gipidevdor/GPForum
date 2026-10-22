# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Email::Sender::Transport::Failable;
use Email::Sender::Transport::Test;
use Test::Exception;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Identity::Mailer;
use GPForum::Service::Notification::Renderer;
use GPForum::Service::Notification::UnsubscribeToken;
use GPForum::Test::NotificationPreferenceCalls;
use GPForum::Worker::Handler::NotificationDigest;

our $VERSION = '0.001';

const my $MEMBER   => '0190a5f2-0000-7000-8000-000000000001';
const my $THREAD   => '0190a5f2-0000-7000-8000-0000000000a1';
const my $EVENT_ID => '0190a5f2-0000-7000-8000-0000000000e1';
const my $START    => '2026-10-14T00:00:00Z';

# ADR 0078, amendment of 2026-10-17: a digest is mailed at most once. The
# worker claims its record before the transport takes the mail, so the
# outbox delivering the event again -- the mail sent, the job not marked
# done -- sends nothing; a transport that refuses the mail gives the claim
# back for the retry. Its Message-ID is named by the event, the same each
# time.
my %claimed;
my $store = GPForum::Test::NotificationPreferenceCalls->new(
    answers => {
        digest_plan => sub (@) {
            return {
                digest        => 1,
                email_address => 'member@example.test',
                locale        => 'en',
            };
        },
        claim_digest_send => sub ($digest) {
            my $key = join q{:}, @{$digest}{qw(user_id frequency period_start)};
            return { status => $claimed{$key}++ ? 'sent' : 'claimed' };
        },
        release_digest_send => sub ($digest) {
            delete $claimed{ join q{:},
                @{$digest}{qw(user_id frequency period_start)} };
            return { status => 'released' };
        },
    }
);
my $refuse    = 1;
my $transport = Email::Sender::Transport::Test->new;
my $handler   = GPForum::Worker::Handler::NotificationDigest->new(
    mailer => GPForum::Service::Identity::Mailer->new(
        transport => Email::Sender::Transport::Failable->new(
            transport          => $transport,
            failure_conditions => [ sub (@) { return $refuse; } ],
        ),
        public_base_url => 'https://forum.example.test/',
        from_address    => 'GPForum <forum@example.test>',
    ),
    preference_store => $store,
    renderer         => GPForum::Service::Notification::Renderer->new,
    tokens           => GPForum::Service::Notification::UnsubscribeToken->new(
        secrets => ['unit-secret']
    ),
);
my $event = {
    event_id       => $EVENT_ID,
    event_type     => 'notification.digest.requested',
    domain_payload => {
        recipient_user_id => $MEMBER,
        frequency         => 'daily',
        period_start      => $START,
        thread_total      => 1,
        items             => [
            {
                thread_id      => $THREAD,
                title          => 'News',
                category_title => 'General',
                new_posts      => 1,
            }
        ],
    },
};

dies_ok { $handler->handle($event) } 'a refused mail fails the run';
is_deeply(
    $store->calls_to('release_digest_send'),
    [
        {
            user_id      => $MEMBER,
            frequency    => 'daily',
            period_start => $START,
            event_id     => $EVENT_ID,
        }
    ],
    'and gives its claim back'
);

$refuse = 0;
ok( $handler->handle($event)->{delivered}, 'the retry sends it' );
my $again = $handler->handle($event);
is_deeply(
    [ @{$again}{qw(skipped reason)} ],
    [ 1, 'sent' ],
    'a second delivery of the event sends nothing'
);
my @sent = $transport->deliveries;
is( scalar @sent, 1, 'one mail in all' );
is(
    $sent[0]{email}->get_header('Message-ID'),
    "<gpforum-digest.$EVENT_ID\@example.test>",
    'its Message-ID named by the event'
);

done_testing;

1;
