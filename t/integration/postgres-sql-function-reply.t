# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use JSON::MaybeXS;
use List::Util   ();
use POSIX        qw(strftime);
use Scalar::Util qw(blessed);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Infrastructure::AuditRecord;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::SqlFunctionCatalogue;
use GPForum::Service::Community::MentionStore;
use GPForum::Service::Forum::CategoryReader;
use GPForum::Service::Forum::PostComposer;
use GPForum::Service::Forum::PostReader;
use GPForum::Service::Forum::PostStore;
use GPForum::Service::Forum::PostingCommand;
use GPForum::Service::Forum::PostingWorkflow;
use GPForum::Service::Forum::Readability;
use GPForum::Service::Forum::ThreadComposer;
use GPForum::Service::Forum::ThreadDetailReader;
use GPForum::Service::Forum::ThreadStore;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Notification::Dispatcher;
use GPForum::Service::Notification::PreferenceStore;
use GPForum::Service::Notification::RecipientPolicy;
use GPForum::Service::Notification::SubscriptionStore;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::FixedClock;
use GPForum::Test::LogLines;
use GPForum::Test::PgDatabase;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use GPForum::Test::SequenceId;
use GPForum::Test::StaleThreads;

our $VERSION = '0.001';

# The side a check is asked about, for the checks that read its lineup.
our $CHECKED;

const my $NOW              => strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime );
const my @PATHS            => qw(function perl);
const my $USERS            => 3;
const my $IDS_PER_SCENARIO => 100;

# api.core_forum_store_reply_v1, which no release calls from Perl, as a
# catalogue entry this test calls it by: its parameters in its order.
const my $STORE_STEP => GPForum::Infrastructure::SqlFunctionCatalogue->new(
    entries => {
        core_forum_store_reply => {
            version    => 1,
            parameters => [
                (
                    map { $_ => 'text' }
                      qw(post_id thread_id author_user_id
                      current_body_id current_revision_id)
                ),
                position => 'bigint',
                ( map { $_ => 'text' } qw(visibility moderation_state) ),
                (
                    map { $_ => 'bigint' }
                      qw(version visibility_version permission_version)
                ),
                (
                    map { $_ => 'text' }
                      qw(hidden_at locked_at deleted_at
                      deleted_by body_id body_post_id body_format body_source
                      body_rendered_safe source_hash revision_id
                      revision_post_id revision_body_id editor_user_id)
                ),
                revision_number => 'integer',
                (
                    map { $_ => 'text' }
                      qw(edit_reason idempotency_key
                      correlation_id event_id outbox_id audit_id recorded_at)
                ),
            ],
        },
    },
);
const my $BODILESS_POST => '018f9e00-0000-7000-8000-000000000001';
const my $TAKEN_EVENT   => '018f9e00-0000-7000-8000-000000000002';
const my $OUTBOX_EVENT  => '018f9e00-0000-7000-8000-000000000003';
const my @POST_COLUMNS => qw(
  post_id thread_id author_user_id current_body_id current_revision_id
  position visibility moderation_state version visibility_version
  permission_version hidden_at locked_at deleted_at deleted_by
);

# What a reply writes, table by table, and the columns PostgreSQL fills
# with now() rather than the code with its clock: those differ between two
# databases and say nothing about the paths.
const my %TABLES => (
    audit_log          => [],
    command_log        => [],
    event_log          => [],
    mentions           => [],
    notification_inbox => [],
    notifications      => [],
    outbox_messages    => [qw(available_at created_at next_attempt_at)],
    post_bodies        => [qw(created_at)],
    post_revisions     => [qw(created_at)],
    posts              => [qw(created_at updated_at)],
    thread_counters    => [qw(last_activity_at)],
    threads            => [qw(updated_at)],
);
const my $UUID =>
  qr/[[:xdigit:]]{8} - (?:[[:xdigit:]]{4} -){3} [[:xdigit:]]{12}/msx;

# The ids a reply draws, in the order both paths draw them when nothing
# collides: the command row's id and correlation id, the composer's post,
# body and revision ids, the store's correlation, event, outbox and audit
# ids. A lineup puts an id already held in some of those places, and the
# sequence's own in the others, so both sides draw the same.
const my %DRAWN => (
    audit   => 9,
    body    => 4,
    command => 1,
    event   => 7,
    outbox  => 8,
    post    => 3,
);

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to compare the reply paths';
}

