# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Email::Sender::Transport::Test;
use Encode qw(decode);
use Test::More;

use lib 'lib';

use GPForum::Config;
use GPForum::Service::Identity::Mailer;
use GPForum::Service::Identity::SecondFactorCodes;
use GPForum::Service::Identity::SecretBox;
use GPForum::Web::QrCode;
use GPForum::Worker::Handler::IdentityMail;

our $VERSION = '0.001';

const my $RFC_SECRET      => '12345678901234567890';
const my $CODES           => 10;
const my $USER            => '6f1c2f1e-0f6a-4d55-9d3a-2b0d7f9a1c11';
const my $OTHER           => '7a2d3e4f-1b2c-4d5e-8f90-a1b2c3d4e5f6';
const my $LONG_KEY        => 'k' x 40;
const my $NEW_KEY         => 'n' x 40;
const my $OLD_KEY         => 'o' x 40;
const my $SECRET_BYTES    => 20;
const my $FINDER          => 7;
const my $VERSION_1       => 21;
const my $RFC_TIME        => 1_111_111_111;
const my $DRIFT           => 1;
const my $BEYOND          => 2;
const my $TOO_LONG        => 100;
const my $TOO_LONG_FOR_QR => 300;

# ADR 0142: the codes an authenticator app makes, the recovery codes, the
# box the secrets are sealed in, the QR code drawn on the server, the key's
# settings and the notice mails.
my $codes = GPForum::Service::Identity::SecondFactorCodes->new;

subtest 'RFC 6238 codes, six digits of the SHA-1 test vectors' => sub {
    my %vector = (
        '59'          => '287082',
        '1111111109'  => '081804',
        '1111111111'  => '050471',
        '1234567890'  => '005924',
        '2000000000'  => '279037',
        '20000000000' => '353130',
    );
    for my $time ( sort { $a <=> $b } keys %vector ) {
        is( $codes->code_at( $RFC_SECRET, $codes->step_at($time) ),
            $vector{$time}, "the code at $time" );
    }
    is(
        $codes->base32($RFC_SECRET),
        'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
        'RFC 4648 base32'
    );
    is( $codes->grouped('ABCDEFGHIJ'), 'ABCD EFGH IJ', 'grouped by four' );
};

subtest 'a code is taken one step either side of now, and no further' => sub {
    my $now  = $RFC_TIME;
    my $step = $codes->step_at($now);
    for my $offset ( -$DRIFT .. $DRIFT ) {
        is(
            $codes->matching_step(
                $RFC_SECRET, $codes->code_at( $RFC_SECRET, $step + $offset ),
                $now
            ),
            $step + $offset,
            "offset $offset"
        );
    }
    for my $offset ( -$BEYOND, $BEYOND ) {
        is(
            $codes->matching_step(
                $RFC_SECRET, $codes->code_at( $RFC_SECRET, $step + $offset ),
                $now
            ),
            undef,
            "offset $offset is refused"
        );
    }
    is( $codes->matching_step( $RFC_SECRET, '050 471', $now ),
        $step, 'spaces are allowed' );
    for my $wrong ( '05047', '0504711', 'abcdef', q{}, undef, '1' x $TOO_LONG )
    {
        is( $codes->matching_step( $RFC_SECRET, $wrong, $now ),
            undef, 'a text not shaped as a code is refused' );
    }
    ok( $codes->totp_shaped('123 456'),    'six digits are a code' );
    ok( !$codes->totp_shaped('abcd-efgh'), 'letters are not' );
};

subtest 'the link an authenticator app reads' => sub {
    is(
        $codes->otpauth_uri( $RFC_SECRET, 'GP Forum', 'ada' ),
        'otpauth://totp/GP%20Forum:ada?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'
          . '&issuer=GP%20Forum&algorithm=SHA1&digits=6&period=30',
        'issuer, account, secret and the defaults written out'
    );
    is( length $codes->new_secret, $SECRET_BYTES, 'a new secret is 160 bits' );
};

