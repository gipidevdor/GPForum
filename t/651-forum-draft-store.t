# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Forum::DraftStore;
use GPForum::Service::Forum::PostingCommand;
use GPForum::Test::FixedClock;
use GPForum::Test::SqlFunctionHandle;

our $VERSION = '0.001';
const my $OVERSIZED_BODY => 50_001;
const my $MAXIMUM_PURGE  => 1_000;

my $handle = GPForum::Test::SqlFunctionHandle->new;
my $store  = GPForum::Service::Forum::DraftStore->new(
    schema    => $handle,
    clock     => GPForum::Test::FixedClock->new,
    functions => GPForum::Infrastructure::SqlFunction->new( schema => $handle ),
);
is( $store->find( seed_id( user => 2 ), undef ),
    undef, 'no initial draft lookup' );
is( scalar @{ $handle->executed },
    0, 'missing draft id sends no database call' );
my $input = {
    owner_user_id  => seed_id( user => 2 ),
    draft_id       => seed_id( post => 99 ),
    draft_revision => 0,
    kind           => 'thread',
    title          => q{},
    body_source    => q{},
    category_id    => undef,
    thread_id      => undef,
    visibility     => undef,
    command_id     => 'draft-publish'
};
my $large = $store->save( { %{$input}, body_source => 'x' x $OVERSIZED_BODY } );
is( $large->{status}, 'invalid',
    'oversized draft rejected before database call' );
is( scalar @{ $handle->executed }, 0, 'oversized draft sends no call' );
$handle->rows(
    [
        {
            status => 'ok',
            draft  => '{"draft_id":"saved","draft_revision":1}',
            error  => undef
        }
    ]
);
my $saved = $store->save($input);
ok( $saved->{ok}, 'save acknowledges success' );
is( $saved->{draft}{draft_revision}, 1, 'save returns the stored revision' );
like(
    $handle->prepared->[0],
    qr/api[.]forum_draft_save_v2/msx,
    'only versioned routine executes'
);
$handle->rows( [ { deleted => 1 } ] );
is( $store->purge_expired( { limit => 9_999 } )->{deleted},
    1, 'retention returns deletion count' );
is( $handle->executed->[-1][-1], $MAXIMUM_PURGE, 'retention limit is bounded' );
my $codec   = GPForum::Service::Forum::PostingCommand->new;
my $publish = {
    author_user_id => seed_id( user     => 2 ),
    category_id    => seed_id( category => 1 ),
    body_source    => 'body',
    title          => 'Title',
    visibility     => 'public',
    draft_id       => seed_id( post => 99 )
};
is_deeply(
    $codec->request( 'thread.create', { %{$publish}, draft_revision => 1 } ),
    $codec->request( 'thread.create', { %{$publish}, draft_revision => '0' } ),
    'native pre-save revision and acknowledged revision fingerprint identically'
);
ok( exists $codec->request( 'thread.create', $publish )->{draft_id},
    'draft identity is fingerprinted' );
ok( !exists $codec->request( 'thread.create', {} )->{draft_id},
    'legacy fingerprint stays unchanged' );

done_testing();

1;
