# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use lib 'lib';
use lib 't/lib';

use Const::Fast;
use GPForum::Infrastructure::AuditRecord;
use GPForum::Test::Id;
use Test::More;

our $VERSION = '0.001';

const my $DEFAULT_SCHEMA_VERSION => 1;

my $records = GPForum::Infrastructure::AuditRecord->new(
    id_service => GPForum::Test::Id->new, );
my $first = $records->build(
    {
        action         => 'thread.created',
        actor_id       => 'user-1',
        correlation_id => 'corr-1',
        created_at     => '2026-05-28T08:00:00Z',
        metadata       => { title => 'Welcome' },
        target_id      => 'thread-1',
        target_type    => 'thread',
    },
    undef,
);

ok(
    $records->has_text( $first->{record_hash} ),
    'build computes a canonical record_hash'
);
ok( $records->verify($first), 'verify accepts an untampered record' );

# ADR 0156: the hash covers the stored form, so the row as PostgreSQL hands
# it back -- the time in the session's zone, metadata as jsonb text, the
# schema version as digits -- verifies as the record did.
ok(
    $records->verify(
        {
            %{$first},
            created_at     => '2026-05-28 10:00:00+02',
            metadata       => '{"title": "Welcome"}',
            schema_version => '1',
        }
    ),
    'verify accepts the record as a row read back'
);
ok(
    !$records->verify( { %{$first}, created_at => '2026-05-28 10:00:01+02' } ),
    'and refuses one whose time moved'
);
is( $records->canonical_time('2026-05-28T08:00:00Z'),
    '2026-05-28T08:00:00.000000Z', 'canonical_time adds the microseconds' );
is( $records->canonical_time('2026-05-28 10:00:00.5+02'),
    '2026-05-28T08:00:00.500000Z', 'canonical_time moves a zone to UTC' );
is( $records->canonical_time('yesterday'),
    'yesterday', 'canonical_time leaves other text alone' );
is( $records->chain_key( 'thread', 'thread-1' ),
    'thread:thread-1', 'chain_key names the target' );
is( $records->chain_key( undef, undef ),
    q{:}, 'and the chain of the records with no target' );
is( $first->{audit_id}, 'generated-1',
    'build allocates audit_id when omitted' );
is( $first->{schema_version},
    $DEFAULT_SCHEMA_VERSION, 'build defaults schema_version when omitted' );
is( $first->{previous_hash},
    undef, 'build keeps an empty chain as undef previous_hash' );

my $chained = $records->build(
    {
        action         => 'thread.updated',
        actor_id       => 'user-1',
        correlation_id => 'corr-1',
        created_at     => '2026-05-28T08:01:00Z',
        metadata       => { title => 'Welcome back' },
        target_id      => 'thread-1',
        target_type    => 'thread',
    },
    $first->{record_hash},
);
is( $chained->{previous_hash},
    $first->{record_hash}, 'build chains previous_hash from the recorder' );
isnt( $chained->{record_hash},
    $first->{record_hash}, 'build changes record_hash when content changes' );

my $explicit = $records->build(
    {
        action         => 'thread.moderated',
        actor_id       => 'user-2',
        correlation_id => 'corr-1',
        created_at     => '2026-05-28T08:02:00Z',
        metadata       => { moderation_state => 'locked' },
        previous_hash  => 'explicit-hash',
        record_hash    => q{},
        target_id      => 'thread-1',
        target_type    => 'thread',
    },
    $chained->{record_hash},
);
is( $explicit->{previous_hash},
    'explicit-hash', 'build prefers an explicit previous_hash over the chain' );

my $blank_previous = $records->build(
    {
        action         => 'thread.moderated',
        actor_id       => 'user-2',
        correlation_id => 'corr-1',
        created_at     => '2026-05-28T08:03:00Z',
        metadata       => { moderation_state => 'locked' },
        previous_hash  => undef,
        record_hash    => q{},
        target_id      => 'thread-1',
        target_type    => 'thread',
    },
    $chained->{record_hash},
);
is(
    $blank_previous->{previous_hash},
    $chained->{record_hash},
    'build ignores blank previous_hash and preserves the chain'
);

my $defaults = $records->build(
    {
        action      => 'user.registered',
        actor_id    => 'user-1',
        target_id   => 'user-1',
        target_type => 'user',
    },
    undef,
);
ok(
    $records->has_text( $defaults->{created_at} ),
    'build stamps created_at when omitted'
);
is_deeply( $defaults->{metadata},
    {}, 'build defaults metadata to an empty hash' );

my %tampered = %{$first};
$tampered{metadata} = { title => 'changed' };
ok( !$records->verify( \%tampered ), 'verify rejects tampered metadata' );
ok(
    !$records->verify( { action => 'thread.created' } ),
    'verify rejects a record without record_hash'
);

done_testing();

1;
