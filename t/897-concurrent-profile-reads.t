# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Mojo::IOLoop;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Identity::ProfileReader;
use GPForum::Test::ConcurrentFunctions;

our $VERSION = '0.001';

const my $THREADS_TOTAL => 4;
const my $TRUST_SCORE   => 7;
const my @READS => qw(
  identity_profile_counts identity_profile_threads identity_profile_replies
  community_avatar_status identity_profile_trust
);

# The public profile's five reads depend only on the member, so they all
# start before any of them answers, and each answer reaches its own place
# however late it arrives.
my $functions = GPForum::Test::ConcurrentFunctions->new;
my $reader    = GPForum::Service::Identity::ProfileReader->new(
    schema    => bless( {}, 'GPForum::Test::NoSchema' ),
    functions => $functions,
);

my ( $done, $failure );
my $profile = $reader->public_profile_p( 'ada', {} )->then(
    sub ($answer) { $done   = $answer; return; },
    sub ($error) { $failure = $error;  return; }
);

$functions->answer(
    identity_user_by_identifier => {
        id          => 'user-1',
        username    => 'ada',
        status      => 'active',
        trust_level => 1
    }
);
while ( !$failure && $functions->started->@* <= @READS ) {
    Mojo::IOLoop->one_tick;
}

is_deeply(
    [ sort $functions->started_after_first ],
    [ sort @READS ],
    'the five reads all started before any of them answered'
);
ok( !$done, 'and the profile waits for them' );

my %answer = (
    identity_profile_counts  => { threads => $THREADS_TOTAL },
    identity_profile_threads => [],
    identity_profile_replies => [],
    community_avatar_status  => { attachment_id => 'avatar-1' },
    identity_profile_trust   => { score => $TRUST_SCORE, trust_level => 2 },
);
for my $name ( reverse $functions->started_after_first ) {
    $functions->answer( $name, $answer{$name} );
}
$profile->wait;

is( $failure, undef, 'no read failed' );
is( $done->{profile}{counts}{threads},
    $THREADS_TOTAL, 'the counts came from the counts read' );
is( $done->{profile}{user}{avatar_id},
    'avatar-1', 'the picture came from the picture read' );
is( $done->{profile}{trust}{score},
    $TRUST_SCORE, 'the trust came from the trust read' );

done_testing();

1;
