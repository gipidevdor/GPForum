# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use POSIX qw(strftime);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Community::MentionStore;
use GPForum::Service::Forum::CategoryReader;
use GPForum::Service::Forum::DraftStore;
use GPForum::Service::Forum::PostComposer;
use GPForum::Service::Forum::PostReader;
use GPForum::Service::Forum::PostStore;
use GPForum::Service::Forum::PostingWorkflow;
use GPForum::Service::Forum::ThreadComposer;
use GPForum::Service::Forum::ThreadDetailReader;
use GPForum::Service::Forum::ThreadStore;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::FixedClock;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';
const my $OVERSIZED_BODY  => 50_001;
const my $AFTER_RETENTION => 31 * 24 * 60 * 60;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for owner-private drafts';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $schema   = $database->schema;
my $dbh      = $database->dbh;
my $now      = strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime );
my $clock    = GPForum::Test::FixedClock->new( iso8601 => $now );
my $ids      = GPForum::Infrastructure::Id->new;
my $store    = GPForum::Service::Forum::DraftStore->new(
    schema => $schema,
    clock  => $clock
);
my $functions = GPForum::Infrastructure::SqlFunction->new( schema => $schema );
my $owner     = seed_id( user => 2 );
my $other     = seed_id( user => 3 );
my $input     = {
    owner_user_id  => $owner,
    draft_id       => $ids->uuid,
    draft_revision => 0,
    kind           => 'thread',
    category_id    => seed_id( category => 1 ),
    thread_id      => undef,
    title          => 'Private draft',
    body_source    => "  private text\n",
    visibility     => undef,
    command_id     => $ids->uuid
};
my $created = $store->save($input);
ok( $created->{ok}, 'draft created' );
is( $created->{draft}{draft_revision}, 1, 'initial revision is one' );
is( $created->{draft}{body_source},
    $input->{body_source}, 'raw draft source preserved' );
is( $store->save($input)->{draft}{draft_revision},
    1, 'lost acknowledgement is idempotent' );
is(
    $store->save( { %{$input}, draft_revision => 1 } )->{draft}{draft_revision},
    1,
    'acknowledged unchanged snapshot does not increment revision'
);
is( $store->find( $other, $input->{draft_id} ),
    undef, 'other owner cannot load private source' );
is(
    $store->remove(
        {
            owner_user_id  => $other,
            draft_id       => $input->{draft_id},
            draft_revision => 1
        }
    )->{status},
    'not_found',
    'other owner cannot remove draft'
);
is( $store->save( { %{$input}, owner_user_id => $other } )->{status},
    'not_found', 'other owner cannot overwrite draft' );
my $changed = $store->save(
    { %{$input}, draft_revision => 1, body_source => 'Changed body' } );
is( $changed->{draft}{draft_revision}, 2, 'change increments revision' );
is(
    $store->save(
        { %{$input}, draft_revision => 1, body_source => 'Stale overwrite' }
    )->{status},
    'conflict',
    'stale save never overwrites'
);
is( $store->find( $owner, $input->{draft_id} )->{body_source},
    'Changed body', 'winner is retained' );
my $list = $store->list_for_user($owner);
ok( !exists $list->[0]{body_source},
    'list returns metadata without private body payload' );
my $parts = $functions->row( 'portability_export_parts', { user_id => $owner } )
  ->{document};
is( $parts->{drafts}[0]{body_source},
    'Changed body', 'user export includes own draft' );
is(
    scalar @{
        $functions->row( 'portability_export_parts', { user_id => $other } )
          ->{document}{drafts}
    },
    0,
    'export does not include another owner draft'
);
my $sql_large = $functions->row(
    'forum_draft_save',
    {
        %{$input},
        draft_id    => $ids->uuid,
        body_source => 'x' x $OVERSIZED_BODY,
        now         => $now
    }
);
is( $sql_large->{status}, 'invalid',
    'database independently enforces source bound' );
my $reply = {
    %{$input},
    draft_id    => $ids->uuid,
    kind        => 'reply',
    category_id => undef,
    thread_id   => seed_id( thread => 1 ),
    command_id  => $ids->uuid
};
$dbh->do( q{UPDATE threads SET moderation_state='hidden' WHERE thread_id=?},
    undef, $reply->{thread_id} );
is( $store->save($reply)->{status},
    'not_found', 'hidden reply target cannot receive draft' );
$dbh->do( q{UPDATE threads SET moderation_state='visible' WHERE thread_id=?},
    undef, $reply->{thread_id} );
ok( $store->save($reply)->{ok}, 'readable reply target accepts a draft' );
$dbh->do( q{UPDATE users SET status='suspended' WHERE id=?}, undef, $owner );
is( $store->save( { %{$input}, draft_id => $ids->uuid } )->{status},
    'forbidden', 'database refuses suspended author' );
