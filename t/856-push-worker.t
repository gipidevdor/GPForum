# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use Carp qw(croak);
use Test::More;
use Test::Exception;
use File::Temp qw(tempdir);
use Crypt::PK::ECC;
use MIME::Base64 qw(encode_base64url);
use Mojo::IOLoop;
use Mojo::JSON qw(encode_json);
use Mojo::Message::Response;
use Mojo::Promise;
use lib 'lib';
use lib 't/lib';
use GPForum::Test::PushCalls;
use GPForum::Test::PushTransport;
use GPForum::Test::PushResolver;
use GPForum::Test::PushUserAgent;
use GPForum::Service::Notification::Push::Transport;
use Scalar::Util qw(refaddr);
use GPForum::Config;
use GPForum::Infrastructure::Id;
use GPForum::Service::Notification::Push::Keyring;
use GPForum::Service::Notification::Push::Store;
use GPForum::Service::Notification::Push::Worker;

const my $HTTPS_PORT          => 443;
const my $SAFE_PRIVATE_MODE   => oct '0600';
const my $UNSAFE_PRIVATE_MODE => oct '0644';
our $VERSION = '0.001';
const my $REVOKED_JOB      => 3;
const my $INVALID_JOB      => 4;
const my $NETWORK_JOB      => 5;
const my $CONCURRENCY      => 8;
const my $AUTH_BYTES       => 16;
const my $KEY_BYTES        => 32;
const my $HASH_LENGTH      => 64;
const my $TTL_SECONDS      => 120;
const my $RETRY_SECONDS    => 180;
const my $HTTP_CREATED     => 201;
const my $COOLDOWN_ENTRIES => 128;

const my @HTTP_CASES => (
    [ $HTTP_CREATED, 'accepted' ],
    [ 202,           'accepted' ],
    [ 410,           'expired' ],
    [ 404,           'expired' ],
    [ 401,           'failed' ],
    [ 403,           'failed' ],
    [ 413,           'failed' ],
    [ 302,           'failed' ],
    [ 429,           'retry' ],
    [ 503,           'retry' ],
);

my $directory = tempdir( CLEANUP => 1 );
GPForum::Service::Notification::Push::Keyring->new( directory => $directory )
  ->generate;
my $config = GPForum::Config->from_environment(
    {
        GPFORUM_PUSH_ENABLED       => 1,
        GPFORUM_PUSH_KEY_DIRECTORY => $directory,
        GPFORUM_PUSH_CONTACT       => 'mailto:ops@example.com'
    }
);
my $calls = GPForum::Test::PushCalls->new;
my $store = GPForum::Service::Notification::Push::Store->new(
    schema    => bless( {}, 'GPForum::Test::NoSchema' ),
    config    => $config,
    functions => $calls
);
my $crypto   = $store->crypto;
my $user     = GPForum::Infrastructure::Id->new->uuid;
my $public   = $store->public_config;
my $receiver = Crypt::PK::ECC->new->generate_key('prime256v1');
my $keys     = {
    p256dh => encode_base64url( $receiver->export_key_raw('public') ),
    auth   => encode_base64url( 'a' x $AUTH_BYTES )
};

sub _job ( $number, $type = 'activation' ) {
    my $id   = GPForum::Infrastructure::Id->new->uuid;
    my $hash = 'a' x $HASH_LENGTH;
    return {
        delivery_id     => $number,
        subscription_id => $id,
        user_id         => $user,
        endpoint_hash   => $hash,
        key_id          => $public->{key_id},
        kind            => $type,
        remaining       => $TTL_SECONDS,
        attempts        => 1,
        envelope        => $crypto->seal(
            $store->secrets->storage,
            "subscription:$user:$hash",
            {
                endpoint => "https://fcm.googleapis.com/push/$number",
                keys     => $keys
            }
        ),
        activation => $crypto->seal(
            $store->secrets->storage,
            "activation:$id",
            {
                type            => 'activation',
                subscription_id => $id,
                nonce           => encode_base64url( 'n' x $KEY_BYTES )
            }
        ),
    };
}

sub _run ($worker) {
    my ( $result, $failure );
    my $pending = $worker->dispatch_p;
    $pending = $pending->then( sub ($value) { $result = $value; return; } );
    $pending->catch( sub ($error) { $failure = $error; return; } )->wait;
    croak $failure if defined $failure;
    return $result;
}

