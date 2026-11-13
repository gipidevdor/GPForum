# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use Const::Fast;
use lib 'lib';
use lib 't/lib';
use GPForum::Test::PgDatabase;
use GPForum::Service::Forum::Polls;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Id;

our $VERSION = '0.001';
const my $THIRD_CHOICE   => 3;
const my $INVALID_CHOICE => 4;
if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for multiple-choice polls';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh      = $database->dbh;
my $functions =
  GPForum::Infrastructure::SqlFunction->new( schema => $database->schema );
my $polls = GPForum::Service::Forum::Polls->new( schema => $database->schema );
my $ids   = GPForum::Infrastructure::Id->new;
my ( $thread, $author ) = $dbh->selectrow_array(
q{SELECT t.thread_id,t.author_user_id FROM threads t JOIN categories c USING(category_id) JOIN spaces s USING(space_id) JOIN users u ON u.id=t.author_user_id WHERE t.visibility='public' AND c.visibility='public' AND s.visibility='public' AND t.deleted_at IS NULL AND t.locked_at IS NULL AND t.moderation_state='visible' AND u.status='active' ORDER BY t.thread_id LIMIT 1}
);
my ($voter) = $dbh->selectrow_array(
    q{SELECT id FROM users WHERE status='active' AND id<>? ORDER BY id LIMIT 1},
    undef, $author
);

sub change ( $actor, $operation, $values, $command = undef ) {
    return $polls->change(
        {
            actor     => $actor,
            operation => $operation,
            values    => $values,
            command   => $command // $ids->uuid,
            thread_id => $thread
        }
    );
}

sub counts {
    return $dbh->selectcol_arrayref(
q{SELECT votes FROM poll_options WHERE thread_id=? ORDER BY option_number},
        undef, $thread
    );
}
subtest 'creation, bounded sets and idempotent vote changes' => sub {
    is(
        change(
            $author, 'create',
            {
                question        => 'Choose two',
                options         => [ 'One', 'Two', 'Three' ],
                maximum_choices => 2
            }
        )->{status},
        'ok',
        'author creates a multi-choice poll'
    );
    my $command = $ids->uuid;
    is(
        change( $voter, 'vote', { choices => [ 1, $THIRD_CHOICE ] }, $command )
          ->{status},
        'ok',
        'two selections accepted'
    );
    is_deeply( counts(), [ 1, 0, 1 ], 'each selection counted once' );
    is(
        change( $voter, 'vote', { choices => [ 1, $THIRD_CHOICE ] }, $command )
          ->{status},
        'ok',
        'retry returns recorded result'
    );
    is_deeply( counts(), [ 1, 0, 1 ], 'retry does not count twice' );
    is( change( $voter, 'vote', { choices => [2] }, $command )->{status},
        'conflict', 'idempotency key cannot change the selection' );
    for my $invalid (
        [],
        [ 1, 2, $THIRD_CHOICE ],
        [ 1, 1 ],
        [$INVALID_CHOICE], [0], ['x'], undef, '1'
      )
    {
        is( change( $voter, 'vote', { choices => $invalid } )->{status},
            'invalid', 'invalid selection refused' );
    }
    is_deeply( counts(), [ 1, 0, 1 ], 'refusals leave counters unchanged' );
    is(
        change( $voter, 'vote', { choices => [ $THIRD_CHOICE, 2 ] } )->{status},
        'ok',
        'selection set can change'
    );
    is_deeply( counts(), [ 0, 1, 1 ], 'old selections replaced atomically' );
    my $read = $polls->overview( $voter, $thread )->{poll};
    is( $read->{maximum_choices}, 2, 'reader exposes the bound' );
    is_deeply(
        $read->{choices},
        [ 2, $THIRD_CHOICE ],
        'reader returns only this voter selections'
    );
    is_deeply( $polls->overview( undef, $thread )->{poll}{choices},
        [], 'anonymous reader sees no voter identities or ballots' );
};
subtest 'changing back to one choice drops extras and preserves totals' => sub {
    is( change( $voter, 'vote', { choices => [1] } )->{status},
        'ok', 'the current API changes the ballot' );
    is_deeply(
        counts(),
        [ 1, 0, 0 ],
        'a one-choice replacement clears extras and counts one ballot'
    );
    is_deeply( $polls->overview( $voter, $thread )->{poll}{choices},
        [1], 'the reader sees the replacement ballot' );
};
subtest 'account export and erasure include all selections' => sub {
    is( change( $voter, 'vote', { choices => [ 1, 2 ] } )->{status},
        'ok', 'multi-choice ballot restored' );
    my $parts =
      $functions->row( 'portability_export_parts', { user_id => $voter } )
      ->{document};
    my ($ballot) =
      grep { $_->{thread_id} eq $thread } @{ $parts->{poll_ballots} };
    is_deeply(
        $ballot->{choices},
        [ 1, 2 ],
        'account export includes every selection'
    );
    $functions->row(
        'privacy_revoke_user',
        {
            source  => 'PollBallot',
            user_id => $voter,
            at      => '2026-11-01T12:00:00Z'
        }
    );
    is_deeply(
        counts(),
        [ 0, 0, 0 ],
        'erasure decrements first and additional selections'
    );
    is(
        $dbh->selectrow_array(
            q{SELECT count(*) FROM poll_ballot_extra_choices WHERE user_id=?},
            undef, $voter
        ),
        0,
        'extra rows erased'
    );
};
subtest 'closed polls refuse all choices' => sub {
    is( change( $author, 'close', {} )->{status}, 'ok', 'author closes poll' );
    is( change( $voter,  'vote',  { choices => [ 1, 2 ] } )->{status},
        'closed', 'closed poll refuses multi-choice votes' );
    is_deeply( counts(), [ 0, 0, 0 ], 'closure leaves counters stable' );
};
done_testing();

1;
