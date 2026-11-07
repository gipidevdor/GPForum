# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use Digest::SHA qw(sha256_hex);
use Crypt::JWT  qw(decode_jwt);
use Test::More;
use Test::Exception;
use File::Temp   qw(tempdir);
use MIME::Base64 qw(decode_base64url encode_base64url);
use Crypt::PK::ECC;
use lib 'lib';
use GPForum::Service::Notification::Push::Crypto;
use GPForum::Service::Notification::Push::Endpoint;
use GPForum::Service::Notification::Push::Keyring;
use GPForum::Service::Notification::Push::Secrets;

const my $KEY_ID_DIGITS => 16;
const my $VAPID_SECONDS => 900;
const my $AUTH_BYTES    => 16;
const my $CACHE_POINTS  => 256;
const my $LAST_INDEX    => -1;
our $VERSION = '0.001';
const my $POINT_FORMAT     => 4;
const my $KEY_BYTES        => 32;
const my $COORDINATE_BYTES => 64;
const my $PRIVATE_MODE     => oct '0600';
const my $PUBLIC_MODE      => oct '0644';
const my $MODE_MASK        => oct '0777';
const my $OVERSIZE_PAYLOAD => 1025;

my $crypto = GPForum::Service::Notification::Push::Crypto->new;
my $keys   = {
    auth   => 'BTBZMqHH6r4Tts7J_aSIgg',
    p256dh =>
'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4'
};

subtest 'RFC 8291 section 5, exact published wire bytes' => sub {
    my $sender = Crypt::PK::ECC->new->import_key_raw(
        decode_base64url('yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw'),
        'prime256v1' );
    my $encrypted = $crypto->encrypt(
        $keys,
        'When I grow up, I want to be a watermelon',
        {
            sender => $sender,
            salt   => decode_base64url('DGv6ra1nlYgDCS1FRnbzlw')
        }
    );
    is(
        encode_base64url($encrypted),
'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIg'
          . 'Dll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVB'
          . 'St2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN',
        'matches independent standard vector'
    );
    isnt(
        $crypto->encrypt( $keys, 'same' ),
        $crypto->encrypt( $keys, 'same' ),
        'production encryption generates a fresh salt and ECDH key'
    );
    dies_ok { $crypto->encrypt( $keys, 'x' x $OVERSIZE_PAYLOAD ) }
    'oversized plaintext refused';
    dies_ok { $crypto->receiver( { %{$keys}, auth => $keys->{auth} . q{=} } ) }
    'padded base64url refused';
    dies_ok {
        $crypto->receiver(
            {
                %{$keys},
                p256dh => encode_base64url(
                    ( chr $POINT_FORMAT ) . "\0" x $COORDINATE_BYTES
                )
            }
        )
    }
    'off-curve public point refused';
};

subtest 'database ciphertext is authenticated to its row and purpose' => sub {
    my $key    = ( chr 1 ) x $KEY_BYTES;
    my $sealed = $crypto->seal( $key, 'subscription:member:hash',
        { endpoint => 'secret' } );
    is_deeply(
        $crypto->unseal( $key, 'subscription:member:hash', $sealed ),
        { endpoint => 'secret' },
        'round trip'
    );
    dies_ok { $crypto->unseal( $key, 'subscription:other:hash', $sealed ) }
    'another owner refused';
    dies_ok { $crypto->unseal( $key, 'activation:member:hash', $sealed ) }
    'another purpose refused';
    dies_ok {
        $crypto->unseal( ( chr 2 ) x $KEY_BYTES,
            'subscription:member:hash', $sealed )
    }
    'wrong key refused';
    my @octets = unpack 'C*', decode_base64url($sealed);
    $octets[$LAST_INDEX] ^= 1;
    my $tampered = pack 'C*', @octets;
    dies_ok {
        $crypto->unseal( $key, 'subscription:member:hash',
            encode_base64url($tampered) )
    }
    'tampering refused';
};

subtest 'endpoint policy rejects cross-provider and local destinations' => sub {
    my $policy = GPForum::Service::Notification::Push::Endpoint->new;
    is(
        $policy->parse('https://FCM.GOOGLEAPIS.COM:443/wp/opaque')->to_string,
        'https://fcm.googleapis.com/wp/opaque',
        'equivalent authority has one endpoint identity'
    );
    for my $url (
        'https://fcm.googleapis.com/fcm/send/opaque',
        'https://updates.push.services.mozilla.com/wpush/v2/opaque',
        'https://web.push.apple.com/opaque',
        'https://wns2-test.notify.windows.com/w/?token=opaque'
      )
    {
        lives_ok { $policy->parse($url) } 'approved provider';
    }
    for my $url (
        'http://fcm.googleapis.com/push',
        'https://fcm.googleapis.com.evil.com/push',
        'https://evilpush.apple.com/push',
        'https://fcm.googleapis.com:444/push',
        'https://user@fcm.googleapis.com/push',
        'https://fcm.googleapis.com/push#secret',
        'https://127.0.0.1/push',
        'https://[::ffff:127.0.0.1]/push',
        'https://169.254.169.254/latest/meta-data',
        'https://fcm.googleapis.com/'
      )
    {
        dies_ok { $policy->parse($url) } 'unsafe target refused';
    }
    for my $ip (
        qw(127.0.0.1 10.0.0.1 169.254.169.254 192.168.1.1 100.64.1.1 ::1 ::ffff:8.8.8.8)
      )
    {
        ok( !$policy->public_address($ip),
            'reserved or unsupported address refused' );
    }
    ok( $policy->public_address('8.8.8.8'), 'public IPv4 accepted' );
};