# ADR 0126, section 10: a reply through api.forum_create_reply_v1 (and
# api.forum_store_reply_v1) against the Perl path it replaces, on two copies
# of the same seeded database, given the same ids and the same clock: the
# same answer, the same log line, and the same rows in every table a reply
# writes -- the post, its body and revision, the reply count, the event and
# its outbox row, the audit row and its chain, the command log's request,
# response and hashes, the mentions and their notifications -- for every
# path the workflow and the store can take: a reply, its replay, a conflict,
# each refusal before and under the lock, an invalid reply, a post an
# earlier run left whole or half written, a taken position, a missing
# counter, an event and an outbox row already there, a failure in the store
# and one in the command log. Where a collision makes either path draw a
# new id, the rows are compared with the ids drawn masked, and each side's
# references and audit chain are checked whole.
my %thread = (
    deleted => seed_id( thread => 4 ),
    locked  => seed_id( thread => 5 ),
    members => seed_id( thread => 8 ),
    open    => seed_id( thread => 1 ),
    other   => seed_id( thread => 2 ),
);
my %user   = map { $_ => seed_id( user => $_ ) } 1 .. $USERS;
my $member = GPForum::Service::Forum::Viewer->new(
    member  => 1,
    user_id => $user{2},
);

with_replaced_subs(
    'GPForum::Infrastructure::AuditRecord',
    { now_iso8601 => sub { return $NOW; } },
    sub {
        _the_same_replies();
        _the_same_after_a_collision();
    }
);

done_testing();

