# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

# The privacy writes as the web worker runs them. Without a METHOD_p
# call_p ran each blocking write -- an export with its bundle, a deletion
# request, its approval, a legal hold and its release, the erasure itself --
# in a forked child that opened a PostgreSQL connection of its own, one
# child at a time per worker. Each promise here must answer what its
# blocking twin answers and leave the same rows behind, on a member of its
# own, without reaching a fork fallback.
package main;
use v5.40;
use Const::Fast;
use Test::More;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Infrastructure::AsyncWork;
use GPForum::Test::PgDatabase;
use GPForum::Test::Promise qw(await_result);
use GPForum::Test::Forks   qw(children_during);

our $VERSION = '0.001';
const my $HEX  => qr/[[:xdigit:]]/msx;
const my $UUID => qr/$HEX {8} - $HEX {4} - $HEX {4} - $HEX {4} - $HEX {12}/msx;
const my $COMPACT_ID  => qr/$HEX {32}/msx;
const my $NAME_DIGITS => 12;

# The values each write draws for itself (times, generated stamps) or each
# fixture post takes (its place in the thread).
const my %DRAWN => map { $_ => 1 } qw(generated_at timestamp position);

const my $MEMBER_SQL => <<'SQL';
INSERT INTO users (id, username, display_name, email_normalized,
  password_hash, status)
VALUES (gen_random_uuid(), ?, 'Privacy member', ?, 'not-a-hash', 'active')
RETURNING id
SQL
const my $SESSION_SQL => <<'SQL';
INSERT INTO sessions (session_id, user_id, session_hash, expires_at)
VALUES (gen_random_uuid(), ?, md5(random()::text),
        now() + interval '1 day')
SQL
const my $POST_SQL => <<'SQL';
INSERT INTO posts (post_id, thread_id, author_user_id, position)
SELECT gen_random_uuid(), thread_id, ?,
       (SELECT coalesce(max(position), 0) + 1 FROM posts p
        WHERE p.thread_id = t.thread_id)
FROM threads t ORDER BY t.created_at LIMIT 1 RETURNING post_id
SQL
const my $BODY_SQL => <<'SQL';
INSERT INTO post_bodies (body_id, post_id, body_source, body_rendered_safe,
  source_hash)
VALUES (gen_random_uuid(), ?, 'Exported post', '<p>Exported post</p>', 'hash')
RETURNING body_id
SQL

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to compare privacy write promises';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
my $dbh   = $database->dbh;
my $owner = seed_id( user => 1 );
my $t     = Test::Mojo->new('GPForum');
my $c     = $t->app->build_controller;
my $w     = $c->gp_privacy_workflow;

# Every child a write starts, recorded instead of trusted. The CPU lane
# (cpu_p, a child that cannot reach PostgreSQL) is counted apart and is no
# fallback.
my $children = children_during( \&writes );
is_deeply( $children->{other}, [], 'no privacy write reached a fork fallback' );

my $app_schema = $c->app->gp_schema;
$app_schema->storage->disconnect;
$database->schema->storage->disconnect;

done_testing;

