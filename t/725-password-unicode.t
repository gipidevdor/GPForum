# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use utf8;

use Const::Fast;
use Crypt::Argon2 qw(argon2id_pass);
use Encode        qw(encode);
use Test::More;
use lib 'lib';

use GPForum::Service::Password;

our $VERSION = '0.001';

const my $SALT_BYTES => 16;
const my $ITERATIONS => 3;
const my $TAG_BYTES  => 32;

# A hash of a password's Latin-1 octets, as a GPForum before any release
# made one: nothing released holds such a hash, and it does not verify.
const my $LATIN_OCTETS =>
'$argon2id$v=19$m=32768,t=3,p=1$MDEyMzQ1Njc4OWFiY2RlZg$OD15i2eb2/OMJus3al8CIm4jGS7Mq3P5qhyxwtkncBo';

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
ok(
    !$service->verify_password( 'legacy café password', $LATIN_OCTETS ),
    'a hash of Latin-1 octets does not verify: passwords are UTF-8'
);

# A hash made while the salt carried an encoding marker still verifies: the
# salt is read from the hash.
my $marked = argon2id_pass(
    encode( 'UTF-8', 'marked café password' ),
    'gpforum:utf8:' . ( 'x' x $SALT_BYTES ),
    $ITERATIONS, '32M', 1, $TAG_BYTES
);
ok( $service->verify_password( 'marked café password', $marked ),
    'a hash with the old salt marker verifies' );
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
