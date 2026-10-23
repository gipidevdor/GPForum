# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use utf8;
use lib 'lib';
use lib 't/lib';
use GPForum::Test::ProtocolFixture;
use Test::More;
use Test::Mojo;
use Mojolicious;
use Crypt::PK::Ed25519;
use GPForum::Worker::Handler::WebSub;
use Test::Fatal qw(exception);
use File::Temp  qw(tempdir);
use Mojo::File  qw(path);
use Email::MIME;
use MIME::Base64 qw(encode_base64url);
use GPForum::Infrastructure::ResultRow;
use GPForum::Service::Discovery::Mbox;
use GPForum::Service::Discovery::Gemini;
use GPForum::Service::Discovery::WebSub;
use GPForum::Service::Forum::PostSigner;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Identity::MailReplyToken;
use GPForum::Service::Identity::MailIn;
use GPForum::Web::ForumAccess;
use GPForum::Command::Support::Manual;
use GPForum::CLI::FrontDoor::Launcher;
use GPForum::Service::Discovery::FeedBuilder;
use GPForum::Service::Discovery::CanonicalUrl;

our $VERSION = '0.001';
const my $HTTP_ACCEPTED    => 202;
const my $HTTP_UNAVAILABLE => 503;

const my $KEY_SECRET_LENGTH => 32;
const my $LONG_URL          => 1024;
const my $MAX_TRUST         => 4;
const my $OVERSIZED_MAIL    => 1_048_577;
const my $READ_LIMIT        => 60;
const my $REPORT_LIMIT      => 5;
const my $SECRET_MAX_LENGTH => 200;
const my $WRITE_LIMIT       => 20;
my $scratch = tempdir( CLEANUP => 1 );
my $thread  = '018f1004-0000-7000-8000-000000000001';
my $user    = '018f1001-0000-7000-8000-000000000001';
my $post    = '018f1005-0000-7000-8000-000000000001';
my $signer  = GPForum::Service::Forum::PostSigner->new(
    key_file => "$scratch/keys/server.pem" );
my $body = {
    post_id     => $post,
    body_format => 'markdown',
    body_source => "Caffè\nFrom alice\n>From bob\n```\n=> /evil\n"
};
my $signature = $signer->sign($body);
ok(
    $signer->verify( $body, $signature ),
    'Ed25519 verifies exact Unicode content'
);
ok( !$signer->verify( { %{$body}, body_source => 'altered' }, $signature ),
    'content tampering fails' );
ok( !$signer->verify( { %{$body}, post_id => $thread }, $signature ),
    'signature cannot move to another post' );
my $reload = GPForum::Service::Forum::PostSigner->new(
    key_file => "$scratch/keys/server.pem" );
is_deeply( $reload->public_key, $signer->public_key,
    'key persists across instances' );
is( ( stat "$scratch/keys/server.pem" )[2] & oct '077',
    0, 'private key has no group or world access' );
my $forged = { %{$signature}, signature => encode_base64url('forged') };
ok( !$signer->verify( $body, $forged ), 'invalid signature is rejected' );
my $attacker = GPForum::Service::Forum::PostSigner->new(
    key_file => "$scratch/attacker.pem" );
ok(
    !$signer->verify( $body, $attacker->sign($body) ),
    'a database attacker cannot substitute their own signing key'
);

my $crlf_body = $body->{body_source} =~ s/\n/\r\n/grmsx;
ok(
    $signer->verify( { %{$body}, body_source => $crlf_body }, $signature ),
    'signature canonicalization survives MIME newline conversion'
);
path("$scratch/keys/server.pem")
  ->spew( Crypt::PK::Ed25519->new->generate_key->export_key_pem('private') );
my $rotated_signer = GPForum::Service::Forum::PostSigner->new(
    key_file => "$scratch/keys/server.pem" );
isnt(
    $rotated_signer->public_key->{kid},
    $signer->public_key->{kid},
    'rotated server key has a distinct identity'
);
ok( $rotated_signer->verify( $body, $signature ),
    'archived public key verifies revisions after private key rotation' );

