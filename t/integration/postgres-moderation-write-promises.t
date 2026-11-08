# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

# The moderation writes as the web worker runs them. Without a METHOD_p
# call_p ran each blocking write in a forked child that opened a PostgreSQL
# connection of its own, one child at a time per worker. Each promise here
# must answer what its blocking write answers and leave the same rows
# behind, on a target of its own, without reaching a fork fallback.
package main;
use v5.40;
use Const::Fast;
use Digest::SHA qw(sha256_hex);
use English     qw(-no_match_vars);
use Test::More;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Command::AdminBootstrap;
use GPForum::Infrastructure::AsyncWork;
use GPForum::Service::Moderation::ThreadTransfers;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;
use GPForum::Test::Promise qw(await_result);
use GPForum::Test::Forks   qw(children_during);

our $VERSION = '0.001';
const my $LINK_LIMIT   => 3;
const my $FIRST_POSTS  => 2;
const my $TRANSFERABLE => 3;
const my $HEX          => qr/[[:xdigit:]]/msx;
const my $UUID => qr/$HEX {8} - $HEX {4} - $HEX {4} - $HEX {4} - $HEX {12}/msx;

# The keys each write draws for itself or names its own target by. Times
# (valid_from, valid_to and every *_at) are the clock's, which may tick to the
# next second between the two writes.
const my %DRAWN => map { $_ => 1 } qw(command_id moderation_action_id
  suspension_id word_id phrase note_id transfer_id new_thread_id thread_id
  target_id post_id report_id review_id link_limit first_posts
  review_first_posts valid_from valid_to);

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all =>
      'set GPFORUM_TEST_DSN to compare moderation write promises';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
my $dbh   = $database->dbh;
my $owner = seed_id( user => 1 );
GPForum::Test::PostgresHarness::quietly(
    sub {
        return GPForum::Command::AdminBootstrap->new(
            schema => $database->schema )->run( 'grant', '--user-id', $owner );
    }
);
my $t = Test::Mojo->new('GPForum');
my $c = $t->app->build_controller;

# Every child a write starts, recorded instead of trusted. The CPU lane
# (cpu_p, a child that cannot reach PostgreSQL) is counted apart and is no
# fallback: an approval composes its post there.
my $children = children_during( \&writes );
is_deeply( $children->{other}, [], 'no write reached a fork fallback' );

done_testing;