# Every deterministic path, one after another on one pair of databases:
# after each, the answer and every table are the same on both, and the
# path taken is the one the scenario names.
sub _the_same_replies {
    my %pair = _pair();

    _same(
        \%pair, 'a reply',
        _input( 'c-01', 'A plain reply.' ),
        check => sub ( $result, $dbh ) { return $result->{ok} },
    );
    _same(
        \%pair, 'its replay',
        _input( 'c-01', 'A plain reply.' ),
        check => sub ( $result, $dbh ) { return $result->{idempotent} },
    );
    _same(
        \%pair,
        'the key used for another request',
        _input( 'c-01', 'Another body.' ),
        check => sub ( $result, $dbh ) {
            return $result->{status} eq 'conflict';
        },
    );
    _with_both( \%pair, \&_command_in_progress );
    _same(
        \%pair,
        'a command still in progress',
        _input( 'c-19', 'Still running.' ),
        check => sub ( $result, $dbh ) {
            return $result->{error} eq
              GPForum::Service::Operations::CommandIdempotency->refusal_error(
                'in_progress');
        },
    );
    _same(
        \%pair,
        'a thread that is not there',
        _input(
            'c-02',
            'Nobody reads this.',
            thread_id => '018f1004-ffff-7000-8000-00000000ffff'
        ),
        check => \&_not_found,
    );
    _same(
        \%pair,
        'a thread id that is no id',
        _input( 'c-03', 'Nor this.', thread_id => 'not-a-uuid' ),
        check => \&_not_found,
    );
    _same(
        \%pair,
        'a locked thread, before the lock',
        _input( 'c-04', 'Too late.', thread_id => $thread{locked} ),
        check => \&_locked,
    );
    _same(
        \%pair,
        'an empty body',
        _input( 'c-05', "  \n " ),
        check => sub ( $result, $dbh ) {
            return $result->{prepared}{errors}{body_source};
        },
    );
    _same(
        \%pair,
        'a visibility broader than its thread',
        _input(
            'c-06', 'Out loud.',
            thread_id  => $thread{members},
            visibility => 'public'
        ),
        check => sub ( $result, $dbh ) {
            return $result->{prepared}{errors}{visibility};
        },
    );
    _same(
        \%pair,
        'the thread\'s own visibility, inherited',
        _input( 'c-07', 'Members only.', thread_id => $thread{members} ),
        check => sub ( $result, $dbh ) {
            return $result->{stored}{post}{visibility} eq 'members';
        },
    );
    _same(
        \%pair,
        'a thread id in capitals',
        _input( 'c-08', 'Shouting the id.', thread_id => uc $thread{open} ),
        check => sub ( $result, $dbh ) {
            return _one( $dbh,
                    q{SELECT payload -> 'response' ->> 'thread_id'}
                  . q{ FROM command_log WHERE idempotency_key = 'c-08'} ) eq
              uc $thread{open};
        },
    );
    _same(
        \%pair,
        'mentions, recorded in the reply\'s transaction',
        _input( 'c-09', 'Hello @perf_user_3 and @perf_user_1, and @nobody.' ),
        check => sub ( $result, $dbh ) {
            return _one( $dbh, 'SELECT count(*) FROM mentions' ) == 2;
        },
    );

    _with_both( \%pair, \&_lock_open_thread );
    _same(
        \%pair,
        'a thread locked after the check, under the lock',
        _input( 'c-10', 'Racing a moderator.' ),
        stale => 1,
        check => \&_locked,
    );
    _with_both( \%pair, \&_unlock_open_thread );
    _same(
        \%pair,
        'a thread deleted after the check, under the lock',
        _input( 'c-11', 'Racing a delete.', thread_id => $thread{deleted} ),
        stale => 1,
        check => \&_not_found,
    );

    _same(
        \%pair,
        'a post an earlier run stored whole',
        _input( 'c-12', 'Retried.' ),
        lineup => \&_whole_post,
        check  => sub ( $result, $dbh ) { return $result->{stored}{skipped} },
    );
    _same(
        \%pair,
        'a post an earlier run stored without its body',
        _input( 'c-13', 'Finished now.' ),
        lineup => \&_bodiless_post,
        check  => sub ( $result, $dbh ) {
            return _one(
                $dbh,
'SELECT current_body_id IS NOT NULL FROM posts WHERE post_id = ?',
                $BODILESS_POST
            );
        },
    );
    _with_both(
        \%pair,
        sub ($dbh) {
            $dbh->do( 'DELETE FROM thread_counters WHERE thread_id = ?',
                undef, $thread{open} );
        }
    );
    _same(
        \%pair,
        'a thread without its counter row',
        _input( 'c-14', 'Counted from nothing.' ),
        check => sub ( $result, $dbh ) {
            return _one( $dbh,
                'SELECT reply_count FROM thread_counters WHERE thread_id = ?',
                $thread{open} ) == 1;
        },
    );
    _same(
        \%pair,
        'an event id already in the log',
        _input( 'c-15', 'An event drawn twice.' ),
        lineup => \&_event_taken,
        check  => sub ( $result, $dbh ) {
            return _one(
                $dbh,
                q{SELECT count(*) = 1 FROM event_log WHERE event_id = ?}
                  . q{ AND idempotency_key = 'earlier'},
                $TAKEN_EVENT
              )
              && _one( $dbh,
                'SELECT count(*) FROM outbox_messages WHERE event_id = ?',
                $TAKEN_EVENT ) == 1;
        },
    );
    _same(
        \%pair,
        'a store that fails',
        _input(
            'c-17', 'From nobody.',
            author_user_id => '018f1002-ffff-7000-8000-00000000ffff'
        ),
        check => sub ( $result, $dbh ) {
            return $result->{error} eq 'post store failed'
              && !_one( $dbh,
                    q{SELECT count(*) FROM command_log}
                  . q{ WHERE idempotency_key = 'c-17'} );
        },
    );
    _same(
        \%pair,
        'a command log that fails',
        _input( 'c-18', 'From no id.', author_user_id => 'not-a-uuid' ),
        check => sub ( $result, $dbh ) {
            return $result->{error} eq 'command log failed';
        },
    );
    _same_store( \%pair, 'a taken position, allocated again', 2 );

    return;
}

sub _not_found ( $result, $dbh ) {
    return $result->{status} eq 'not_found'
      && $result->{error} eq 'thread not found';
}

sub _locked ( $result, $dbh ) {
    return $result->{status} eq 'forbidden'
      && $result->{error} eq 'thread is locked';
}

# The paths where a collision makes the store or the log draw a new id: the
# Perl path draws it from its id service, the function from
# api.core_uuid_v7_v1, so every id the reply drew is masked, and each side's
# rows must hold together.
sub _the_same_after_a_collision {
    my %taken = (
        'a post id another thread\'s post holds' => sub ($side) {
            return _taken(
                $side,
                post => 'SELECT post_id FROM posts WHERE thread_id = ? LIMIT 1',
                $thread{other}
            );
        },
        'a body id another post\'s body holds' => sub ($side) {
            return _taken( $side,
                body => 'SELECT body_id FROM post_bodies LIMIT 1' );
        },
        'a command id another command holds'              => \&_command_taken,
        'an audit id already in the log at the same time' => \&_audit_taken,
        'an outbox id another row holds'                  => \&_outbox_id_taken,

        # Not a collision: the Perl path draws no outbox id when the row is
        # there, the function drew one with the others, so the audit id
        # that follows is another.
        'an outbox row already there' => \&_outbox_taken,
    );
    for my $label ( sort keys %taken ) {
        my %pair = _pair();
        _same(
            \%pair, $label,
            _input( 'c-20', "Colliding: $label." ),
            check  => \&_drew_another,
            lineup => $taken{$label},
            masked => 1,
        );
    }

    return;
}

