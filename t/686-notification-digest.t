# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use Email::Sender::Transport::Test;
use MIME::QuotedPrint qw(decode_qp);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::ScheduledJobs;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Identity::Mailer;
use GPForum::Service::Notification::DigestMessage;
use GPForum::Service::Notification::DigestQueue;
use GPForum::Service::Notification::PreferenceStore;
use GPForum::Service::Notification::Renderer;
use GPForum::Service::Notification::UnsubscribeToken;
use GPForum::Service::Operations::ScheduledJobs;
use GPForum::Test::DigestResolver;
use GPForum::Test::JobsSummary;
use GPForum::Test::NotificationPreferenceCalls;
use GPForum::Worker::Handler::NotificationDigest;

our $VERSION = '0.001';

const my $MEMBER     => '0190a5f2-0000-7000-8000-000000000001';
const my $OTHER      => '0190a5f2-0000-7000-8000-000000000002';
const my $THREAD     => '0190a5f2-0000-7000-8000-0000000000a1';
const my $THREAD2    => '0190a5f2-0000-7000-8000-0000000000a2';
const my $SCHEMA     => bless {}, 'GPForum::Test::NoSchema';
const my $BASE       => 'https://forum.example.test';
const my $START      => '2026-10-14T00:00:00Z';
const my $END        => '2026-10-15T00:00:00Z';
const my $TOTAL      => 7;
const my $ITEM_LIMIT => 20;
const my $TITLE_TEXT => qr{Release [ ] <b>notes</b> [ ] & [ ] plans}msx;
const my $TITLE_HTML =>
  qr{Release [ ] &lt;b&gt;notes&lt;/b&gt; [ ] &amp; [ ] plans}msx;
const my $NEWS_POSTS => qr{in [ ] News: [ ] 3 [ ] new [ ] posts}msx;
const my $THREAD_URL => qr{\Q$BASE\E/t/\Q$THREAD\E}msx;
const my $BOUNDARY   => qr{gpforum-digest-[[:xdigit:]]+}msx;

# ADR 0078: the daily and weekly email digest, without a database -- its
# words and markup, the scheduled job that queues it, the worker that mails
# it, and its unsubscribe scope.

my @ITEMS = (
    {
        thread_id      => $THREAD,
        title          => 'Release <b>notes</b> & plans',
        category_title => 'News',
        new_posts      => 3,
    },
    {
        thread_id      => $THREAD2,
        title          => 'Welcome',
        category_title => 'General',
        new_posts      => 1,
    },
);
my $renderer = GPForum::Service::Notification::Renderer->new;

