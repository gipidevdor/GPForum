# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use JSON::MaybeXS qw(decode_json);
use Test::More;
use lib 'lib', 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Infrastructure::Id;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';
const my $CHOICE_LIMIT   => 50;
const my $PUBLIC_CHOICES => 8;
const my $ALL_CHOICES    => 18;
const my $EXTRA_THREADS  => 100;
const my $OTHER_USER     => 3;
const my $POST_CURSOR    => 3;
const my @VERSIONS       => ( 2, 4 );

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'requires PostgreSQL';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh      = $database->dbh;
my $ids      = GPForum::Infrastructure::Id->new;
my $actor    = seed_id( user => 2 );
my $other    = seed_id( user => $OTHER_USER );
my ( $moderator, $reader ) = ( $ids->uuid, $ids->uuid );
$dbh->do( 'DELETE FROM role_bindings WHERE user_id=?', undef, $actor );

for my $role (
    [ $moderator, 'picker-work-moderator', 'thread',   'moderate' ],
    [ $reader,    'picker-work-reader',    'category', 'read' ]
  )
{
    $dbh->do( 'INSERT INTO roles(role_id,name) VALUES(?,?)',
        undef, @{$role}[ 0, 1 ] );
    $dbh->do(
q{INSERT INTO permissions(permission_id,name,resource_type,action) VALUES(?,?,?,?) ON CONFLICT (resource_type,action) DO NOTHING},
        undef, $ids->uuid, $role->[1], $role->[2], $role->[-1]
    );
    $dbh->do(
q{INSERT INTO role_permissions(role_id,permission_id) SELECT ?,permission_id FROM permissions WHERE resource_type=? AND action=?},
        undef, $role->[0], $role->[2], $role->[-1]
    );
}
$dbh->do(
q{INSERT INTO role_bindings(binding_id,user_id,role_id,resource_type) VALUES(?,?,?,'global')},
    undef, $ids->uuid, $actor, $moderator
);

my ( @spaces, @categories, @threads );
_visibility_fixture();

sub _visibility_fixture {
    for my $space_visibility (qw(public members private)) {
        my $space = $ids->uuid;
        push @spaces, $space;
        $dbh->do(
q{INSERT INTO spaces(space_id,slug,title,visibility) VALUES(?,?,?,?)},
            undef, $space, $space, 'Picker space', $space_visibility
        );
        for my $category_visibility (qw(public members private)) {
            my $category = $ids->uuid;
            push @categories, $category;
            $dbh->do(
q{INSERT INTO categories(category_id,space_id,slug,title,visibility) VALUES(?,?,?,?,?)},
                undef,
                $category,
                $space,
                $category,
                'Picker category',
                $category_visibility
            );
            for my $thread_visibility (qw(public members)) {
                my $thread = $ids->uuid;
                push @threads, $thread;
                $dbh->do(
q{INSERT INTO threads(thread_id,category_id,author_user_id,title,slug,visibility) VALUES(?,?,?,?,?,?)},
                    undef,
                    $thread,
                    $category,
                    $other,
"Picker $space_visibility $category_visibility $thread_visibility",
                    $thread,
                    $thread_visibility
                );
            }
        }
    }
    return;
}