subtest
  'a batch claims once, sends asynchronously, and commits its results once' =>
  sub {
    $calls->jobs( [ _job(1), _job(2) ] );
    $calls->seen( [] );
    my $transport = GPForum::Test::PushTransport->new;
    my $worker    = GPForum::Service::Notification::Push::Worker->new(
        store     => $store,
        transport => $transport
    );
    my $result = _run($worker);
    is( $result->{accepted}, 2, 'both provider acceptances recorded' );
    is( $transport->peak, 2,
        'requests overlap without a sequential network wait' );
    is_deeply(
        [ map { $_->[0] } @{ $calls->seen } ],
        [
            qw(notification_push_cleanup notification_push_claim notification_push_refresh notification_push_finish_batch)
        ],
        'four database calls including fresh permissions and cleanup'
    );
    is( $calls->seen->[1][1]{limit}, $CONCURRENCY, 'global claim bound' );
    is( $calls->seen->[1][1]{per_provider}, 2,     'per-provider claim bound' );
    is( scalar @{ $calls->seen->[$REVOKED_JOB][1]{outcomes} },
        2, 'one result per claimed job' );
    my $sent = $transport->sent->[0];
    is( $sent->{headers}{TTL}, $TTL_SECONDS, 'only the remaining TTL' );
    like(
        $sent->{headers}{Authorization},
        qr/\Avapid[ ]t=/msx,
        'VAPID authorization'
    );
    unlike( $sent->{body}, qr/activation|nonce/msx, 'wire body encrypted' );
    unlike(
        encode_json($result),
        qr/googleapis|nonce|Authorization/msx,
        'metrics carry no capability URL or secrets'
    );
  };

subtest 'revoked read permission stops delivery before any HTTP request' =>
  sub {
    my $job = _job( $REVOKED_JOB, 'alert' );
    $job->{allowed} = 0;
    $calls->jobs( [$job] );
    my $transport = GPForum::Test::PushTransport->new;
    my $worker    = GPForum::Service::Notification::Push::Worker->new(
        store     => $store,
        transport => $transport
    );
    my $result = _run($worker);
    is( $result->{cancelled},         1, 'cancelled' );
    is( scalar @{ $transport->sent }, 0, 'nothing sent' );
  };

subtest 'temporary network failure retries, invalid ciphertext fails closed' =>
  sub {
    my $broken = _job($INVALID_JOB);
    $broken->{envelope} = 'invalid';
    $calls->jobs( [ _job($NETWORK_JOB), $broken ] );
    my $transport = GPForum::Test::PushTransport->new( fail => 1 );
    my $worker    = GPForum::Service::Notification::Push::Worker->new(
        store     => $store,
        transport => $transport
    );
    my $result = _run($worker);
    is( $result->{retry},  1, 'network failure scheduled for retry' );
    is( $result->{failed}, 1, 'bad ciphertext not sent or retried forever' );
  };

subtest
'provider responses retain the distinction between expiry and configuration faults'
  => sub {
    my $worker =
      GPForum::Service::Notification::Push::Worker->new( store => $store );
    for my $case (@HTTP_CASES) {
        my $response = Mojo::Message::Response->new( code => $case->[0] );
        $response->headers->header( 'Retry-After' => '180' );
        my ( $outcome, $delay ) = $worker->outcome( $response, 1 );
        is( $outcome, $case->[1], "HTTP $case->[0]" );
        if ( $outcome eq 'retry' ) {
            cmp_ok( $delay, '>=', $RETRY_SECONDS, 'honors Retry-After' );
        }
    }
  };