# The id a lineup placed is still its first row's, once, and the reply's
# row of that kind holds another -- or, for an outbox row already there,
# the reply's event is the one placed and its outbox row is that row.
sub _drew_another ( $result, $dbh ) {
    my ( $kind, $placed ) = %{ $CHECKED->{placed} };
    my $post = _one(
        $dbh,
        q{SELECT post_id FROM posts WHERE thread_id = ?}
          . q{ ORDER BY position DESC LIMIT 1},
        $thread{open}
    );
    my %reply = (
        audit =>
          [ 'SELECT audit_id FROM audit_log WHERE target_id = ?', $post ],
        body =>
          [ 'SELECT current_body_id FROM posts WHERE post_id = ?', $post ],
        command => [
            q{SELECT command_id FROM command_log WHERE idempotency_key = 'c-20'}
        ],
        event =>
          [ 'SELECT event_id FROM event_log WHERE aggregate_id = ?', $post ],
        outbox => [
            q{SELECT o.outbox_id FROM outbox_messages o JOIN event_log e}
              . q{ ON e.event_id = o.event_id WHERE e.aggregate_id = ?},
            $post
        ],
        post => [
            q{SELECT post_id FROM posts WHERE thread_id = ?}
              . q{ AND author_user_id = ? ORDER BY position DESC LIMIT 1},
            $thread{open},
            $user{2}
        ],
    );
    my $held = _one( $dbh, @{ $reply{$kind} } );
    return
         $result->{ok}
      && $held eq $placed
      && _one( $dbh,
        'SELECT count(*) FROM outbox_messages WHERE event_id = ?', $placed ) ==
      1
      if $kind eq 'event';

    return $result->{ok} && defined $held && $held ne $placed;
}

# Two copies of the seeded database, one per path, each with its own ids
# drawn from the same sequence.
sub _pair {
    my %pair;
    for my $path (@PATHS) {
        my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
        $pair{$path} = {
            database => $database,
            dbh      => $database->dbh,
            ids      => GPForum::Test::SequenceId->new,
            log      => [],
            schema   => $database->schema,
        };
    }
    _with_both( \%pair, \&_fixture );

    return %pair;
}

sub _with_both ( $pair, $code ) {
    for my $path (@PATHS) {
        $code->( $pair->{$path}{dbh} );
    }

    return;
}

# The reply on both paths, then the answer, the log and every table.
# Each comparison starts both sides' ids at the same place. The function
# path draws its ids before its one call, the Perl path as it writes: a
# replay or a conflict draws ids on the first that it never uses, which
# writes nothing either way, as the tables show.
my $scenario = 0;