sub writes {
    subtest 'an export, its bundle and its replay' => sub {
        my ( $a, $b ) = members(2);
        my $ids = { $b => $a };
        my $blocking =
          $w->request_export( { command_id => uuid(), user_id => $a } );
        my $command  = uuid();
        my $promised = await_result(
            $w->request_export_p(
                { command_id => $command, user_id => $b }, undef
            )
        );
        is( $promised->{status}, 'ok', 'the promised export succeeds' );
        is( $promised->{stored}{status},
            'completed', 'and completes the bundle' );
        is_deeply(
            plain( $promised, $ids ),
            plain( $blocking, {} ),
            'request_export: promise = blocking'
        );
        is_deeply(
            plain(
                await_result(
                    $w->request_export_p(
                        { command_id => $command, user_id => $b }, undef
                    )
                ),
                $ids
            ),
            plain( $promised, $ids ),
            'the same command id replays the promised export'
        );
        is_deeply( member_rows($b), member_rows($a),
            'both members keep the same export and records' );
    };

    subtest 'deletion requested, approved and erased' => sub {
        my ( $a, $b ) = members(2);
        my $ids = { $b => $a };
        my ( $blocking, $promised ) = @{
            same_effect( 'request_deletion', { reason => 'leaving' },
                $a, $b, $ids )
        };
        is( $promised->{status}, 'ok', 'the promised request succeeds' );
        my $pair = {
            $promised->{stored}{deletion_request_id} =>
              $blocking->{stored}{deletion_request_id},
            %{$ids}
        };
        is_deeply(
            plain(
                await_result(
                    $w->request_deletion_p(
                        command( reason => 'again', user_id => $b ), undef
                    )
                ),
                $pair
            ),
            plain( $promised, $pair ),
            'asking again answers the open request'
        );

        my ( $approved_a, $approved_b ) = pair(
            'approve_deletion',
            review( $blocking->{stored}{deletion_request_id} ),
            review( $promised->{stored}{deletion_request_id} ), $pair
        );
        is( $approved_b->{status}, 'ok', 'the promised approval succeeds' );
        $pair->{ $approved_b->{stored}{job}{erasure_job_id} } =
          $approved_a->{stored}{job}{erasure_job_id};
        my ( $replayed_a, $replayed_b ) = pair(
            'approve_deletion',
            review( $blocking->{stored}{deletion_request_id} ),
            review( $promised->{stored}{deletion_request_id} ), $pair
        );
        is( $replayed_b->{stored}{idempotent},
            1, 'a second approval replays it' );

        my ( $erased_a, $erased_b ) = pair(
            'run_erasure_job',
            job( $approved_a->{stored}{job}{erasure_job_id} ),
            job( $approved_b->{stored}{job}{erasure_job_id} ), $pair
        );
        is( $erased_b->{status}, 'ok', 'the promised erasure succeeds' );
        is( $erased_b->{stored}{anonymized}{user_id},
            $b, 'and anonymizes the member' );
        my ( undef, $again_b ) = pair(
            'run_erasure_job',
            job( $approved_a->{stored}{job}{erasure_job_id} ),
            job( $approved_b->{stored}{job}{erasure_job_id} ), $pair
        );
        is( $again_b->{stored}{idempotent}, 1, 'a second run replays it' );
        is_deeply( member_rows($b), member_rows($a),
            'both members end erased alike' );
        is( member_rows($b)->{live_sessions}, 0, 'with every session revoked' );
    };

    subtest 'a legal hold, an approval and an erasure it blocks, released' =>
      sub {
        my ( $a, $b ) = members(2);
        my $ids = { $b => $a };
        my ( $request_a, $request_b ) = @{
            same_effect( 'request_deletion', { reason => 'leaving' },
                $a, $b, $ids )
        };
        my $pair = {
            $request_b->{stored}{deletion_request_id} =>
              $request_a->{stored}{deletion_request_id},
            %{$ids}
        };
        my @requests =
          map { $_->{stored}{deletion_request_id} } ( $request_a, $request_b );
        my ( $approved_a, $approved_b ) = pair(
            'approve_deletion',
            review( $requests[0] ),
            review( $requests[1] ), $pair
        );
        $pair->{ $approved_b->{stored}{job}{erasure_job_id} } =
          $approved_a->{stored}{job}{erasure_job_id};
        my @jobs = map { $_->{stored}{job}{erasure_job_id} }
          ( $approved_a, $approved_b );

        my ( $held_a, $held_b ) = pair(
            'hold_deletion',
            review( $requests[0] ),
            review( $requests[1] ), $pair
        );
        is( $held_b->{status}, 'ok', 'the promised hold succeeds' );
        my @holds = map { hold_of($_) } ( $a, $b );
        ok( $holds[1], 'and places a retention hold' );
        $pair->{ $holds[1] } = $holds[0];

        my ( undef, $blocked_b ) =
          pair( 'run_erasure_job', job( $jobs[0] ), job( $jobs[1] ), $pair );
        is( $blocked_b->{status}, 'conflict', 'the hold blocks the erasure' );
        my ( undef, $still_b ) =
          pair( 'run_erasure_job', job( $jobs[0] ), job( $jobs[1] ), $pair );
        is( $still_b->{stored}{idempotent}, 1, 'and blocks it once' );
        my ( undef, $refused_b ) = pair(
            'approve_deletion',
            review( $requests[0] ),
            review( $requests[1] ), $pair
        );
        is( $refused_b->{stored}{idempotent},
            1, 'an approval already made replays under the hold' );

        my ( undef, $released_b ) = pair(
            'release_hold',
            release( $holds[0] ),
            release( $holds[1] ), $pair
        );
        is( $released_b->{status}, 'ok', 'the promised release succeeds' );
        is( $released_b->{stored}{status},
            'approved', 'giving the request back to approved' );
        my ( undef, $gone_b ) = pair(
            'release_hold',
            release( $holds[0] ),
            release( $holds[1] ), $pair
        );
        is( $gone_b->{status}, 'not_found', 'a released hold is not found' );

        my ( undef, $erased_b ) =
          pair( 'run_erasure_job', job( $jobs[0] ), job( $jobs[1] ), $pair );
        is( $erased_b->{status}, 'ok', 'the erasure runs once released' );
        is_deeply( member_rows($b), member_rows($a),
            'both members end the same way' );
      };

    subtest 'refusals answer as the blocking writes do' => sub {
        my ($a) = members(1);
        for my $case (
            [ request_export   => { user_id => $a } ],
            [ request_deletion => { user_id => $a, command_id => uuid() } ],
            [ approve_deletion => review( uuid() ) ],
            [ hold_deletion    => review( uuid() ) ],
            [ release_hold     => release( uuid() ) ],
            [ run_erasure_job  => job( uuid() ) ],
          )
        {
            my ( $method, $input ) = @{$case};
            my $async = $method . '_p';
            is_deeply( await_result( $w->$async( $input, undef ) ),
                $w->$method($input), "$method: the same refusal" );
        }
    };

    return;
}