subtest 'recovery codes' => sub {
    my $fresh = $codes->new_recovery_codes;
    is( scalar @{$fresh}, $CODES, 'ten of them' );
    my %seen = map { $_ => 1 } @{$fresh};
    is( scalar keys %seen, $CODES, 'distinct' );
    for my $code ( @{$fresh} ) {
        like(
            $code,
            qr/\A [[:lower:]2-7]{4} (?: - [[:lower:]2-7]{4} ){3} \z/msx,
            "$code is shaped"
        );
    }
    my $code = $fresh->[0];
    ( my $bare = uc $code ) =~ s/-//gmsx;
    is(
        $codes->normalize_recovery_code(" $bare "),
        $codes->normalize_recovery_code($code),
        'any case, with or without dashes, is one code'
    );
    is( $codes->normalize_recovery_code('123456'), undef, 'a TOTP is not one' );
    my $normal = $codes->normalize_recovery_code($code);
    like(
        $codes->recovery_hash( $USER, $normal ),
        qr/\A [[:xdigit:]]{64} \z/msx,
        'kept as SHA-256'
    );
    isnt(
        $codes->recovery_hash( $USER,  $normal ),
        $codes->recovery_hash( $OTHER, $normal ),
        'bound to its member'
    );
};

subtest 'the secret box' => sub {
    my $box = GPForum::Service::Identity::SecretBox->new( keys => [$LONG_KEY] );
    ok( $box->available, 'a key makes it available' );
    my ( $sealed, $key_id ) = $box->seal( $RFC_SECRET, $USER );
    is( $key_id, $box->current_key_id, 'sealed under the current key' );
    unlike( $sealed, qr/\Q$RFC_SECRET\E/msx, 'the secret is not in it' );
    is( $box->unseal( $sealed, $USER ), $RFC_SECRET,
        'it opens for its member' );
    is( $box->unseal( $sealed, $OTHER ), undef, 'and for nobody else' );
    my ($again) = $box->seal( $RFC_SECRET, $USER );
    isnt( $again, $sealed, 'a fresh nonce each time' );

    my ( $format, $id, $nonce, $ciphertext, $tag ) = split /[.]/msx, $sealed;
    my $tampered = join q{.}, $format, $id, $nonce,
      ( $ciphertext =~ tr/A-Za-z/B-ZAb-za/r ), $tag;
    is( $box->unseal( $tampered, $USER ), undef, 'an altered one opens not' );
    is( $box->unseal( 'v0.x.y.z.w', $USER ), undef, 'nor another format' );

    my $rotated = GPForum::Service::Identity::SecretBox->new(
        keys => [ $NEW_KEY, $LONG_KEY ] );
    is( $rotated->unseal( $sealed, $USER ),
        $RFC_SECRET, 'a key being rotated out still opens' );
    ok( $rotated->stale($key_id), 'and says it is worth sealing again' );
    ok( !$rotated->stale( $rotated->current_key_id ), 'the current is not' );
    my $forgotten =
      GPForum::Service::Identity::SecretBox->new( keys => [$NEW_KEY] );
    is( $forgotten->unseal( $sealed, $USER ), undef,
        'a key dropped opens not' );

    my $none = GPForum::Service::Identity::SecretBox->new;
    ok( !$none->available, 'without a key it is not available' );
    my $sealed_none = 1;
    try {
        $none->seal( 'x', $USER );
    }
    catch ($error) {
        $sealed_none = 0;
    };
    ok( !$sealed_none, 'and seals nothing' );
};