subtest
  'TLS peers stay pinned while pooled connections retain provider identity' =>
  sub {
    local $ENV{MOJO_INSECURE}  = 1;
    local $ENV{MOJO_CERT_FILE} = 'private-server-certificate.pem';
    local $ENV{MOJO_KEY_FILE}  = 'private-server-key.pem';
    my $resolver = GPForum::Test::PushResolver->new;
    my @clients;
    my $transport = GPForum::Service::Notification::Push::Transport->new(
        resolver       => $resolver,
        client_factory => sub {
            my $ua = GPForum::Test::PushUserAgent->new;
            push @clients, $ua;
            return $ua;
        }
    );
    my $prepared = _await(
        $transport->prepare_p('https://fcm.googleapis.com/push/test-one') );
    my $reused = _await(
        $transport->prepare_p('https://fcm.googleapis.com/push/test-two') );
    is(
        refaddr( $prepared->{client} ),
        refaddr( $reused->{client} ),
        'same checked origin reuses its client pool'
    );
    is( scalar @clients,
        1, 'no user-agent process or connection pool per message' );
    my $ua = $clients[0];
    is( $ua->tls_options->{SSL_hostname},
        'fcm.googleapis.com', 'TLS SNI remains the provider hostname' );
    is( $ua->tls_options->{SSL_verifycn_name},
        'fcm.googleapis.com',
        'certificate identity remains the provider hostname' );
    is( $ua->tls_options->{SSL_verify_mode},
        1, 'certificate verification required' );
    is( $ua->max_redirects, 0, 'redirects disabled' );
    is( $ua->insecure,      0, 'environment cannot disable TLS verification' );
    is( $ua->cert, undef,
        'unrelated process client certificate is not forwarded' );
    is( $ua->key, undef, 'unrelated process client key is not loaded' );
    ok( $ua->cookie_jar->ignore->(), 'provider cookies are never retained' );
    isa_ok( $ua->proxy, 'GPForum::Service::Integration::DirectProxy' );
    _await(
        $transport->send_prepared_p(
            $prepared, { TTL => $TTL_SECONDS },
            'ciphertext', time + $TTL_SECONDS
        )
    );
    my $tx = $ua->captured->[0];
    is_deeply(
        [ $ua->transactor->peer($tx) ],
        [ 'https', '8.8.8.8', $HTTPS_PORT ],
        'connection uses only the checked IP'
    );
    is( $tx->req->url->host,
        'fcm.googleapis.com', 'request URL retains its original hostname' );
    is( $tx->req->headers->content_encoding,
        'aes128gcm', 'standard wire encoding' );
    $resolver->peer(
        { address => '127.0.0.1', expires => time + $TTL_SECONDS } );
    my $failed;
    $transport->prepare_p('https://fcm.googleapis.com/push/rebound')
      ->catch( sub { $failed = 1; return; } )
      ->wait;
    ok( $failed,
        'a renewed private DNS peer cannot reuse the old public pool' );
  };

subtest 'unsafe signing configuration stops before any queue claim' => sub {
    my $worker = GPForum::Service::Notification::Push::Worker->new(
        store     => $store,
        transport => GPForum::Test::PushTransport->new
    );
    $calls->seen( [] );
    chmod $UNSAFE_PRIVATE_MODE, "$directory/private.json";
    dies_ok { _run($worker) } 'unsafe private file is rejected before dispatch';
    is( scalar @{ $calls->seen },
        0, 'pending deliveries are preserved for configuration repair' );
    chmod $SAFE_PRIVATE_MODE, "$directory/private.json";
};

subtest 'provider backoff memory stays bounded across changing subdomains' =>
  sub {
    my $worker =
      GPForum::Service::Notification::Push::Worker->new( store => $store );
    $worker->cooldown->{'expired.example'} = time - 1;
    for my $number ( 0 .. $COOLDOWN_ENTRIES ) {
        $worker->_pause_origin( "https://$number.push.apple.com",
            time + $TTL_SECONDS );
    }
    is( scalar keys %{ $worker->cooldown },
        $COOLDOWN_ENTRIES, 'changing hosts cannot grow memory without limit' );
    ok( !exists $worker->cooldown->{'expired.example'},
        'expired origin pauses are removed' );
    my $origin = 'https://last.push.apple.com';
    $worker->_pause_origin( $origin, time + $RETRY_SECONDS );
    my $deadline = $worker->cooldown->{$origin};
    $worker->_pause_origin( $origin, time + $TTL_SECONDS );
    is( $worker->cooldown->{$origin},
        $deadline,
        'later responses cannot shorten an existing provider pause' );
  };

done_testing();

1;

sub _await ($pending) {
    my ( $value, $failure );
    $pending = $pending->then( sub ($answer) { $value = $answer; return; } );
    $pending->catch( sub ($error) { $failure = $error; return; } )->wait;
    croak $failure if defined $failure;
    return $value;
}
1;
