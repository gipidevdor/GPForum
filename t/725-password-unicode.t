# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use utf8;

use Const::Fast;
use Test::More;
use lib 'lib';

use GPForum::Service::Password;

our $VERSION = '0.001';

# Produced by the previous Password boundary, with its original 16-byte salt
# and Latin-1 password octets. They are public regression fixtures.
const my $LEGACY_LATIN =>
'$argon2id$v=19$m=32768,t=3,p=1$MDEyMzQ1Njc4OWFiY2RlZg$OD15i2eb2/OMJus3al8CIm4jGS7Mq3P5qhyxwtkncBo';
const my $LEGACY_AMBIGUOUS =>
'$argon2id$v=19$m=32768,t=3,p=1$MDEyMzQ1Njc4OWFiY2RlZg$pVvR6mdSLNYg2Yo4fe68Cmj2UXdtwWblAWIWxREgRVE';

my $service = GPForum::Service::Password->new;
for my $password (
    'пароль для форума',
    '论坛密码保持安全测试字符',
    'emoji 🔒 password',
    '  exact café password  '
  )
{
    my $before = $password;
    my $hash   = $service->hash_password($password);
    like(
        $hash,
        qr/\A \x{24} argon2id \x{24}/msx,
        'Unicode uses the standard Argon2id encoded format'
    );
    ok(
        $service->verify_password( $password, $hash ),
        'the exact Unicode password verifies'
    );
    ok(
        !$service->verify_password( $password . 'x', $hash ),
        'a different Unicode password is refused'
    );
    is( $password, $before, 'hashing and verification preserve the input' );
}

my $latin_hash = $service->hash_password('new café password');
ok(
    !$service->verify_password( 'new cafÃ© password', $latin_hash ),
    'UTF-8 hashes never fall back to an ambiguous legacy encoding'
);
ok( $service->verify_password( 'legacy café password', $LEGACY_LATIN ),
    'existing Latin-1 passwords continue to verify' );
ok( !$service->verify_password( 'legacy cafÃ© password', $LEGACY_LATIN ),
    'a different Latin-1 password is refused' );
ok(
    $service->verify_password( 'legacy ä¸­ password', $LEGACY_AMBIGUOUS ),
    'the original legacy character sequence still verifies'
);
ok(
    !$service->verify_password( 'legacy 中 password', $LEGACY_AMBIGUOUS ),
    'wide characters cannot impersonate different legacy password bytes'
);
ok(
    !$service->verify_password( 'unknown 🔒 password', $service->decoy_hash ),
    'unknown-account verification accepts Unicode input without throwing'
);

my $short;
try { $service->hash_password('短短短短短短短短短短短'); }
catch ($error) { $short = $error; };
ok( GPForum::X::Argument->caught($short),
    'minimum length still counts Unicode characters, not encoded bytes' );

done_testing();

1;