subtest 'the key in the settings' => sub {
    is_deeply(
        GPForum::Config->new( environment => 'test' )->second_factor_keys,
        [
            GPForum::Config->new( environment => 'development' )
              ->second_factor_keys->[0]
        ],
        'development and test share a fixed key'
    );
    is_deeply(
        GPForum::Config->new( environment => 'production' )->second_factor_keys,
        [],
        'a deployed forum without one has none'
    );
    is_deeply(
        GPForum::Config->new(
            environment                 => 'production',
            second_factor_key           => $LONG_KEY,
            previous_second_factor_keys => [ $OLD_KEY, $LONG_KEY ],
        )->second_factor_keys,
        [ $LONG_KEY, $OLD_KEY ],
        'the current key first, then the earlier ones'
    );
    my @problems =
      map  { $_->{key} }
      grep { $_->{setting} eq 'second_factor_key' } @{ GPForum::Config->new(
            environment       => 'production',
            second_factor_key => 'short',
        )->problems
      };
    is_deeply( \@problems, ['config.short_secret'],
        'production refuses a short key' );
};

subtest 'the QR code' => sub {
    my $modules = GPForum::Web::QrCode->matrix('a');
    is( scalar @{$modules}, $VERSION_1, 'one byte fits version 1' );
    for my $corner (
        [ 0,                    0 ],
        [ 0,                    $VERSION_1 - $FINDER ],
        [ $VERSION_1 - $FINDER, 0 ]
      )
    {
        my ( $row, $column ) = @{$corner};
        is(
            join( q{},
                @{ $modules->[$row] }[ $column .. $column + $FINDER - 1 ] ),
            '1111111',
            "a finder pattern at $row,$column"
        );
    }
    my $uri = $codes->otpauth_uri( $codes->new_secret, 'GPForum', 'ada' );
    my $svg = GPForum::Web::QrCode->svg( $uri, 'Scan "this" <now>' );
    like( $svg, qr/\A<svg [^>]* role="img"/msx, 'an inline SVG image' );
    ok( index( $svg, 'aria-label="Scan &quot;this&quot; &lt;now&gt;"' ) > 0,
        'with its label escaped' );
    unlike( $svg, qr/(?:href|src)=/msx, 'and nothing it loads' );
    my $drawn = 1;
    try {
        GPForum::Web::QrCode->matrix( 'x' x $TOO_LONG_FOR_QR );
    }
    catch ($error) {
        $drawn = 0;
    };
    ok( !$drawn, 'a text longer than version 10 holds is refused' );
};

subtest 'the notice mails, in the member\'s language' => sub {
    my $transport = Email::Sender::Transport::Test->new;
    my $mailer    = GPForum::Service::Identity::Mailer->new(
        public_base_url => 'https://forum.test/',
        transport       => $transport,
    );
    my $handler =
      GPForum::Worker::Handler::IdentityMail->new( mailer => $mailer );
    my $task = $handler->handle(
        {
            event_type => 'identity.mail.requested',
            event_id   => 'e1',
            mail       => {
                kind   => 'second_factor_enabled',
                to     => 'ada@example.test',
                locale => 'it',
            },
        }
    );
    ok( $task->{delivered}, 'delivered without a token' );
    my @sent = map { $_->{email} } $transport->deliveries;
    is( $sent[0]->get_header('To'), 'ada@example.test', 'to the member' );
    like( decode( 'MIME-Header', $sent[0]->get_header('Subject') ),
        qr/attivata/msx, 'in Italian' );
    my $body = decode( 'UTF-8', $sent[0]->get_body );
    like(
        $body,
        qr{https://forum[.]test/settings/security}msx,
        'with the way to the settings'
    );
    ok( !$sent[0]->get_header('List-Unsubscribe'), 'and no unsubscribe' );
    $handler->handle(
        {
            event_type => 'identity.mail.requested',
            mail       => { kind => 'second_factor_locked', to => 'b@x.test' },
        }
    );
    @sent = map { $_->{email} } $transport->deliveries;
    like( decode( 'MIME-Header', $sent[1]->get_header('Subject') ),
        qr/paused/msx, 'English without a language' );
    my $unknown = $handler->handle(
        {
            event_type => 'identity.mail.requested',
            mail       => { kind => 'second_factor_other', to => 'b@x.test' },
        }
    );
    ok( $unknown->{skipped}, 'an unknown kind without a token is skipped' );
};

done_testing();

1;