subtest 'rotation preserves receiver identity and storage encryption' => sub {
    my $directory = tempdir( CLEANUP => 1 );
    my $generator = GPForum::Service::Notification::Push::Keyring->new(
        directory => $directory );
    my $first   = $generator->generate;
    my $secrets = GPForum::Service::Notification::Push::Secrets->new(
        directory => $directory );
    my $storage = $secrets->storage;
    dies_ok { $generator->generate } 'existing keys never silently replaced';
    my $rotated = $generator->generate(1);
    isnt( $rotated->{key_id}, $first->{key_id}, 'new signing identity' );
    is( $secrets->storage, $storage, 'database key preserved' );
    ok( exists $secrets->private->{keys}{ $first->{key_id} },
        'old private key retained' );
    ok( exists $secrets->public->{keys}{ $first->{key_id} },
        'old public key retained' );
    is( ( stat "$directory/private.json" )[2] & $MODE_MASK,
        $PRIVATE_MODE, 'private mode' );
    chmod $PUBLIC_MODE, "$directory/private.json";
    dies_ok { $secrets->private } 'unsafe private file mode refused';
};

subtest
  'VAPID signatures bind the short-lived token to the exact provider origin' =>
  sub {
    my $signer  = Crypt::PK::ECC->new->generate_key('prime256v1');
    my $encoded = encode_base64url( $signer->export_key_raw('public') );
    my $key_id  = substr sha256_hex($encoded), 0, $KEY_ID_DIGITS;
    my $private = encode_base64url( $signer->export_key_raw('private') );
    my $authorization =
      $crypto->authorization( 'https://fcm.googleapis.com', $key_id, $private,
        'mailto:ops@example.com' );
    my ($jwt) = $authorization =~ /\Avapid[ ]t=([^,]+)/msx;
    my $claims = decode_jwt(
        token        => $jwt,
        key          => $signer,
        accepted_alg => 'ES256',
        verify_exp   => 1
    );
    is( $claims->{aud}, 'https://fcm.googleapis.com',
        'audience contains the origin, not the capability path' );
    is( $claims->{sub}, 'mailto:ops@example.com', 'operator contact' );
    cmp_ok( $claims->{exp} - time,
        '<=', $VAPID_SECONDS, 'short signing lifetime' );
    is(
        $crypto->authorization(
            'https://fcm.googleapis.com', $key_id,
            $private,                     'mailto:ops@example.com'
        ),
        $authorization,
        'same-origin sends reuse the signature'
    );
    isnt(
        $crypto->authorization(
            'https://web.push.apple.com', $key_id,
            $private,                     'mailto:ops@example.com'
        ),
        $authorization,
        'another origin receives a separate signature'
    );
    dies_ok {
        $crypto->authorization( 'https://fcm.googleapis.com', 'invalid',
            $private, 'mailto:ops@example.com' )
    }
    'a mislabeled private key fails closed';
  };

subtest
'cached curve validation is bounded and never caches the authentication secret'
  => sub {
    my $cached  = GPForum::Service::Notification::Push::Crypto->new;
    my $parsed  = $cached->receiver($keys);
    my $changed = { %{$keys}, auth => encode_base64url( 'z' x $AUTH_BYTES ) };
    is(
        $cached->receiver($changed)->{auth},
        'z' x $AUTH_BYTES,
        'new authentication material is decoded on every use'
    );
    dies_ok { $cached->receiver( { %{$keys}, auth => 'invalid' } ) }
    'cache hit cannot bypass secret validation';
    for ( 1 .. $CACHE_POINTS ) {
        my $point = Crypt::PK::ECC->new->generate_key('prime256v1');
        $cached->receiver(
            {
                %{$keys},
                p256dh => encode_base64url( $point->export_key_raw('public') )
            }
        );
    }
    is( scalar keys %{ $cached->receiver_points },
        $CACHE_POINTS, 'curve-point cache has a fixed capacity' );
    is( scalar @{ $cached->receiver_order },
        $CACHE_POINTS, 'eviction bookkeeping is bounded too' );
  };

done_testing();

1;