subtest 'the message says the digest in both languages' => sub {
    my $composer =
      GPForum::Service::Notification::DigestMessage->new(
        i18n => $renderer->i18n );
    my $english = $composer->compose(
        {
            locale          => 'en',
            frequency       => 'daily',
            items           => [ @ITEMS, { thread_id => 'not-a-uuid' } ],
            thread_total    => 5,
            base_url        => "$BASE/",
            unsubscribe_url => "$BASE/unsubscribe/token",
        }
    );
    is( $english->{subject}, 'Your daily GPForum digest', 'the subject' );
    like(
        $english->{text},
        qr/Posts [ ] from [ ] yesterday/msx,
        'the text names the period'
    );
    like(
        $english->{text},
        qr{^- [ ] $TITLE_TEXT [ ] $NEWS_POSTS \n [ ]{2} $THREAD_URL $}msx,
        'each thread with its category, its new posts and its link'
    );
    like(
        $english->{text},
        qr/Welcome [ ] in [ ] General: [ ] 1 [ ] new [ ] post$/msx,
        'one post said in the singular'
    );
    unlike( $english->{text}, qr/not-a-uuid/msx,
        'a thread whose id is no uuid is left out' );
    like(
        $english->{text},
        qr/And [ ] 3 [ ] more [ ] discussions [ ] with [ ] new [ ] posts/msx,
        'the threads beyond those named are counted'
    );
    like(
        $english->{text},
        qr{Stop [ ] the [ ] digest: [ ] \Q$BASE\E/unsubscribe/token}msx,
        'the footer names the unsubscribe link'
    );
    like( $english->{html}, qr{<html [ ] lang="en">}msx, 'the HTML part' );
    like(
        $english->{html},
        qr{<a [ ] href="\Q$BASE\E/t/\Q$THREAD\E"[^>]*>$TITLE_HTML</a>}msx,
        'escapes every title'
    );
    unlike( $english->{html}, qr/<b>notes/msx, 'and lets no markup through' );
    like(
        $english->{html},
        qr{href="\Q$BASE\E/settings"}msx,
        'and links the settings page'
    );

    my $italian = $composer->compose(
        {
            locale          => 'it',
            frequency       => 'weekly',
            items           => [ $ITEMS[1] ],
            thread_total    => 1,
            base_url        => $BASE,
            unsubscribe_url => "$BASE/unsubscribe/token",
        }
    );
    is(
        $italian->{subject},
        'Il tuo riepilogo settimanale di GPForum',
        'the weekly subject in Italian'
    );
    like( $italian->{text}, qr/settimana [ ] scorsa/msx, 'and its period' );
    like( $italian->{text}, qr/1 [ ] nuovo [ ] messaggio/msx,
        'and its counts' );
    unlike( $italian->{text}, qr/altr[ae]/msx,
        'with nothing more to count, no line for it' );
};

subtest 'the queue records each due member once, queued or empty' => sub {
    my $calls = GPForum::Test::NotificationPreferenceCalls->new(
        answers => {
            notification_digest_due => sub ($parameters) {
                return [] if defined $parameters->{after_user_id};
                return [
                    {
                        user_id      => $MEMBER,
                        frequency    => 'daily',
                        period_start => $START,
                        period_end   => $END,
                    },
                    {
                        user_id      => $OTHER,
                        frequency    => 'weekly',
                        period_start => '2026-10-05T00:00:00Z',
                        period_end   => '2026-10-12T00:00:00Z',
                    },
                ];
            },
            notification_digest_items => sub ($parameters) {
                return $parameters->{user_id} eq $MEMBER
                  ? [ map { +{ %{$_}, thread_total => $TOTAL } } @ITEMS ]
                  : [];
            },
            notification_digest_record => sub ($parameters) {
                return { status => $parameters->{event} ? 'queued' : 'empty' };
            },
            notification_digest_purge => { deleted => 4 },
        }
    );
    my $queue = GPForum::Service::Notification::DigestQueue->new(
        functions       => $calls,
        event_recorder  => _recorder(),
        viewer_resolver => _resolver(),
    );
    is_deeply(
        $queue->run( { limit => 2 } ),
        { ok => 1, queued => 1, empty => 1, purged => 4 },
        'one queued, one empty, old records removed'
    );
    is( $calls->calls_to('notification_digest_due')->[0]{row_limit},
        2, 'bounded by the limit' );
    is_deeply(
        [
            @{ $calls->calls_to('notification_digest_due')->[1] }
              {qw(after_start after_user_id)}
        ],
        [ '2026-10-05T00:00:00Z', $OTHER ],
        'a full page reads the next one after its last key'
    );
    my ($items) = @{ $calls->calls_to('notification_digest_items') };
    is_deeply(
        [ @{$items}{qw(member global_read category_ids row_limit)} ],
        [ 1, 0, ['0190a5f2-0000-7000-8000-0000000000c1'], $ITEM_LIMIT ],
        'read as the member reads'
    );
    my ( $queued, $empty ) =
      @{ $calls->calls_to('notification_digest_record') };
    is( $queued->{thread_count}, $TOTAL, 'the total is recorded' );
    is(
        $queued->{event}{event_type},
        'notification.digest.requested',
        'with its mail event'
    );
    is_deeply(
        $queued->{event}{payload}{items}[0],
        {
            thread_id      => $THREAD,
            title          => 'Release <b>notes</b> & plans',
            category_title => 'News',
            new_posts      => 3,
        },
        'which carries the threads and no address'
    );
    is(
        $queued->{event}{idempotency_key},
        "notification.digest:$MEMBER:daily:$START",
        'keyed by member, frequency and period'
    );
    ok( !defined $empty->{event} && $empty->{thread_count} == 0,
        'an empty period is recorded without one' );

    my $failing = GPForum::Test::NotificationPreferenceCalls->new(
        answers => {
            %{ $calls->answers },
            notification_digest_items => sub ($parameters) {
                die "database gone\n" if $parameters->{user_id} eq $OTHER;
                return [];
            },
        }
    );
    my $summary = GPForum::Service::Notification::DigestQueue->new(
        functions       => $failing,
        event_recorder  => _recorder(),
        viewer_resolver => _resolver(),
    )->run( {} );
    is( $summary->{ok}, 0, 'a member that fails fails the run' );
    is_deeply( $summary->{errors}, ["$OTHER: database gone"],
        'and is named, the others queued' );
    is( $summary->{empty}, 1, 'the other member was still recorded' );

    is_deeply(
        GPForum::Service::Notification::DigestQueue->new( functions => undef )
          ->run( {} ),
        { ok => 1, queued => 0, skipped => 'unavailable' },
        'nothing is queued without the function layer'
    );
};