# The blocking write on the first member, its promise on the second, each
# with its own command id; the answers compared with the second's ids read
# as the first's.
sub same_effect ( $method, $input, $a, $b, $ids ) {
    return [
        pair(
            $method,
            command( %{$input}, user_id => $a ),
            command( %{$input}, user_id => $b ),
            $ids
        )
    ];
}

sub pair ( $method, $blocking_input, $promised_input, $ids ) {
    my $async    = $method . '_p';
    my $blocking = $w->$method($blocking_input);
    my $promised = await_result( $w->$async( $promised_input, undef ) );
    is_deeply(
        plain( $promised, $ids ),
        plain( $blocking, {} ),
        "$method: promise = blocking"
    );
    return ( $blocking, $promised );
}

sub command (%input) {
    return { command_id => uuid(), %input };
}

sub review ($request_id) {
    return command(
        actor_user_id => $owner,
        reason        => 'verified',
        request_id    => $request_id
    );
}

sub job ($job_id) {
    return command( actor_user_id => $owner, job_id => $job_id );
}

sub release ($hold_id) {
    return command(
        actor_user_id => $owner,
        hold_id       => $hold_id,
        reason        => 'cleared'
    );
}

sub uuid { return $c->gp_id->uuid; }

# Members with a session and one post, so an export has something in it
# and an erasure something to revoke.
sub members ($count) {
    my @ids;
    for ( 1 .. $count ) {
        my $name = 'privacy_' . substr uuid() =~ s/-//grmsx, 0, $NAME_DIGITS;
        my ($id) = $dbh->selectrow_array( $MEMBER_SQL, undef, $name,
            "$name\@example.test" );
        $dbh->do( $SESSION_SQL, undef, $id );
        my ($post) = $dbh->selectrow_array( $POST_SQL, undef, $id );
        my ($body) = $dbh->selectrow_array( $BODY_SQL, undef, $post );
        $dbh->do( 'UPDATE posts SET current_body_id = ? WHERE post_id = ?',
            undef, $body, $post );
        push @ids, $id;
    }
    return @ids;
}

sub hold_of ($user_id) {
    my ($hold) = $dbh->selectrow_array( <<'SQL', undef, $user_id );
SELECT retention_hold_id FROM retention_holds
WHERE resource_type = 'user' AND resource_id = ? AND ends_at IS NULL
SQL
    return $hold;
}

# What the writes left behind for a member, with nothing drawn in it.
sub member_rows ($user_id) {
    my $one = sub ( $sql, @binds ) {
        return [
            map {
                join q{|},
                  map { $_ // q{} }
                  @{$_}
            } @{ $dbh->selectall_arrayref( $sql, undef, @binds ) }
        ];
    };
    return {
        user => $one->(
q{SELECT status, display_name, deleted_at IS NOT NULL FROM users WHERE id = ?},
            $user_id
        ),
        live_sessions => scalar $dbh->selectrow_array(
q{SELECT count(*) FROM sessions WHERE user_id = ? AND revoked_at IS NULL},
            undef,
            $user_id
        ),
        exports => $one->(
q{SELECT status, manifest -> 'counts' FROM export_requests WHERE subject_user_id = ? ORDER BY created_at},
            $user_id
        ),
        requests => $one->(
q{SELECT status, completed_at IS NOT NULL FROM deletion_requests WHERE resource_id = ? ORDER BY created_at},
            $user_id
        ),
        jobs => $one->(
q{SELECT j.status, j.last_error FROM erasure_jobs j JOIN deletion_requests r USING (deletion_request_id) WHERE r.resource_id = ?},
            $user_id
        ),
        actions => $one->(
q{SELECT a.action_type FROM deletion_actions a JOIN deletion_requests r USING (deletion_request_id) WHERE r.resource_id = ? ORDER BY a.created_at, a.action_type},
            $user_id
        ),
        holds => $one->(
q{SELECT reason, ends_at IS NOT NULL FROM retention_holds WHERE resource_id = ?},
            $user_id
        ),
        events => $one->(
q{SELECT event_type, count(*) FROM event_log WHERE aggregate_id = ? GROUP BY event_type ORDER BY event_type},
            $user_id
        ),
        audits => $one->(
q{SELECT action, count(*) FROM audit_log WHERE target_id = ? GROUP BY action ORDER BY action},
            $user_id
        ),
    };
}

# Rows and answers with the second member's ids read as the first's and the
# values each write draws (times, ids, names) left out.
sub plain ( $value, $same ) {
    my $type = ref $value;
    if ( !$type ) {
        return $value if !defined $value;
        my $text = $same->{$value} // $value;
        $text =~ s/$UUID/uuid/gmsx;
        $text =~ s/$COMPACT_ID/id/gmsx;
        $text =~ s/privacy_[[:xdigit:]]{12}/member/gmsx;
        return $text;
    }
    return [ map { plain( $_, $same ) } @{$value} ] if $type eq 'ARRAY';
    return {
        map  { $_ => plain( $value->{$_}, $same ) }
        grep { !/_at\z/msx && !exists $DRAWN{$_} }
          keys %{$value}
      }
      if $type eq 'HASH' || $value->isa('HASH');
    return "$type";
}

1;