sub writes {
    subtest 'post and thread actions' => sub {
        my $workflow = $c->gp_moderation_workflow;
        my ( $post_a, $post_b ) = posts(2);
        my ( $hidden_a, $hidden_b );
        for my $method (qw(hide_post hide_post restore_post)) {
            my ( $answer, $pair ) =
              same_effect( $workflow, $method,
                sub ($post) { return [ action_input( post_id => $post ) ] },
                $post_a, $post_b, $method );
            $hidden_a //= $pair->[0];
            $hidden_b //= $pair->[1];
        }
        is_deeply( post_state($post_b), post_state($post_a),
            'both posts end in the same state' );

        my ( $thread_a, $thread_b ) = threads(2);
        for my $method (
            qw(lock_thread unlock_thread pin_thread unpin_thread hide_thread
            restore_thread)
          )
        {
            same_effect(
                $workflow,
                $method,
                sub ($thread) {
                    return [ action_input( thread_id => $thread ) ];
                },
                $thread_a,
                $thread_b,
                $method
            );
        }
        is_deeply( thread_state($thread_b), thread_state($thread_a),
            'both threads end in the same state' );
        is( action_count($thread_b), action_count($thread_a),
            'both threads record the same actions' );

        my $input = action_input( post_id => $post_b );
        my $first = await_result( $workflow->hide_post_p( $input, undef ) );
        is_deeply( await_result( $workflow->hide_post_p( $input, undef ) ),
            $first, 'a repeated command id replays its answer' );
        is_deeply(
            await_result(
                $workflow->hide_post_p(
                    { %{ action_input( post_id => $post_b ) }, reason => q{} },
                    undef
                )
            ),
            $workflow->hide_post(
                { %{ action_input( post_id => $post_a ) }, reason => q{} }
            ),
            'a missing reason is refused alike'
        );

        my ( $action_a, $action_b ) =
          map { $_->{stored}{action}{moderation_action_id} }
          ( $hidden_a, $hidden_b );
        same_effect(
            $workflow,
            'reverse_action',
            sub ($action) {
                return [ action_input( action_id => $action ) ];
            },
            $action_a,
            $action_b,
            'reverse_action'
        );
        same_effect(
            $workflow,
            'reverse_action',
            sub ($action) {
                return [ action_input( action_id => $action ) ];
            },
            $action_a,
            $action_b,
            'reverse_action again'
        );
    };

    subtest 'reports' => sub {
        my $workflow = $c->gp_moderation_workflow;
        my ( $report_a, $report_b ) = reports(2);
        for my $call (
            [ assign_report  => {} ],
            [ assign_report  => {} ],
            [ release_report => {} ],
            [ release_report => {} ],
            [ resolve_report => { resolution => 'handled' } ],
            [ resolve_report => { resolution => 'handled' } ],
            [ resolve_report => {} ],
          )
        {
            my ( $method, $extra ) = @{$call};
            same_effect(
                $workflow,
                $method,
                sub ($report) {
                    return [
                        {
                            actor_user_id => $owner,
                            command_id    => $c->gp_id->uuid,
                            report_id     => $report,
                            %{$extra},
                        }
                    ];
                },
                $report_a,
                $report_b,
                $method
            );
        }
        is_deeply( report_state($report_b), report_state($report_a),
            'both reports end in the same state' );
    };

    subtest 'suspensions' => sub {
        my $workflow = $c->gp_moderation_workflow;
        my ( $member_a, $member_b ) =
          ( member('mwp-sus-a'), member('mwp-sus-b') );
        my ( $answer, $ids ) = same_effect(
            $workflow,
            'suspend_user',
            sub ($user) {
                return [
                    {
                        actor_user_id => $owner,
                        command_id    => $c->gp_id->uuid,
                        reason        => 'spam',
                        user_id       => $user,
                    }
                ];
            },
            $member_a,
            $member_b,
            'suspend_user'
        );
        is( user_status($member_b), 'suspended', 'the member is suspended' );
        same_effect(
            $workflow,
            'suspend_user',
            sub ($user) {
                return [
                    {
                        actor_user_id => $owner,
                        command_id    => $c->gp_id->uuid,
                        reason        => 'again',
                        user_id       => $user,
                    }
                ];
            },
            $member_a,
            $member_b,
            'a suspended member keeps the suspension'
        );
        my ( $suspension_a, $suspension_b ) =
          map { $_->{stored}{suspension}{suspension_id} } @{$ids};
        for my $round ( 1, 2 ) {
            same_effect(
                $workflow,
                'revoke_suspension',
                sub ($suspension) {
                    return [
                        {
                            actor_user_id => $owner,
                            command_id    => $c->gp_id->uuid,
                            reason        => 'appeal',
                            suspension_id => $suspension,
                        }
                    ];
                },
                $suspension_a,
                $suspension_b,
                "revoke_suspension $round"
            );
        }
        is( user_status($member_b), user_status($member_a),
            'both members are active again' );
        is( user_status($member_b), 'active', 'the member is active' );
    };

    subtest 'automod and review rules' => sub {
        my $automod = $c->gp_automod_store;
        my ( $word_a, $word_b ) = qw(mwpalpha mwpbravo);
        my ( $added,  $ids )    = same_effect(
            $automod,
            'add_word',
            sub ($phrase) {
                return [
                    {
                        actor_user_id => $owner,
                        phrase        => $phrase,
                        action        => 'flag',
                    }
                ];
            },
            $word_a,
            $word_b,
            'add_word'
        );
        is( $added->{status}, 'ok', 'the word is added' );
        same_effect(
            $automod,
            'add_word',
            sub ($phrase) {
                return [
                    {
                        actor_user_id => $owner,
                        phrase        => $phrase,
                        action        => 'flag',
                    }
                ];
            },
            $word_a,
            $word_b,
            'add_word again'
        );
        same_effect(
            $automod,
            'add_word',
            sub ($phrase) {
                return [ { actor_user_id => $owner, phrase => $phrase } ];
            },
            $word_a,
            $word_b,
            'add_word without an action'
        );
        my ( $id_a, $id_b ) = map { $_->{word}{word_id} } @{$ids};
        for my $round ( 1, 2 ) {
            same_effect(
                $automod,
                'remove_word',
                sub ($word) {
                    return [ { actor_user_id => $owner, word_id => $word } ];
                },
                $id_a,
                $id_b,
                "remove_word $round"
            );
        }
        same_effect(
            $automod,
            'set_link_rule',
            sub ($limit) {
                return [
                    {
                        actor_user_id    => $owner,
                        link_limit       => $limit,
                        link_trust_below => 1,
                        link_action      => 'hold',
                    }
                ];
            },
            $LINK_LIMIT,
            $LINK_LIMIT + 1,
            'set_link_rule'
        );
        same_effect(
            $automod,
            'set_link_rule',
            sub ($limit) {
                return [ { actor_user_id => $owner, link_limit => $limit } ];
            },
            'x',
            'y',
            'an invalid link rule'
        );

        my $review = $c->gp_review_store;
        same_effect(
            $review,
            'set_rule',
            sub ($first) {
                return [
                    {
                        actor_user_id => $owner,
                        first_posts   => $first,
                        flagged       => 1,
                    }
                ];
            },
            $FIRST_POSTS,
            $FIRST_POSTS + 1,
            'set_rule'
        );
        same_effect(
            $review,
            'set_rule',
            sub ($first) {
                return [ { actor_user_id => $owner, first_posts => $first } ];
            },
            'x',
            'y',
            'an invalid review rule'
        );
    };

    subtest 'review decisions' => sub {
        my $workflow = $c->gp_review_workflow;
        my ( $held_a, $held_b ) = ( held(), held() );
        same_effect(
            $workflow,
            'reject',
            sub ($review) {
                return [
                    {
                        actor_user_id => $owner,
                        review_id     => $review,
                        reason        => 'off topic',
                    }
                ];
            },
            $held_a,
            $held_b,
            'reject'
        );
        same_effect(
            $workflow,
            'reject',
            sub ($review) {
                return [ { actor_user_id => $owner, review_id => $review } ];
            },
            $held_a,
            $held_b,
            'reject again'
        );
        same_effect(
            $workflow,
            'reject',
            sub ($review) {
                return [ { actor_user_id => $owner, review_id => $review } ];
            },
            'not-a-review',
            'not-a-review',
            'reject nothing'
        );
        is_deeply( review_status($held_b), review_status($held_a),
            'both entries end rejected' );

        my $approval = sub ($review) {
            return [ { actor_user_id => $owner, review_id => $review } ];
        };
        my ( $held_c, $held_d ) = ( held(), held() );
        my ( undef,   $approved ) =
          same_effect( $workflow, 'approve', $approval, $held_c, $held_d,
            'approve' );
        my @published = map { $_->{post_id} } @{$approved};
        is( scalar( grep { defined } @published ),
            2, 'each approval publishes its post' );
        is_deeply( [ map { review_status($_) } $held_c, $held_d ],
            [qw(approved approved)], 'both entries end approved' );
        is_deeply(
            [ map { notified( 'review_approved', 'post', $_ ) } @published ],
            [ 1, 1 ],
            'and each author is told once'
        );
        same_effect( $workflow, 'approve', $approval, $held_c, $held_d,
            'approve again' );
        same_effect( $workflow, 'approve', $approval, 'not-a-review',
            'not-a-review', 'approve nothing' );

        my $mentioned = member('mwp_mentioned');
        my ( $held_e, $held_f ) =
          map { held('Held, for @mwp_mentioned to read.') } 1 .. 2;
        my ( undef, $mentioning ) =
          same_effect( $workflow, 'approve', $approval, $held_e, $held_f,
            'approve a post that mentions someone' );
        is_deeply(
            [
                map {
                    [
                        mentions( $_->{post_id} ),
                        notified( 'mention', 'post', $_->{post_id} )
                    ]
                } @{$mentioning}
            ],
            [ [ 1, 1 ], [ 1, 1 ] ],
            'each records its mention and notifies the member once'
        );
        ok( $mentioned, 'the member mentioned exists' );

        # As the web worker awaits it: blocking PostgreSQL access in this
        # process croaks, so nothing here may take the blocking path.
        my $held_g = held('Held, for @mwp_mentioned again.');
        my $native = do {
            local $GPForum::Infrastructure::PgStorage::HTTP_PID = $PROCESS_ID;
            await_result( $workflow->approve_p( $approval->($held_g)->[0] ) );
        };
        is_deeply(
            [
                $native->{status},
                review_status($held_g),
                mentions( $native->{post_id} ),
                notified( 'mention',         'post', $native->{post_id} ),
                notified( 'review_approved', 'post', $native->{post_id} ),
            ],
            [ 'ok', 'approved', 1, 1, 1 ],
            'an approval never blocks the event loop'
        );
    };

    subtest 'member notes' => sub {
        my $notes = $c->gp_member_note_store;
        my ( $member_a, $member_b ) =
          ( member('mwp-note-a'), member('mwp-note-b') );
        my ( $added, $ids ) = same_effect(
            $notes, 'add',
            sub ($subject) {
                return [
                    {
                        subject_user_id => $subject,
                        author_user_id  => $owner,
                        body            => "  Warned in private.\r\n",
                    }
                ];
            },
            $member_a,
            $member_b,
            'add'
        );
        is( $added->{status}, 'ok', 'the note is added' );
        same_effect(
            $notes, 'add',
            sub ($subject) {
                return [
                    {
                        subject_user_id => $subject,
                        author_user_id  => $owner,
                        body            => q{ },
                    }
                ];
            },
            $member_a,
            $member_b,
            'an empty note'
        );
        my %note = (
            $member_a => $ids->[0]{note_id},
            $member_b => $ids->[1]{note_id},
        );
        same_effect(
            $notes, 'edit',
            sub ($subject) {
                return [
                    {
                        subject_user_id => $subject,
                        note_id         => $note{$subject},
                        actor_user_id   => $owner,
                        body            => 'Warned twice.',
                    }
                ];
            },
            $member_a,
            $member_b,
            'edit'
        );
        same_effect( $notes, 'for_member', sub ($subject) { return [$subject] },
            $member_a, $member_b, 'for_member' );
        for my $round ( 1, 2 ) {
            same_effect(
                $notes, 'remove',
                sub ($subject) {
                    return [
                        {
                            subject_user_id => $subject,
                            note_id         => $note{$subject},
                            actor_user_id   => $owner,
                        }
                    ];
                },
                $member_a,
                $member_b,
                "remove $round"
            );
        }
    };

    subtest 'media decisions' => sub {
        my $review   = $c->gp_attachment_content_review;
        my $uploader = member('mwp-media');
        for my $decision (qw(approved rejected)) {
            my ( $file_a, $file_b ) =
              ( attachment($uploader), attachment($uploader) );
            same_effect(
                $review, 'decide',
                sub ($file) {
                    return [
                        {
                            actor_user_id => $owner,
                            attachment_id => $file,
                            decision      => $decision,
                            reason        => 'checked',
                        }
                    ];
                },
                $file_a,
                $file_b,
                $decision
            );
            is_deeply(
                attachment_state($file_b),
                attachment_state($file_a),
                "$decision: both files end alike"
            );
            is( audit_count($file_b), audit_count($file_a),
                "$decision: both decisions are audited" );
        }
        same_effect(
            $review, 'decide',
            sub ($file) {
                return [
                    {
                        actor_user_id => $owner,
                        attachment_id => $file,
                        decision      => 'approved',
                    }
                ];
            },
            $c->gp_id->uuid,
            $c->gp_id->uuid,
            'an unknown file'
        );
    };

    subtest 'reported messages and thread transfers' => sub {
        my $messages = $c->gp_message_store;
        same_effect( $messages, 'read_reported',
            sub ($report) { return [ $report, $owner ] },
            'not-an-id', 'not-an-id', 'a malformed report' );
        same_effect( $messages, 'read_reported',
            sub ($report) { return [ $report, $owner ] },
            $c->gp_id->uuid, $c->gp_id->uuid, 'an unknown report' );
        my $report = message_report();
        my ($read) =
          same_effect( $messages, 'read_reported',
            sub ($id) { return [ $id, $owner ] },
            $report, $report, 'a reported message' );
        is( $read->{status}, 'ok', 'the message is read' );
        is( audit_count( $read->{message}{message_id} ),
            2, 'each reading is audited' );

        my $transfers =
          GPForum::Service::Moderation::ThreadTransfers->new(
            schema => $c->gp_schema );
        my ( $source_a, $source_b ) = threads( 2, $TRANSFERABLE );
        my ( $moved,    $pair )     = same_effect(
            $transfers,
            'change',
            sub ($source) {
                return [
                    {
                        actor        => $owner,
                        command      => $c->gp_id->uuid,
                        source       => $source,
                        operation    => 'split',
                        post_numbers => '2',
                        title        => 'Split off for the test',
                        reason       => 'off topic',
                    }
                ];
            },
            $source_a,
            $source_b,
            'split'
        );
        is( $moved->{status}, 'ok', 'the post is split off' );
        same_effect(
            $transfers,
            'change',
            sub ($source) {
                return [
                    { actor => $owner, command => 'x', source => $source } ];
            },
            $source_a,
            $source_b,
            'a malformed command'
        );
        my %transfer = (
            $source_a => $pair->[0]{transfer_id},
            $source_b => $pair->[1]{transfer_id},
        );
        same_effect(
            $transfers,
            'undo',
            sub ($source) {
                return [
                    {
                        actor       => $owner,
                        command     => $c->gp_id->uuid,
                        transfer_id => $transfer{$source},
                    }
                ];
            },
            $source_a,
            $source_b,
            'undo'
        );
    };
    return;
}