my $mbox =
  GPForum::Service::Discovery::Mbox->new( base_url => 'https://forum.example' );
my $mbox_record = $mbox->message(
    {
        thread_id   => $thread,
        category_id => $thread,
        title       => "Hello\nBcc: injected"
    },
    {
        %{$body},
        author_user_id      => $user,
        author_display_name => 'Gianni',
        created_at          => '2026-10-23 14:00:00+02'
    },
    $signature
);
like( $mbox_record, qr/^From[ ]gpforum/msx, 'mbox has an envelope separator' );
like( $mbox_record, qr/^>From[ ]alice$/msx, 'mboxrd quotes From' );
like(
    $mbox_record,
    qr/^>>From[ ]bob$/msx,
    'mboxrd quotes previously escaped From'
);
unlike( $mbox_record, qr/^Bcc:/msx, 'untrusted title cannot inject headers' );
$mbox_record =~ s/\A[^\n]*\n//msx;
my $mail = Email::MIME->new($mbox_record);
is(
    $mail->header_raw('Date'),
    'Fri, 23 Oct 2026 12:00:00 +0000',
    'creation timestamp is converted to UTC'
);
my $decoded = $mail->body_str;
$decoded =~ s/\r\n/\n/gmsx;
$decoded =~ s/^>(>*From[ ])/$1/gmsx;
$decoded =~ s/\n\z//msx;
is( $decoded, $body->{body_source},
    'mail reader recovers the exact UTF-8 post including mbox escaping' );
is(
    $mail->header_raw('Message-ID'),
    $mbox->message_id($post),
    'stable message id'
);
like( $mail->header_raw('X-GPForum-Signature'),
    qr/\A[[:word:]-]+\z/msx, 'portable detached signature header' );
my $reply = Email::MIME->new(
    (
        $mbox->message(
            { thread_id => $thread, category_id => $thread, title => 'Hello' },
            {
                %{$body},
                author_user_id => $user,
                created_at     => '2026-10-23T12:00:00Z'
            },
            undef, $post
        )
    ) =~ s/\A[^\n]*\n//rmsx
);
is(
    $reply->header_raw('In-Reply-To'),
    $mbox->message_id($post),
    'reply stays in the mailbox thread'
);

my $tokens = GPForum::Service::Identity::MailReplyToken->new(
    secrets => [ 'a' x $KEY_SECRET_LENGTH ],
    domain  => 'forum.example'
);
my $token = $tokens->issue( $thread, $user, $post );
is_deeply(
    $tokens->verify($token),
    { thread_id => $thread, user_id => $user },
    'reply capability binds thread and recipient'
);
is( $tokens->issue( $thread, $user, $post ),
    $token, 'retries use a stable notification message id' );
isnt( $tokens->issue( $thread, $user, $thread ),
    $token, 'different posts do not collapse into one email' );
ok(
    !$tokens->verify( $mbox->message_id($post) ),
    'public archive id is not posting authority'
);
ok( !$tokens->verify( $token =~ s/000000000001/000000000002/rmsx ),
    'altered capability fails' );
my $rotated = GPForum::Service::Identity::MailReplyToken->new(
    secrets => [ 'b' x $KEY_SECRET_LENGTH, 'a' x $KEY_SECRET_LENGTH ],
    domain  => 'forum.example'
);
ok( $rotated->verify($token), 'configured previous secret supports rotation' );
my $fixture = GPForum::Test::ProtocolFixture->new(
    user   => $user,
    thread => $thread,
    post   => $post,
    body   => $body->{body_source}
);
my $inbound = GPForum::Service::Identity::MailIn->new(
    tokens           => $tokens,
    schema           => $fixture,
    functions        => $fixture,
    viewer_resolver  => $fixture,
    suspension_store => $fixture,
    rate_limiter     => $fixture,
    reputation_rate  => $fixture,
    workflow         => $fixture
);

