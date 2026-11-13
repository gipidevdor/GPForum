# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

const my $HANDLE_LENGTH => 43;
const my $PURGE_LIMIT   => 100;

# Migration 2052: mark all read covers what the badge counts, completed
# handler claims leave with the dead letters, and erasure removes the
# sign-in pathways bound to the account.
my $database = GPForum::Test::PgDatabase->fresh;
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $dbh = $database->dbh;
my $functions =
  GPForum::Infrastructure::SqlFunction->new( schema => $database->schema );

my ( $lower_user, $higher_user ) =
  sort map { _user($_) } qw(dm_author dm_reader);
my $reader = $higher_user;

subtest 'mark all read marks the notification of a direct message' => sub {
    my $conversation = _uuid();
    my $message      = _uuid();
    my $notification = _uuid();
    $dbh->do(
        q{INSERT INTO direct_conversations (conversation_id, first_user_id,}
          . q{ second_user_id, started_by_user_id, created_at, last_message_at)}
          . q{ VALUES (?, ?, ?, ?, now(), now())},
        undef, $conversation, $lower_user, $higher_user, $lower_user
    );
    for
      my $pair ( [ $lower_user, $higher_user ], [ $higher_user, $lower_user ] )
    {
        $dbh->do(
            q{INSERT INTO direct_conversation_members (conversation_id,}
              . q{ user_id, other_user_id, last_message_at)}
              . q{ VALUES (?, ?, ?, now())},
            undef, $conversation, @{$pair}
        );
    }
    $dbh->do(
        q{INSERT INTO direct_messages (message_id, conversation_id,}
          . q{ author_user_id, body, created_at)}
          . q{ VALUES (?, ?, ?, 'hello', now())},
        undef, $message, $conversation, $lower_user
    );
    my ($created_at) = $dbh->selectrow_array(
        q{INSERT INTO notifications (notification_id, recipient_user_id,}
          . q{ source_type, source_id, notification_type)}
          . q{ VALUES (?, ?, 'message', ?, 'message') RETURNING created_at},
        undef, $notification, $reader, $message
    );
    $dbh->do(
        q{INSERT INTO notification_inbox (recipient_user_id, notification_id,}
          . q{ created_at) VALUES (?, ?, ?)},
        undef, $reader, $notification, $created_at
    );

    my $marked = _mark_all_read();
    is( $marked->{marked_count}, 1, 'the DM notification is marked' );
    my ($read_at) = $dbh->selectrow_array(
        q{SELECT read_at FROM notification_inbox WHERE notification_id = ?},
        undef, $notification );
    ok( defined $read_at, 'and the inbox row is read' );
    my ($reads) = $dbh->selectrow_array(
        q{SELECT count(*) FROM notification_reads WHERE notification_id = ?},
        undef, $notification );
    is( $reads,                        1, 'and the read is recorded once' );
    is( _mark_all_read()->{duplicate}, 1, 'a second pass marks nothing' );
};

subtest 'completed handler claims leave after the replay window' => sub {
    my %key = (
        old_done  => q{now() - interval '60 days'},
        new_done  => q{now()},
        old_claim => undef,
    );
    for my $name ( sort keys %key ) {
        my $completed = $key{$name} // 'NULL';
        $dbh->do(
            q{INSERT INTO event_idempotency_keys (idempotency_key,}
              . q{ event_id, created_at, completed_at) VALUES (?, ?,}
              . qq{ now() - interval '60 days', $completed)},
            undef, "review:$name", _uuid()
        );
    }
    my $purged = $functions->row(
        'ops_retention_purge',
        {
            source    => 'EventIdempotencyKey',
            cutoff    => '-infinity',
            row_limit => $PURGE_LIMIT,
        }
    );
    is( $purged->{deleted}, 0, 'nothing completed before -infinity' );
    my ($cutoff) =
      $dbh->selectrow_array(q{SELECT (now() - interval '37 days')::text});
    $purged = $functions->row(
        'ops_retention_purge',
        {
            source    => 'EventIdempotencyKey',
            cutoff    => $cutoff,
            row_limit => $PURGE_LIMIT,
        }
    );
    is( $purged->{deleted}, 1, 'the old completed claim goes' );
    is_deeply(
        $dbh->selectcol_arrayref(
                q{SELECT idempotency_key FROM event_idempotency_keys}
              . q{ WHERE idempotency_key LIKE 'review:%' ORDER BY 1}
        ),
        [ 'review:new_done', 'review:old_claim' ],
        'a recent completion and an open claim stay'
    );
};

subtest 'erasing the credentials removes OIDC links and passkeys' => sub {
    my $member     = _user('erased_member');
    my $credential = _uuid();
    $dbh->do(
        q{INSERT INTO credentials (id, user_id, type, secret_hash)}
          . q{ VALUES (?, ?, 'password', 'x')},
        undef, $credential, $member
    );
    $dbh->do(
        q{INSERT INTO oidc_account_links (issuer, subject, user_id,}
          . q{ credential_id) VALUES ('https://id.example.test', 'sub-1', ?, ?)},
        undef, $member, $credential
    );
    $dbh->do(
        q{INSERT INTO passkey_accounts (user_id, rp_id, user_handle)}
          . q{ VALUES (?, 'forum.example.test', ?)},
        undef, $member, 'h' x $HANDLE_LENGTH
    );
    my $kept = _user('kept_member');
    $dbh->do(
        q{INSERT INTO passkey_accounts (user_id, rp_id, user_handle)}
          . q{ VALUES (?, 'forum.example.test', ?)},
        undef, $kept, 'k' x $HANDLE_LENGTH
    );

    $functions->row(
        'privacy_revoke_user',
        {
            source  => 'Credential',
            user_id => $member,
            at      => '2026-11-08T12:00:00Z'
        }
    );
    is( _count( 'oidc_account_links', $member ), 0, 'the OIDC link is gone' );
    is( _count( 'passkey_accounts',   $member ),
        0, 'and the passkey user handle' );
    is( _count( 'passkey_accounts', $kept ), 1, 'another member keeps theirs' );
};

done_testing();

sub _mark_all_read {
    return $functions->row(
        'notification_mark_all_read',
        {
            user_id        => $reader,
            filter_sources => 1,
            member         => 1,
            global_read    => 0,
            viewer_user_id => $reader,
            category_ids   => [],
            space_ids      => [],
            read_at        => '2026-11-08T12:00:00Z',
        }
    )->{result};
}

sub _count ( $table, $user_id ) {
    my ($count) =
      $dbh->selectrow_array( "SELECT count(*) FROM $table WHERE user_id = ?",
        undef, $user_id );
    return $count;
}

sub _uuid {
    my ($id) = $dbh->selectrow_array(q{SELECT gen_random_uuid()});
    return $id;
}

sub _user ($name) {
    my ($id) = $dbh->selectrow_array(
        q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{ password_hash, status, email_verified_at) VALUES}
          . q{ (gen_random_uuid(), ?, ?, ?, 'x', 'active', now())}
          . q{ RETURNING id},
        undef, $name, $name, "$name\@example.test"
    );

    return $id;
}

1;