# Calls METHOD for $a and METHOD_p for $b and compares the answers, $b's
# values read as $a's. Answers the promise's answer and both answers.
sub same_effect ( $service, $method, $arguments, $a, $b, $name ) {
    my $async    = $method . '_p';
    my $blocking = $service->$method( @{ $arguments->($a) } );
    my $promised =
      await_result( $service->$async( @{ $arguments->($b) }, undef ) );
    is_deeply(
        plain( $promised, { $b => $a } ),
        plain( $blocking, {} ),
        "$name: promise = blocking"
    );
    return ( $promised, [ $blocking, $promised ] );
}

# Rows are objects of the same classes either way; compare their columns,
# with the second target's ids read as the first's and the values each
# write draws (times, ids) left out.
sub plain ( $value, $same ) {
    my $type = ref $value;
    if ( !$type ) {
        return $value if !defined $value;
        return ( $same->{$value} // $value ) =~ s/$UUID/uuid/grmsx;
    }
    return [ map { plain( $_, $same ) } @{$value} ] if $type eq 'ARRAY';
    return {
        map  { $_ => plain( $value->{$_}, $same ) }
        grep { !_drawn($_) }
          keys %{$value}
      }
      if $type eq 'HASH' || $value->isa('HASH');
    return "$type";
}

sub _drawn ($key) {
    return 1 if $key =~ /_at\z/msx;
    return exists $DRAWN{$key} ? 1 : 0;
}

sub action_input (%target) {
    return {
        actor_user_id => $owner,
        command_id    => $c->gp_id->uuid,
        reason        => 'moderation write promises',
        %target,
    };
}

sub posts ($count) {
    return @{ $dbh->selectcol_arrayref( <<'SQL', undef, $count ) };
SELECT p.post_id FROM posts p JOIN threads t ON t.thread_id = p.thread_id
WHERE p.moderation_state = 'visible' AND p.deleted_at IS NULL
  AND t.moderation_state = 'visible' AND t.deleted_at IS NULL
ORDER BY p.post_id DESC LIMIT ?
SQL
}

# Visible threads with at least $posts posts, least used first.
sub threads ( $count, $posts = 1 ) {
    state %taken;
    my $rows = $dbh->selectcol_arrayref( <<'SQL', undef, $posts );
SELECT t.thread_id FROM threads t
WHERE t.moderation_state = 'visible' AND t.deleted_at IS NULL
  AND t.visibility = 'public' AND t.locked_at IS NULL AND NOT t.pinned
  AND (SELECT count(*) FROM posts p WHERE p.thread_id = t.thread_id
       AND p.deleted_at IS NULL) >= ?
ORDER BY t.thread_id
SQL
    my @free   = grep { !$taken{$_} } @{$rows};
    my @picked = @free[ 0 .. $count - 1 ];
    @taken{@picked} = (1) x @picked;
    return @picked;
}

sub post_state ($post) {
    return $dbh->selectrow_hashref( <<'SQL', undef, $post );
SELECT moderation_state, hidden_at IS NOT NULL AS hidden FROM posts
WHERE post_id = ?
SQL
}

sub thread_state ($thread) {
    return $dbh->selectrow_hashref( <<'SQL', undef, $thread );
SELECT moderation_state, locked_at IS NOT NULL AS locked, pinned
FROM threads WHERE thread_id = ?
SQL
}

sub action_count ($target) {
    return $dbh->selectrow_array(
        'SELECT count(*) FROM moderation_actions WHERE target_id = ?',
        undef, $target );
}

sub audit_count ($target) {
    return $dbh->selectrow_array(
        'SELECT count(*) FROM audit_log WHERE target_id = ?',
        undef, $target );
}

sub reports ($count) {
    my $reporter = member('mwp-reporter');
    my @targets  = posts($count);
    return map {
        scalar $dbh->selectrow_array( <<'SQL', undef, $reporter, $_ )
INSERT INTO reports
  (report_id, reporter_user_id, target_type, target_id, reason, details,
   status, created_at)
VALUES (gen_random_uuid(), ?, 'post', ?, 'spam', '', 'open',
        now() - interval '1 minute')
RETURNING report_id
SQL
    } @targets;
}

sub report_state ($report) {
    return $dbh->selectrow_hashref( <<'SQL', undef, $report );
SELECT status, resolution, assigned_moderator_user_id FROM reports
WHERE report_id = ?
SQL
}

sub user_status ($user) {
    return
      scalar $dbh->selectrow_array( 'SELECT status FROM users WHERE id = ?',
        undef, $user );
}

sub member ($name) {
    my ($id) = $dbh->selectrow_array( <<'SQL', undef, $name, $name, $name );
INSERT INTO users (id, username, display_name, email_normalized, status,
    email_verified_at, password_hash)
VALUES (gen_random_uuid(), ?, ?, ? || '@example.test', 'active', now(),
    'unusable')
RETURNING id
SQL
    return $id;
}

sub held ( $body = 'A reply held for review.' ) {
    state $author = member('mwp-held');
    my ($thread) = threads(1);
    my $held = $c->gp_review_store->hold(
        {
            author_user_id     => $author,
            command_id         => $c->gp_id->uuid,
            command_type       => 'reply.create',
            kind               => 'reply',
            thread_id          => $thread,
            body_source        => $body,
            body_rendered_safe => "<p>$body</p>",
            visibility         => 'public',
            reason             => 'first_posts',
        }
    );
    return $held->{review_id};
}

sub mentions ($post) {
    return scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM mentions WHERE source_type = 'post'}
          . q{ AND source_id = ?},
        undef, $post
    );
}