subtest 'the scheduled-jobs runner and its command name the job' => sub {
    ok(
        (
            grep { $_ eq 'notification_digests' }
              @{ GPForum::Service::Operations::ScheduledJobs->job_names }
        ),
        'notification_digests is a job'
    );
    my $jobs = GPForum::Service::Operations::ScheduledJobs->new;
    is_deeply(
        $jobs->run_job( 'notification_digests', {} ),
        { ok => 1, queued => 0, skipped => 'unavailable' },
        'skipped without a database'
    );

    my $summary = GPForum::Test::JobsSummary->new(
        summary => {
            ok                   => 1,
            notification_digests =>
              { ok => 1, queued => 3, empty => 2, purged => 0 },
        }
    );
    my $output = q{};
    open my $handle, '>', \$output or croak 'capture';
    my $command = GPForum::Command::ScheduledJobs->new(
        human  => 1,
        output => $handle,
        jobs   => $summary,
    );
    is( $command->run( '--once', '--job', 'notification_digests' ),
        0, 'the command runs it' );
    close $handle or croak 'close capture';
    like(
        $output,
        qr/email [ ] digests: [ ] 3 [ ] queued/msx,
        'and says how many digests it queued'
    );
};

my $transport = Email::Sender::Transport::Test->new;
my $tokens =
  GPForum::Service::Notification::UnsubscribeToken->new(
    secrets => ['unit-secret'] );
my $plan = {
    digest        => 1,
    frequency     => 'daily',
    email_address => 'member@example.test',
    locale        => 'it',
};
my $preferences = GPForum::Test::NotificationPreferenceCalls->new(
    answers => { digest_plan => sub (@) { return $plan; } } );
my $handler = GPForum::Worker::Handler::NotificationDigest->new(
    mailer => GPForum::Service::Identity::Mailer->new(
        transport       => $transport,
        public_base_url => "$BASE/",
        from_address    => 'forum@example.test',
    ),
    preference_store => $preferences,
    renderer         => $renderer,
    tokens           => $tokens,
);
my $event = {
    event_id       => 'e1',
    event_type     => 'notification.digest.requested',
    domain_payload => {
        recipient_user_id => $MEMBER,
        frequency         => 'daily',
        thread_total      => 2,
        items             => \@ITEMS,
    },
};