my $public = _same('active moderator without private read grants');
is(
    scalar grep( { $_->{title} =~ /\APicker /msx } @{ $public->{choices} } ),
    $PUBLIC_CHOICES,
    'only public/member ancestors are visible without read grants'
);
for my $binding (
    [ category => $categories[-1], undef ],
    [ space    => $spaces[-1],     undef ],
    [ space    => undef,           $spaces[-1] ],
    [ global   => undef,           undef ]
  )
{
    my $binding_id = $ids->uuid;
    $dbh->do(
q{INSERT INTO role_bindings(binding_id,user_id,role_id,resource_type,resource_id,space_id) VALUES(?,?,?,?,?,?)},
        undef, $binding_id, $actor, $reader, @{$binding}
    );
    my $granted = _same("$binding->[0] read grant");
    cmp_ok(
        scalar @{ $granted->{choices} },
        '>',
        scalar @{ $public->{choices} },
        'the scoped read grant actually exposes additional choices'
    );
    if ( $binding->[0] eq 'global' ) {
        is(
            scalar grep( { $_->{title} =~ /\APicker /msx }
                @{ $granted->{choices} } ),
            $ALL_CHOICES,
            'the global read grant reaches every fixture scope'
        );
    }
    _same( 'selected source and matching destination audience', $threads[-1] );
    $dbh->do( 'UPDATE role_bindings SET revoked_at=now() WHERE binding_id=?',
        undef, $binding_id );
    _same('revocation is visible on the next call');
}
for my $query ( 'Picker public', 'unmatched', q{%}, '_' ) {
    _same( "query $query", undef, $query );
}
for my $state (
    q{locked_at=now()},           q{deleted_at=now()},
    q{moderation_state='hidden'}, q{visibility='private'}
  )
{
    $dbh->begin_work;
    $dbh->do( "UPDATE threads SET $state WHERE thread_id=?",
        undef, $threads[0] );
    _same("ineligible thread: $state");
    _same( 'ineligible source is refused', $threads[0] );
    $dbh->rollback;
}
for my $relation (qw(categories spaces)) {
    $dbh->begin_work;
    my $key = $relation eq 'categories' ? 'category_id'  : 'space_id';
    my $id  = $relation eq 'categories' ? $categories[0] : $spaces[0];
    $dbh->do( "UPDATE $relation SET deleted_at=now() WHERE $key=?", undef,
        $id );
    _same("deleted $relation are excluded");
    $dbh->rollback;
}
$dbh->do(
q{INSERT INTO thread_polls(thread_id,question,closes_at) VALUES(?,'Picker poll',now()+interval '1 day')},
    undef, $threads[0]
);
_same('polls are excluded');
_same( 'poll source is refused', $threads[0] );
_same( 'seeded source posts',    seed_id( thread => 1 ) );
_same( 'source post cursor',     seed_id( thread => 1 ), q{}, $POST_CURSOR );
my $suspension = $ids->uuid;
$dbh->do(
q{INSERT INTO suspensions(suspension_id,user_id,actor_user_id,reason) VALUES(?,?,?,'Picker test')},
    undef, $suspension, $actor, $other
);
_same('active suspension refuses the picker');
$dbh->do( 'UPDATE suspensions SET revoked_at=now() WHERE suspension_id=?',
    undef, $suspension );
_same('revoked suspension permits the picker again');

for my $number ( 1 .. $EXTRA_THREADS ) {
    my $thread = $ids->uuid;
    $dbh->do(
q{INSERT INTO threads(thread_id,category_id,author_user_id,title,slug) VALUES(?,?,?,'Extra picker candidate',?)},
        undef, $thread, $categories[0], $other, $thread
    );
}
my $bounded = _same('more candidates than the page size');
is( scalar @{ $bounded->{choices} },
    $CHOICE_LIMIT, 'the full page retains its limit' );
SKIP: {
    if ( $dbh->selectrow_array(q{SHOW is_superuser}) ne 'on' ) {
        skip 'function counters require a superuser fixture', 1;
    }
    $dbh->do(q{SET track_functions='all'});
    my $before = _viewer_calls();
    $dbh->selectrow_array(
q{SELECT result FROM api.moderation_transfer_picker_v4(?::uuid,NULL::uuid,''::text,0::bigint)},
        undef, $actor
    );
    is(
        _viewer_calls() - $before,
        1,
        'a full page resolves the viewer once, independent of candidate count'
    );
}
$dbh->do( q{UPDATE users SET status='suspended' WHERE id=?}, undef, $actor );
_same('inactive moderator is refused');
$dbh->do( q{UPDATE users SET status='active' WHERE id=?}, undef, $actor );
$dbh->do( 'DELETE FROM role_bindings WHERE user_id=?',    undef, $actor );
_same('revoked moderation permission is refused');

done_testing();

sub _same ( $label, $source = undef, $query = q{}, $after = 0 ) {
    my @answers;
    for my $version (@VERSIONS) {
        my ($raw) = $dbh->selectrow_array(
"SELECT result FROM api.moderation_transfer_picker_v$version(?::uuid,?::uuid,?::text,?::bigint)",
            undef, $actor, $source, $query, $after
        );
        push @answers, decode_json($raw);
    }
    is_deeply( $answers[1], $answers[0], $label );
    cmp_ok( scalar @{ $answers[1]{choices} // [] },
        '<=', $CHOICE_LIMIT, 'choice count stays bounded' );
    return $answers[1];
}

sub _viewer_calls {
    $dbh->do('SELECT pg_stat_force_next_flush()');
    $dbh->do('SELECT pg_stat_clear_snapshot()');
    return $dbh->selectrow_array(
q{SELECT coalesce((SELECT calls FROM pg_stat_user_functions WHERE funcid='api.forum_resolve_viewer_v5(uuid)'::regprocedure),0)}
    );
}

1;