sub inbound_mail ( $from, $parent, $text, @extra ) {
    return Email::MIME->create(
        header_str => [
            From          => $from,
            To            => 'reply@forum.example',
            Subject       => 'Re: topic',
            'In-Reply-To' => $parent,
            'Message-ID'  => '<incoming@example.net>',
            @extra
        ],
        attributes => {
            content_type => 'text/plain',
            charset      => 'UTF-8',
            encoding     => 'quoted-printable'
        },
        body_str => $text
    )->as_string;
}
my $raw = inbound_mail( 'alice@example.net', $token,
    "Caffè\n\n> old text\n\n-- \nSignature" );
ok( $inbound->receive($raw)->{ok},
    'authenticated MIME reply reaches posting workflow' );
is( $fixture->{command}{body_source},
    'Caffè', 'charset, quotes and signature are handled' );
my $command_id = $fixture->{command}{command_id};
$inbound->receive($raw);
is( $fixture->{command}{command_id},
    $command_id, 'redelivery has same durable idempotency key' );
like(
    exception {
        $inbound->receive(
            inbound_mail( 'attacker@example.net', $token, 'attack' ) )
    },
    qr/verified/msx,
    'spoofed From does not match capability owner'
);
like(
    exception {
        $inbound->receive(
            inbound_mail(
                'alice@example.net', $mbox->message_id($post), 'attack'
            )
        )
    },
    qr/capability/msx,
    'public id is rejected before posting'
);
like(
    exception {
        $inbound->receive(
            inbound_mail(
                'alice@example.net', $token,
                'automatic',         'Auto-Submitted' => 'auto-replied'
            )
        )
    },
    qr/automatic/msx,
    'auto replies cannot loop'
);
like( exception { $inbound->receive( 'x' x $OVERSIZED_MAIL ) },
    qr/exceeds/msx, 'oversized mail is refused' );
$fixture->{suspended} = 1;
like( exception { $inbound->receive($raw) },
    qr/participate/msx, 'suspended recipient cannot post' );
$fixture->{suspended} = 0;