$dbh->do( q{UPDATE users SET status='active' WHERE id=?}, undef, $owner );
my $workflow = _workflow();
my $publish  = {
    viewer =>
      GPForum::Service::Forum::Viewer->new( member => 1, user_id => $owner ),
    author_user_id => $owner,
    category_id    => $input->{category_id},
    title          => $input->{title},
    body_source    => 'Changed body',
    visibility     => undef,
    command_id     => $input->{command_id},
    draft_id       => $input->{draft_id},
    draft_revision => 2
};
is(
    $workflow->create_thread( { %{$publish}, draft_revision => 1 } )->{status},
    'conflict',
    'stale publication preserves draft and writes no thread'
);
ok(
    $store->find( $owner, $input->{draft_id} ),
    'stale publication retains draft'
);
my $posted = $workflow->create_thread($publish);
ok( $posted->{ok}, 'draft publication succeeds' );
is( $store->find( $owner, $input->{draft_id} ),
    undef, 'successful publication consumes draft' );
is( $store->save($input)->{status},
    'not_found', 'native revision-zero retry cannot recreate consumed draft' );
my $replayed = $workflow->create_thread( { %{$publish}, draft_revision => 0 } );
ok(
    $replayed->{ok} && $replayed->{idempotent},
    'publication retries replay after draft deletion'
);
is(
    $replayed->{stored}{thread}{thread_id},
    $posted->{stored}{thread}->thread_id,
    'retry returns original thread'
);
my $invalid =
  { %{$input}, draft_id => $ids->uuid, title => 'x', command_id => $ids->uuid };
my $invalid_saved = $store->save($invalid);
my $failed_input  = {
    %{$publish},
    title          => 'x',
    body_source    => $invalid->{body_source},
    draft_id       => $invalid->{draft_id},
    draft_revision => 1,
    command_id     => $invalid->{command_id}
};
is( $workflow->create_thread($failed_input)->{status},
    'invalid', 'validation refusal is recorded' );
ok(
    $store->find( $owner, $invalid->{draft_id} ),
    'validation failure retains source'
);
my $renewed = $store->save( { %{$invalid}, draft_revision => 1 } );
isnt(
    $renewed->{draft}{command_id},
    $invalid->{command_id},
    'refused nonce rotates on unchanged save'
);
my $rollback = {
    %{$input},
    draft_id   => $ids->uuid,
    title      => 'Rollback draft',
    command_id => $ids->uuid
};
ok( $store->save($rollback)->{ok}, 'rollback fixture saved' );
$dbh->do(
q{CREATE FUNCTION public.fail_draft_publish() RETURNS trigger LANGUAGE plpgsql }
      . q{AS 'BEGIN RAISE EXCEPTION ''fixture publication failure''; END'} );
$dbh->do( q{CREATE TRIGGER fail_draft_publish BEFORE INSERT ON public.posts }
      . q{FOR EACH ROW EXECUTE FUNCTION public.fail_draft_publish()} );
is(
    $workflow->create_thread(
        {
            %{$publish},
            draft_id       => $rollback->{draft_id},
            draft_revision => 1,
            title          => $rollback->{title},
            body_source    => $rollback->{body_source},
            command_id     => $rollback->{command_id}
        }
    )->{status},
    'failed',
    'database failure aborts publication'
);
ok( $store->find( $owner, $rollback->{draft_id} ),
    'database rollback retains draft' );
is(
    $dbh->selectrow_array(
        'SELECT count(*) FROM command_log WHERE idempotency_key=?', undef,
        $rollback->{command_id}
    ),
    0,
    'failed transaction leaves no consumed command'
);
$functions->row( 'privacy_revoke_user',
    { source => 'ForumDraft', user_id => $owner, at => $now } );
is( scalar @{ $store->list_for_user($owner) },
    0, 'erasure routine deletes all owner drafts' );
my $expired = $store->save(
    { %{$input}, draft_id => $ids->uuid, command_id => $ids->uuid } );
$clock->iso8601(
    strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime( time + $AFTER_RETENTION ) ) );
is( $store->find( $owner, $expired->{draft}{draft_id} ),
    undef, 'expired draft cannot be restored' );
is( $store->purge_expired( { limit => 1 } )->{deleted},
    1, 'bounded retention deletes expired draft' );

done_testing();

sub _workflow {
    my $posts = GPForum::Service::Forum::PostReader->new( schema => $schema );
    return GPForum::Service::Forum::PostingWorkflow->new(
        category_reader =>
          GPForum::Service::Forum::CategoryReader->new( schema => $schema ),
        post_reader          => $posts,
        thread_detail_reader =>
          GPForum::Service::Forum::ThreadDetailReader->new(
            schema      => $schema,
            post_reader => $posts
          ),
        mention_store =>
          GPForum::Service::Community::MentionStore->new( schema => $schema ),
        post_composer =>
          GPForum::Service::Forum::PostComposer->new( id_service => $ids ),
        thread_composer =>
          GPForum::Service::Forum::ThreadComposer->new( id_service => $ids ),
        post_store => GPForum::Service::Forum::PostStore->new(
            schema     => $schema,
            id_service => $ids,
            clock      => $clock
        ),
        thread_store => GPForum::Service::Forum::ThreadStore->new(
            schema     => $schema,
            id_service => $ids,
            clock      => $clock
        ),
        command_idempotency =>
          GPForum::Service::Operations::CommandIdempotency->new(
            schema     => $schema,
            id_service => $ids,
            clock      => $clock
          ),
    );
}

1;