subtest 'the worker mails it as text and HTML, with one-click' => sub {
    ok( $handler->supports($event), 'the handler takes the digest event' );
    ok(
        !$handler->supports( { event_type => 'notification.email.requested' } ),
        'and not a single notification'
    );
    ok( $handler->handle($event)->{delivered}, 'the digest is sent' );
    my ($sent) = $transport->deliveries;
    my $email = $sent->{email};
    is( $email->get_header('To'), 'member@example.test', 'to the member' );
    like(
        $email->get_header('Subject'),
        qr/\A =[?]UTF-8[?]/msx,
        'the subject MIME-encoded'
    );
    like(
        $email->get_header('Content-Type'),
        qr{\A multipart/alternative; [ ] boundary="$BOUNDARY" \z}msx,
        'one message with alternative parts'
    );
    my ($boundary) =
      $email->get_header('Content-Type') =~ /boundary="([^"]+)"/msx;
    my @parts = grep { /Content-Type/msx } split /--\Q$boundary\E/msx,
      $email->get_body;
    is( scalar @parts, 2, 'two parts' );
    like(
        $parts[0],
        qr{Content-Type: [ ] text/plain; [ ] charset=UTF-8}msx,
        'plain text first'
    );
    like( $parts[1], qr{Content-Type: [ ] text/html; [ ] charset=UTF-8}msx,
        'then HTML' );
    my $text = decode_qp( ( split /\r\n\r\n/msx, $parts[0], 2 )[1] );
    utf8::decode($text);
    like(
        $text,
        qr/I [ ] messaggi [ ] di [ ] ieri/msx,
        'in the member language'
    );
    my ($token) =
      $email->get_header('List-Unsubscribe') =~
      m{\A <\Q$BASE\E/unsubscribe/([^>]+)> \z}msx;
    is_deeply(
        $tokens->verify($token),
        { user_id => $MEMBER, scope => 'digest' },
        'whose List-Unsubscribe stops the digest'
    );
    is( $email->get_header('List-Unsubscribe-Post'),
        'List-Unsubscribe=One-Click', 'in one click' );

    $plan = { digest => 0, email_address => 'member@example.test' };
    ok( $handler->handle($event)->{skipped},
        'a digest switched off since it was queued is not sent' );
    ok(
        GPForum::Worker::Handler::NotificationDigest->new->handle($event)
          ->{skipped},
        'nor without a mailer'
    );
    is( scalar $transport->deliveries, 1, 'nothing more went out' );
};

subtest 'the digest unsubscribe turns the digest channel off' => sub {
    my $calls = GPForum::Test::NotificationPreferenceCalls->new(
        answers => { notification_digest_unsubscribe => { status => 'ok' } } );
    my $store = GPForum::Service::Notification::PreferenceStore->new(
        schema    => $SCHEMA,
        functions => $calls,
        recorder  => $calls,
    );
    is_deeply(
        $store->unsubscribe(
            { user_id => $MEMBER, scope => 'digest', via => 'one_click' }
        ),
        { ok => 1, status => 'ok', scope => 'digest' },
        'the digest scope'
    );
    my ($call) = @{ $calls->calls_to('notification_digest_unsubscribe') };
    is_deeply(
        [ $call->{user_id}, $call->{audit}{metadata}{scope} ],
        [ $MEMBER,          'digest' ],
        'goes to the digest function, audited'
    );
    is_deeply( $calls->calls_to('notification_unsubscribe'),
        [], 'not to the email one' );
    is_deeply(
        $tokens->verify( $tokens->issue( $MEMBER, 'digest' ) ),
        { user_id => $MEMBER, scope => 'digest' },
        'a token may name the digest'
    );
    is_deeply(
        GPForum::Service::Notification::PreferenceStore->new(
            schema    => $SCHEMA,
            functions => undef
        )->digest_plan($MEMBER),
        { digest => 0 },
        'no digest without the function layer'
    );
};

done_testing;

sub _recorder {
    return GPForum::Infrastructure::EventRecorder->new( schema => $SCHEMA );
}

sub _resolver {
    return GPForum::Test::DigestResolver->new;
}

1;