sub notified ( $type, $source_type, $source_id ) {
    return scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM notifications WHERE notification_type = ?}
          . q{ AND source_type = ? AND source_id = ?},
        undef, $type, $source_type, $source_id
    );
}

sub review_status ($review) {
    return
      scalar $dbh->selectrow_array(
        'SELECT status FROM held_posts WHERE review_id = ?',
        undef, $review );
}

sub attachment ($uploader) {
    my $id = $c->gp_id->uuid;
    $dbh->do( <<'SQL', undef, $id, $uploader, "mwp/$id", sha256_hex($id) );
INSERT INTO attachments
  (attachment_id, owner_user_id, object_key, original_filename, media_type,
   byte_size, checksum, state, scan_status, uploaded_at, scanned_at)
VALUES (?, ?, ?, 'picture.png', 'image/png', 1, ?, 'uploaded', 'clean',
        now(), now())
SQL
    $dbh->do( <<'SQL', undef, $id );
INSERT INTO attachment_content_reviews (attachment_id, source_kind)
VALUES (?, 'original')
SQL
    return $id;
}

sub attachment_state ($file) {
    return $dbh->selectrow_hashref( <<'SQL', undef, $file );
SELECT a.state, r.status, r.reason, r.reviewed_by
FROM attachments a JOIN attachment_content_reviews r USING (attachment_id)
WHERE a.attachment_id = ?
SQL
}

# A report on a direct message between two members of its own.
sub message_report {
    my @pair = sort { $a cmp $b } member('mwp-dm-a'), member('mwp-dm-b');
    my ($conversation) =
      $dbh->selectrow_array( <<'SQL', undef, @pair, $pair[0] );
INSERT INTO direct_conversations
  (conversation_id, first_user_id, second_user_id, started_by_user_id,
   created_at, last_message_at)
VALUES (gen_random_uuid(), ?, ?, ?, now(), now())
RETURNING conversation_id
SQL
    my ($message) =
      $dbh->selectrow_array( <<'SQL', undef, $conversation, $pair[0] );
INSERT INTO direct_messages (message_id, conversation_id, author_user_id,
    body, created_at)
VALUES (gen_random_uuid(), ?, ?, 'A message someone reported.', now())
RETURNING message_id
SQL
    return scalar $dbh->selectrow_array( <<'SQL', undef, $pair[1], $message );
INSERT INTO reports
  (report_id, reporter_user_id, target_type, target_id, reason, details,
   status, created_at)
VALUES (gen_random_uuid(), ?, 'message', ?, 'abuse', '', 'open',
        now() - interval '1 minute')
RETURNING report_id
SQL
}

1;