my $gemini = GPForum::Service::Discovery::Gemini->new(
    hostname             => 'forum.example',
    category_reader      => $fixture,
    thread_reader        => $fixture,
    thread_detail_reader => $fixture
);
like(
    $gemini->response("gemini://forum.example/\r\n"),
    qr/\A20[ ]text\/gemini.*=>[ ]\/c\//msx,
    'Gemini index renders public categories'
);
like(
    $gemini->response("gemini://forum.example/t/$thread\r\n"),
    qr/\A20[ ]text\/gemini/msx,
    'Gemini thread renders'
);
like(
    $gemini->response("gemini://forum.example/t/$thread\r\n"),
    qr/\n[ ]```\n=>[ ]\/evil/msx,
    'user fences remain inside preformatted text'
);
like( $gemini->response("gemini://elsewhere.example/\r\n"),
    qr/\A53/msx, 'Gemini does not proxy other hosts' );
like( $gemini->response("gemini://alice\@forum.example/\r\n"),
    qr/\A59/msx, 'Gemini rejects userinfo' );
like( $gemini->response("gemini://forum.example/#fragment\r\n"),
    qr/\A59/msx, 'Gemini rejects fragments' );
like(
    $gemini->response(
        'gemini://forum.example/' . ( 'a' x $LONG_URL ) . "\r\n"
    ),
    qr/\A59/msx,
    'Gemini enforces 1024 byte URL limit'
);
like( $gemini->response("gemini://forum.example/\n"),
    qr/\A59/msx, 'Gemini requires CRLF' );

my $hub = GPForum::Service::Discovery::WebSub->new(
    hub_url => 'https://hub.example/',
    topic   => 'https://forum.example/feed.atom'
);
my $subscription = {
    'hub.mode'     => 'subscribe',
    'hub.topic'    => $hub->topic,
    'hub.callback' => 'https://reader.example/callback',
    'hub.secret'   => 'secret'
};
is_deeply( $hub->subscription($subscription),
    $subscription,
    'WebSub preserves subscription and secret for upstream verification' );
like(
    exception {
        $hub->subscription(
            {
                %{$subscription},
                'hub.topic' => 'https://forum.example/private'
            }
        )
    },
    qr/topic/msx,
    'private topics cannot be subscribed'
);
like(
    exception {
        $hub->subscription(
            { %{$subscription}, 'hub.secret' => 'x' x $SECRET_MAX_LENGTH } )
    },
    qr/secret/msx,
    'WebSub secret length follows the standard'
);
my $feed = GPForum::Service::Discovery::FeedBuilder->new(
    canonical_url => GPForum::Service::Discovery::CanonicalUrl->new,
    hub_url       => 'https://hub.example/?a=1&b=2'
)->render_atom(
    {
        id      => $hub->topic,
        url     => $hub->topic,
        title   => 'Forum',
        updated => '2026-10-23T12:00:00Z'
    }
);
like(
    $feed,
    qr{href="https://hub.example/[?]a=1&amp;b=2"[ ]rel="hub"}msx,
    'Atom advertises an escaped WebSub hub'
);
$hub->ua($fixture);
ok( $hub->publish->{published},
    'public feed publication is acknowledged by the hub' );
is( $fixture->{posted_url},
    $hub->hub_url, 'publisher only contacts the trusted hub' );
is_deeply(
    $fixture->{posted_arguments},
    [ form => { 'hub.mode' => 'publish', 'hub.url' => $hub->topic } ],
    'outbox publication carries the fixed public topic'
);
my $handler = GPForum::Worker::Handler::WebSub->new( publisher => $hub );
ok( $handler->supports( { event_type => 'post.created' } ),
    'outbox handler accepts post events' );
ok( !$handler->supports( { event_type => 'post.created.unexpected' } ),
    'outbox handler rejects noncanonical event types' );
$fixture->{hub_status} = $HTTP_UNAVAILABLE;
like(
    exception { $handler->handle( { event_type => 'post.created' } ) },
    qr/rejected/msx,
    'failed hub delivery propagates so the durable outbox retries'
);
$fixture->{hub_status} = $HTTP_ACCEPTED;
my $gateway = Mojolicious->new;
$gateway->routes->namespaces( ['GPForum::Controller'] );
$gateway->routes->post('/websub')->to('Discovery#subscribe');
$gateway->helper( gp_websub       => sub { return $hub; } );
$gateway->helper( gp_rate_limiter => sub { return $fixture; } );
my $http = Test::Mojo->new($gateway);
$http->post_ok( '/websub' => form => $subscription )->status_is($HTTP_ACCEPTED);
is_deeply(
    $fixture->{posted_arguments},
    [ form => $subscription ],
'subscription gateway preserves callback and secret for verification by the hub'
);
my $access = GPForum::Web::ForumAccess->new;

for my $level ( 0 .. $MAX_TRUST ) {
    is(
        $access->read_rate_input(
            { actor_id => $user, action => 'read', trust_level => $level }
        )->{limit},
        $READ_LIMIT * $MAX_TRUST**$level,
        "read budget follows trust $level"
    );
    is(
        $access->write_rate_input(
            {
                actor_id    => $user,
                action      => 'reply.create',
                trust_level => $level
            }
        )->{limit},
        $WRITE_LIMIT * 2**$level,
        "write budget follows trust $level"
    );
}
is(
    $access->write_rate_input(
        {
            actor_id    => $user,
            action      => 'report.create',
            trust_level => $MAX_TRUST
        }
    )->{limit},
    $REPORT_LIMIT,
    'reports retain abuse bound'
);
my $resolved = GPForum::CLI::FrontDoor::Launcher->new->resolve('backup');
my $manual   = GPForum::Command::Support::Manual->new;
like( $manual->text( 'backup', $resolved->{class} ),
    qr/--verify/msx, 'POD help includes executable options' );
$manual->man( 'backup', $resolved->{class}, "$scratch/gpforum-backup.1" );
like( path("$scratch/gpforum-backup.1")->slurp,
    qr/\\-\\-verify/msx, 'man page includes same executable option' );
done_testing();

1;