sub _same ( $pair, $label, $input, %option ) {
    my %answer;
    $scenario++;
    for my $path (@PATHS) {
        my $side = $pair->{$path};
        $side->{ids}->drawn( $scenario * $IDS_PER_SCENARIO );
        if ( $option{lineup} ) {
            $side->{ids}->next_ids( $option{lineup}->($side) );
        }
        if ( $option{masked} ) {
            $side->{known} = _uuids( _tables( $side->{dbh} ),
                [ map { ref $_ ? () : $_ } values %{$input} ] );
        }
        my $workflow = _workflow( $path, $side, $option{stale} );
        @{ $side->{log} } = ();
        my $result = _plain( $workflow->create_reply( { %{$input} } ) );
        $answer{$path} = {
            log    => [ map { s/:.*//msxr } @{ $side->{log} } ],
            result => $result,
        };
    }

    if ( $option{check} ) {
        for my $path (@PATHS) {
            $CHECKED = $pair->{$path};
            ok(
                $option{check}->( $answer{$path}{result}, $pair->{$path}{dbh} ),
                "$label: the $path path took that path"
            );
        }
    }

    my %tables = map { $_ => _tables( $pair->{$_}{dbh} ) } @PATHS;
    if ( $option{masked} ) {
        for my $path (@PATHS) {
            _holds_together( $pair->{$path}, "$label ($path)" );
        }
        %answer = map { $_ => _masked( $answer{$_}, $pair->{$_} ) } @PATHS;
        %tables =
          map { $_ => _masked_tables( $tables{$_}, $pair->{$_} ) } @PATHS;
    }
    is_deeply( $answer{function}, $answer{perl}, "$label: the same answer" )
      or diag explain \%answer;
    for my $table ( sort keys %TABLES ) {
        is_deeply(
            $tables{function}{$table},
            $tables{perl}{$table},
            "$label: the same $table"
          )
          or diag explain {
            map { $_ => $tables{$_}{$table} } @PATHS
          };
    }

    return;
}

# The store's step alone, which the workflow's call runs and only a command
# that names a position can reach without a race: PostStore::create_post
# against api.core_forum_store_reply_v1, called here as the command calls
# it. A command naming a position a post holds is allocated the next one.
sub _same_store ( $pair, $label, $position ) {
    my %answer;
    $scenario++;
    for my $path (@PATHS) {
        my $side = $pair->{$path};
        $side->{ids}->drawn( $scenario * $IDS_PER_SCENARIO );
        my $composed = GPForum::Service::Forum::PostComposer->new(
            id_service => $side->{ids} )->prepare(
            {
                author_user_id  => $user{2},
                body_hash       => 'hash of a positioned reply',
                body_source     => 'A positioned reply.',
                idempotency_key => 'store-1',
                position        => $position,
                thread_id       => $thread{open},
            }
            );
        my $store = _post_store( $path, $side );
        $answer{$path} = _plain(
              $path eq 'perl'
            ? $store->create_post( $composed->{command} )
            : $store->reply_answer(
                GPForum::Infrastructure::SqlFunction->new(
                    catalogue => $STORE_STEP,
                    schema    => $side->{schema},
                )->row(
                    'core_forum_store_reply',
                    $store->reply_parameters( $composed->{command} )
                )
            )
        );
    }
    is_deeply( $answer{function}, $answer{perl}, "$label: the same answer" )
      or diag explain \%answer;
    my %tables = map { $_ => _tables( $pair->{$_}{dbh} ) } @PATHS;
    for my $table ( sort keys %TABLES ) {
        is_deeply(
            $tables{function}{$table},
            $tables{perl}{$table},
            "$label: the same $table"
        );
    }

    return;
}

sub _input ( $command_id, $body, %field ) {
    return {
        author_user_id => $user{2},
        body_source    => $body,
        command_id     => $command_id,
        thread_id      => $thread{open},
        viewer         => $member,
        visibility     => q{},
        %field,
    };
}

# The workflow as Bootstrap::Forum builds it, on one side's schema, ids and
# clock; the Perl path's with every function layer taken away. A stale
# reader is the workflow's check made before a moderator's lock or an
# author's delete committed: it reads the thread as it was.
sub _workflow ( $path, $side, $stale ) {
    my %perl   = $path eq 'perl' ? ( functions => undef ) : ();
    my $schema = $side->{schema};
    my $clock  = GPForum::Test::FixedClock->new( iso8601 => $NOW );
    my $ids    = $side->{ids};
    my $posts =
      GPForum::Service::Forum::PostReader->new( schema => $schema, %perl );
    my $threads = GPForum::Service::Forum::ThreadDetailReader->new(
        post_reader => $posts,
        schema      => $schema,
        %perl,
    );
    if ($stale) {
        $threads = GPForum::Test::StaleThreads->new(
            rows => {
                map { $_ => _unlocked( $threads->find_thread_row($_) ) }
                  values %thread
            }
        );
    }

    return GPForum::Service::Forum::PostingWorkflow->new(
        category_reader =>
          GPForum::Service::Forum::CategoryReader->new( schema => $schema ),
        command_idempotency =>
          GPForum::Service::Operations::CommandIdempotency->new(
            clock      => $clock,
            id_service => $ids,
            schema     => $schema,
          ),
        logger        => GPForum::Test::LogLines->new( lines => $side->{log} ),
        mention_store => _mention_store( $schema, $clock, $ids ),
        post_composer =>
          GPForum::Service::Forum::PostComposer->new( id_service => $ids ),
        post_reader     => $posts,
        post_store      => _post_store( $path, $side ),
        thread_composer =>
          GPForum::Service::Forum::ThreadComposer->new( id_service => $ids ),
        thread_detail_reader => $threads,
        thread_store         => GPForum::Service::Forum::ThreadStore->new(
            clock      => $clock,
            id_service => $ids,
            schema     => $schema,
        ),
        %perl,
    );
}

sub _post_store ( $path, $side ) {
    return GPForum::Service::Forum::PostStore->new(
        clock      => GPForum::Test::FixedClock->new( iso8601 => $NOW ),
        id_service => $side->{ids},
        schema     => $side->{schema},
    );
}

sub _mention_store ( $schema, $clock, $ids ) {
    my $policy =
      GPForum::Service::Notification::RecipientPolicy->new( schema => $schema );

    return GPForum::Service::Community::MentionStore->new(
        clock                   => $clock,
        id_service              => $ids,
        notification_dispatcher =>
          GPForum::Service::Notification::Dispatcher->new(
            clock             => $clock,
            id_service        => $ids,
            permission_engine => $policy,
            preference_store  =>
              GPForum::Service::Notification::PreferenceStore->new(
                clock  => $clock,
                schema => $schema,
              ),
            readability        => $policy,
            schema             => $schema,
            subscription_store =>
              GPForum::Service::Notification::SubscriptionStore->new(
                clock      => $clock,
                id_service => $ids,
                schema     => $schema,
              ),
          ),
        readability =>
          GPForum::Service::Forum::Readability->new( schema => $schema ),
        schema => $schema,
    );
}

# The thread row as a check before the lock read it: not locked, not
# deleted.
sub _unlocked ($row) {
    return undef if !$row;

    my %columns = $row->get_columns;
    @columns{qw(deleted_at locked_at)} = ( undef, undef );
    $columns{moderation_state} = 'visible';

    return \%columns;
}

# A deterministic answer: rows as their columns, the store's post as the
# columns a reply command names.
sub _plain ($value) {
    if ( blessed $value && $value->can('get_column') ) {
        return { map { $_ => $value->get_column($_) } @POST_COLUMNS };
    }
    if ( ref $value eq 'HASH' ) {
        return { map { $_ => _plain( $value->{$_} ) } keys %{$value} };
    }
    if ( ref $value eq 'ARRAY' ) {
        return [ map { _plain($_) } @{$value} ];
    }

    return $value;
}

# Every table a reply writes, each row as JSON with the columns now() fills
# left out, sorted.
sub _tables ($dbh) {
    my $json = JSON::MaybeXS->new( canonical => 1, utf8 => 0 );
    my %tables;
    for my $table ( sort keys %TABLES ) {
        my @rows;
        for my $text (
            @{
                $dbh->selectcol_arrayref(
                    "SELECT to_jsonb(t)::text FROM $table t")
            }
          )
        {
            my $row = $json->decode($text);
            delete @{$row}{ @{ $TABLES{$table} } };
            push @rows, $json->encode($row);
        }
        $tables{$table} = [ sort @rows ];
    }

    return \%tables;
}

# The uuids a database holds and a request names before a reply: the ones
# the reply did not draw.
sub _uuids (@values) {
    my $text = JSON::MaybeXS->new( canonical => 1 )->encode( \@values );
    my %seen = map { $_ => 1 } $text =~ /($UUID)/gmsx;

    return \%seen;
}

# What a reply drew, and the hashes over it, as placeholders: every uuid
# the database and the request did not hold before is "drawn", every
# SHA-256 "hash". The rows hold together on each side, which is checked
# apart; here the rest of each row is compared.
sub _masked ( $value, $side ) {
    my $json = JSON::MaybeXS->new( canonical => 1, utf8 => 0 );

    return $json->decode( _masked_text( $json->encode($value), $side ) );
}

sub _masked_tables ( $tables, $side ) {
    return {
        map {
            $_ => [ sort map { _masked_text( $_, $side ) } @{ $tables->{$_} } ]
        } keys %{$tables}
    };
}

sub _masked_text ( $text, $side ) {
    my $known = $side->{known} // {};
    $text =~ s{($UUID)}{ $known->{$1} ? $1 : 'drawn' }gemsx;
    $text =~ s{\b [[:xdigit:]]{64} \b}{hash}gmsx;

    return $text;
}

# One side's rows of the reply hold together whatever ids it drew: the post
# points at its body and revision, which point at it; the event names the
# post and the revision, the outbox row the event; the command log answers
# with the post; the audit row names the post, and the chain verifies.
sub _holds_together ( $side, $label ) {
    my $dbh  = $side->{dbh};
    my $post = $dbh->selectrow_hashref(
        'SELECT p.*, b.post_id AS body_post, r.post_id AS revision_post,'
          . ' r.body_id AS revision_body FROM posts p'
          . ' JOIN post_bodies b ON b.body_id = p.current_body_id'
          . ' JOIN post_revisions r ON r.revision_id = p.current_revision_id'
          . ' WHERE p.thread_id = ? ORDER BY p.position DESC LIMIT 1',
        undef, $thread{open}
    );
    ok( $post, "$label: the post points at its body and revision" ) or return;
    is_deeply(
        [ @{$post}{qw(body_post revision_post revision_body)} ],
        [ @{$post}{qw(post_id post_id current_body_id)} ],
        "$label: which point at it"
    );
    my $event = $dbh->selectrow_hashref(
        q{SELECT e.*, o.event_id AS outbox_event FROM event_log e}
          . q{ JOIN outbox_messages o ON o.event_id = e.event_id}
          . q{ WHERE e.aggregate_id = ?},
        undef, $post->{post_id}
    );
    ok( $event, "$label: the event names the post, its outbox row the event" );
    my $payload = decode_json( $event->{payload} // '{}' );
    is(
        $payload->{revision_id},
        $post->{current_revision_id},
        "$label: and the revision"
    );
    my ($response) = $dbh->selectrow_array(
            q{SELECT payload -> 'response' ->> 'post_id' FROM command_log}
          . q{ WHERE idempotency_key = 'c-20'} );
    is( $response, $post->{post_id}, "$label: the command answers the post" );
    my $audits = $dbh->selectall_arrayref(
        'SELECT * FROM audit_log ORDER BY created_at, audit_id',
        { Slice => {} } );
    my $audit_record = GPForum::Infrastructure::AuditRecord->new(
        json => JSON::MaybeXS->new( canonical => 1, utf8 => 1 ) );
    ok(
        ( grep { ( $_->{target_id} // q{} ) eq $post->{post_id} } @{$audits} ),
        "$label: the audit row names the post"
    );
    my ($tip) =
      grep { ( $_->{target_id} // q{} ) eq $post->{post_id} } @{$audits};
    is(
        $tip->{record_hash},
        $audit_record->record_hash(
            {
                %{ $audit_record->payload_from($tip) },
                created_at     => $NOW,
                metadata       => decode_json( $tip->{metadata} ),
                schema_version => 0 + $tip->{schema_version},
            }
        ),
        "$label: the reply's audit row's hash is its own"
    );

    return;
}

# The posts and logs a lineup collides with, made on each side alike.
sub _fixture ($dbh) {
    $dbh->do(
        q{UPDATE threads SET moderation_state = 'locked', locked_at = ?}
          . q{ WHERE thread_id = ?},
        undef, $NOW, $thread{locked}
    );
    $dbh->do(
        q{UPDATE threads SET deleted_at = ?, deleted_by = author_user_id,}
          . q{ author_user_id = ? WHERE thread_id = ?},
        undef, $NOW, $user{1}, $thread{deleted}
    );
    $dbh->do( q{UPDATE threads SET visibility = 'members' WHERE thread_id = ?},
        undef, $thread{members} );

    return;
}

# A command row of the key and the request with no response yet.
sub _command_in_progress ($dbh) {
    $dbh->do(
        q{INSERT INTO command_log (command_id, command_type, correlation_id,}
          . q{ idempotency_key, payload, status, created_at)}
          . q{ VALUES (?, 'reply.create', ?, 'c-19', ?, 'accepted', ?)},
        undef,
        ('018f9e00-0000-7000-8000-000000000008') x 2,
        JSON::MaybeXS->new( canonical => 1 )->encode(
            {
                request_hash =>
                  GPForum::Service::Operations::CommandIdempotency
                  ->request_hash(
                    GPForum::Service::Forum::PostingCommand->new->request(
                        'reply.create', _input( 'c-19', 'Still running.' )
                    )
                  )
            }
        ),
        $NOW
    );

    return;
}

sub _lock_open_thread ($dbh) {
    $dbh->do(
        q{UPDATE threads SET moderation_state = 'locked', locked_at = ?}
          . q{ WHERE thread_id = ?},
        undef, $NOW, $thread{open}
    );

    return;
}

sub _unlock_open_thread ($dbh) {
    $dbh->do(
        q{UPDATE threads SET moderation_state = 'visible', locked_at = NULL}
          . q{ WHERE thread_id = ?},
        undef, $thread{open}
    );

    return;
}

sub _lineup ( $side, %at ) {
    $side->{placed} = {%at};
    my %place = map { $DRAWN{$_} => $at{$_} } keys %at;
    my $count = List::Util::max( keys %place );

    return [ map { $place{$_} // $side->{ids}->uuid } 1 .. $count ];
}

sub _one ( $dbh, $sql, @bind ) {
    my ($value) = $dbh->selectrow_array( $sql, undef, @bind );

    return $value;
}

# A post of the open thread with its body: an earlier run of the command
# that stored it whole.
sub _whole_post ($side) {
    my ( $post, $body ) = $side->{dbh}->selectrow_array(
        'SELECT post_id, current_body_id FROM posts WHERE thread_id = ?'
          . ' ORDER BY position DESC LIMIT 1',
        undef, $thread{open}
    );

    return _lineup( $side, post => $post, body => $body );
}

# A post of the open thread with no body yet: an earlier run that stopped
# after the post.
sub _bodiless_post ($side) {
    my $post = $BODILESS_POST;
    $side->{dbh}->do(
        q{INSERT INTO posts (post_id, thread_id, author_user_id, position)}
          . q{ SELECT ?, ?, ?, max(position) + 1 FROM posts WHERE thread_id = ?},
        undef, $post, $thread{open}, $user{2}, $thread{open}
    );

    return _lineup( $side, post => $post );
}

# An event of the drawn id already in the log, at another month: found in
# every partition, reused, and its outbox row written from the stored row.
sub _event_taken ($side) {
    my $event = $TAKEN_EVENT;
    $side->{dbh}->do(
        q{INSERT INTO event_log (event_id, event_type, schema_version,}
          . q{ aggregate_type, aggregate_id, aggregate_version, actor_id,}
          . q{ correlation_id, idempotency_key, payload, metadata, created_at)}
          . q{ VALUES (?, 'post.created', 1, 'post', ?, 1, ?, ?, 'earlier',}
          . q{ '{"post_id":"earlier"}', '{"timestamp":"earlier"}',}
          . q{ date_trunc('month', now()) + interval '1 month')},
        undef, $event, $event, $user{2}, $event
    );

    return _lineup( $side, event => $event );
}

# The outbox row of the drawn event already there: nothing to write.
sub _outbox_taken ($side) {
    my $event = $OUTBOX_EVENT;
    $side->{dbh}->do(
        q{INSERT INTO outbox_messages (outbox_id, event_id, queue, job_type,}
          . q{ idempotency_key, payload) VALUES (?, ?, 'events',}
          . q{ 'domain_event.dispatch', ?, '{}')},
        undef,
        '018f9e00-0000-7000-8000-000000000004',
        $event,
        "outbox:post.created:$event"
    );

    return _lineup( $side, event => $event );
}

sub _taken ( $side, $kind, $sql, @bind ) {
    return _lineup( $side, $kind => _one( $side->{dbh}, $sql, @bind ) );
}

# Another command's row holding the drawn command id.
sub _command_taken ($side) {
    my $command = '018f9e00-0000-7000-8000-000000000005';
    $side->{dbh}->do(
        q{INSERT INTO command_log (command_id, command_type, correlation_id,}
          . q{ idempotency_key, payload, status, created_at)}
          . q{ VALUES (?, 'reply.create', ?, 'another', '{}', 'accepted', ?)},
        undef, $command, $command, $NOW
    );

    return _lineup( $side, command => $command );
}

# An audit row of the drawn id at the same time, in the same partition:
# PostgreSQL names the partition's index, which is the log's key.
sub _audit_taken ($side) {
    my $audit = '018f9e00-0000-7000-8000-000000000006';
    $side->{dbh}->do(
        q{INSERT INTO audit_log (audit_id, action, schema_version,}
          . q{ correlation_id, record_hash, created_at)}
          . q{ VALUES (?, 'earlier', 1, ?, 'earlier', ?)},
        undef, $audit, $audit, $NOW
    );

    return _lineup( $side, audit => $audit );
}

# Another outbox row holding the drawn outbox id.
sub _outbox_id_taken ($side) {
    my $outbox = '018f9e00-0000-7000-8000-000000000007';
    $side->{dbh}->do(
        q{INSERT INTO outbox_messages (outbox_id, event_id, queue, job_type,}
          . q{ idempotency_key, payload) VALUES (?, ?, 'events',}
          . q{ 'domain_event.dispatch', 'another', '{}')},
        undef, $outbox, $outbox
    );

    return _lineup( $side, outbox => $outbox );
}

1;
