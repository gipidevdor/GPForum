# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Mojo::JSON qw(decode_json);
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::AdminBootstrap;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Moderation::MemberNoteStore;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';

const my $HTTP_OK        => 200;
const my $HTTP_CREATED   => 201;
const my $HTTP_FOUND     => 302;
const my $HTTP_INVALID   => 400;
const my $HTTP_FORBIDDEN => 403;
const my $HTTP_MISSING   => 404;
const my $HTTP_CONFLICT  => 409;
const my $TOO_LONG       => 2001;
const my $SHOWN          => 3;
const my $FOUR           => 4;
const my $WORD           => 'quokkanote';
const my $JSON           => { Accept => 'application/json' };
const my $NOW            => '2026-10-17T10:00:00Z';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the staff notes on members';
}

# ADR 0138 on a migrated, seeded PostgreSQL: staff holding member_note
# write, edit and delete notes about a member, read them on the member's
# admin page and beside the reports about the member, every change audited
# without its text; nobody else reads them, the member's erasure deletes
# them and the export leaves them out.
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $schema    = $database->schema;
my $dbh       = $database->dbh;
my $ids       = GPForum::Infrastructure::Id->new;
my $functions = GPForum::Infrastructure::SqlFunction->new( schema => $schema );
my $store     = GPForum::Service::Moderation::MemberNoteStore->new(
    schema    => $schema,
    functions => $functions
);
my $admin     = _user( 'notes_admin',     1 );
my $member    = _user( 'notes_member',    0 );
my $reader    = _user( 'notes_reader',    0 );
my $suspended = _user( 'notes_suspended', 1 );
_grant_queue($reader);
$dbh->do(
    q{INSERT INTO suspensions (suspension_id, user_id, actor_user_id, reason)}
      . q{ VALUES (gen_random_uuid(), ?, ?, 'notes test')},
    undef, $suspended, $admin
);
my ( $post_id, $author ) =
  $dbh->selectrow_array( q{SELECT p.post_id, p.author_user_id FROM posts p}
      . q{ JOIN users u ON u.id = p.author_user_id}
      . q{ WHERE p.deleted_at IS NULL AND u.status = 'active'}
      . q{ ORDER BY p.post_id LIMIT 1} );
my $profile_report = _report( 'user', $member );
my $post_report    = _report( 'post', $post_id );

my $first;
subtest 'the store adds, replays and refuses' => sub {
    my $command = $ids->uuid;
    my $added   = $store->add(
        {
            subject_user_id => $member,
            author_user_id  => $admin,
            body            => "  Warned about $WORD links.\r\nSecond line.  ",
            command_id      => $command,
        }
    );
    is_deeply(
        $added,
        { status => 'ok', note_id => $command },
        'a note is added under the form\'s command id'
    );
    $first = $command;

    # The clock reads whole seconds: the notes added next are later.
    $dbh->do(
        q{UPDATE member_notes SET created_at = created_at - interval '1 hour'}
          . q{ WHERE note_id = ?},
        undef, $first
    );
    is(
        _note($first)->{body},
        "Warned about $WORD links.\nSecond line.",
        'trimmed, with its line endings made one'
    );
    is(
        $store->add(
            {
                subject_user_id => $member,
                author_user_id  => $admin,
                body            => 'again',
                command_id      => $command,
            }
        )->{status},
        'replayed',
        'the same submission again adds nothing'
    );
    is(
        $store->add(
            {
                subject_user_id => $reader,
                author_user_id  => $admin,
                body            => 'elsewhere',
                command_id      => $command,
            }
        )->{status},
        'conflict',
        'an id another note holds is a conflict'
    );
    is_deeply(
        $store->add(
            {
                subject_user_id => $member,
                author_user_id  => $admin,
                body            => " \n ",
            }
        ),
        { status => 'invalid', field => 'body' },
        'an empty note is refused'
    );
    is(
        $store->add(
            {
                subject_user_id => $member,
                author_user_id  => $admin,
                body            => 'x' x $TOO_LONG,
            }
        )->{status},
        'invalid',
        'and one longer than 2000 characters'
    );
    is(
        $functions->row(
            'moderation_member_note_add',
            {
                note_id         => $ids->uuid,
                subject_user_id => $member,
                author_user_id  => $admin,
                body            => 'x' x $TOO_LONG,
                now             => $NOW,
                audit           => {},
            }
        )->{status},
        'invalid',
        'the function refuses it as well'
    );
    is(
        $store->add(
            {
                subject_user_id => $ids->uuid,
                author_user_id  => $admin,
                body            => 'nobody',
            }
        )->{status},
        'not_found',
        'a member who does not exist has no notes'
    );
    is( _audits('member_note.added'), 1, 'the addition is audited once' );
    unlike( _audit_text('member_note.added'),
        qr/$WORD/msx, 'and the audit does not hold the text' );
};

subtest 'the store edits and lists' => sub {
    is(
        $store->edit(
            {
                subject_user_id => $member,
                note_id         => $first,
                actor_user_id   => $suspended,
                body            => "Warned about $WORD links twice.",
            }
        )->{status},
        'ok',
        'a note is edited'
    );
    my $note = _note($first);
    is( $note->{updated_by_user_id}, $suspended, 'by whom is recorded' );
    is( $note->{author_user_id},     $admin,     'and the author stays' );
    is(
        $store->edit(
            {
                subject_user_id => $member,
                note_id         => $first,
                actor_user_id   => $admin,
                body            => "Warned about $WORD links twice.",
            }
        )->{status},
        'unchanged',
        'the same text again changes nothing'
    );
    is(
        $store->edit(
            {
                subject_user_id => $reader,
                note_id         => $first,
                actor_user_id   => $admin,
                body            => 'moved',
            }
        )->{status},
        'not_found',
        'a note is edited only under its own member'
    );
    is( _audits('member_note.edited'), 1, 'one edit is audited' );
    for my $count ( 1 .. $SHOWN ) {
        $store->add(
            {
                subject_user_id => $member,
                author_user_id  => $admin,
                body            => "Later note $count",
            }
        );
    }
    my $rows = $store->for_member($member);
    is( scalar @{$rows},              $FOUR,         'every note is listed' );
    is( $rows->[0]{note_total},       $FOUR,         'with the total' );
    is( $rows->[-1]{note_id},         $first,        'newest first' );
    is( $rows->[-1]{author_username}, 'notes_admin', 'with its author' );
    is( $rows->[-1]{updated_by_username},
        'notes_suspended', 'and its last editor' );
    my $reports = $store->for_reports( [ $profile_report, $post_report ] );
    is( $reports->{$profile_report}{subject_user_id},
        $member, 'a profile report is about its member' );
    is( scalar @{ $reports->{$profile_report}{notes} },
        $SHOWN, 'with the newest three notes' );
    is( $reports->{$profile_report}{note_total}, $FOUR, 'and the total' );
    is( $reports->{$post_report}{subject_user_id},
        $author, 'a post report is about its author' );
    is_deeply( $reports->{$post_report}{notes}, [], 'who has no notes yet' );
};

subtest 'staff read the notes on the admin page and beside reports' => sub {
    my $test = _session($admin);
    $test->get_ok("/admin/users/$member/roles")->status_is($HTTP_OK);
    $test->content_like( qr/$WORD/msx, 'the admin page shows the notes' );
    $test->element_exists( qq{form[action="/moderation/members/$member/notes"]},
        'with the form that adds one' );
    $test->element_exists(
qq{form[action="/moderation/members/$member/notes/$first/delete"] input[name=confirm]},
        'and a confirmed delete'
    );
    $test->get_ok( "/admin/users/$member/roles" => $JSON )->status_is($HTTP_OK);
    $test->json_is( '/member_notes/note_total' => $FOUR );
    $test->get_ok('/moderation/reports')->status_is($HTTP_OK);
    $test->content_like( qr/Later[ ]note[ ]3/msx,
        'the newest notes stand beside the report' );
    $test->content_unlike( qr/$WORD/msx, 'three of them' );
    $test->content_like( qr/notes_member/msx, 'naming the member' );
    $test->element_exists( qq{a[href="/admin/users/$member/roles"]},
        'with a link to all of them' );
    $test->get_ok( '/moderation/reports' => $JSON )->status_is($HTTP_OK);
    $test->json_is( "/member_notes/$profile_report/note_total" => $FOUR );

    my $queue = _session($reader);
    $queue->get_ok('/moderation/reports')->status_is($HTTP_OK);
    $queue->content_unlike( qr/$WORD/msx,
        'staff without member_note.view do not read them' );
    $queue->get_ok( '/moderation/reports' => $JSON )
      ->json_is( '/member_notes' => {} );
};

subtest 'the member and everyone else never read them' => sub {
    my $test = _session($member);
    $test->get_ok("/admin/users/$member/roles")->status_is($HTTP_FORBIDDEN);
    $test->get_ok('/moderation/reports')->status_is($HTTP_FORBIDDEN);
    for my $path ( '/u/notes_member', '/settings', '/privacy', '/feed.atom' ) {
        $test->get_ok($path)->content_unlike( qr/$WORD/msx, "not on $path" );
    }
    my $anonymous = Test::Mojo->new('GPForum');
    $anonymous->get_ok( '/u/notes_member' => $JSON )
      ->content_unlike( qr/$WORD/msx, 'nor in the profile\'s JSON' );
    $test->get_ok( "/search?q=$WORD" => $JSON )
      ->status_is($HTTP_OK)
      ->json_is( '/results' => [], 'search finds nothing' );
    for my $table (qw(search_documents outbox_messages event_log notifications))
    {
        is( _containing($table), 0,
            "nothing in $table: no search, feed or realtime carries it" );
    }
    my $document =
      $functions->row( 'portability_export_parts', { user_id => $member } )
      ->{document};
    unlike( Mojo::JSON::encode_json($document),
        qr/$WORD/msx, 'the export leaves the notes out' );
};

subtest 'writes need the permission, CSRF, and an active account' => sub {
    my $test = _session($admin);
    $test->post_ok( "/moderation/members/$member/notes" => form =>
          { body => "No token $WORD" } )->status_is($HTTP_FORBIDDEN);
    my $csrf = _csrf($test);

    my $command = $ids->uuid;
    $test->post_ok(
        "/moderation/members/$member/notes" => form => {
            csrf_token => $csrf,
            command_id => $command,
            body       => 'From the page',
            return_to  => '/moderation/reports',
        }
    )->status_is($HTTP_FOUND)->header_is( Location => '/moderation/reports' );
    is( _note($command)->{body}, 'From the page', 'the form adds a note' );
    $test->post_ok(
        "/moderation/members/$member/notes" => form => {
            csrf_token => $csrf,
            command_id => $command,
            body       => 'From the page',
        }
      )
      ->status_is($HTTP_FOUND)
      ->header_is( Location => "/admin/users/$member/roles" );
    is( _count($member), 1 + $FOUR, 'sent twice, it is added once' );
    $test->post_ok( "/moderation/members/$member/notes" => $JSON => form =>
          { csrf_token => $csrf, body => 'As JSON' } )
      ->status_is($HTTP_CREATED)
      ->json_is( '/status' => 'added' );
    $test->post_ok( "/moderation/members/$member/notes" => $JSON => form =>
          { csrf_token => $csrf, body => q{ } } )->status_is($HTTP_INVALID);
    $test->post_ok(
        "/moderation/members/$member/notes/$command" => $JSON => form =>
          { csrf_token => $csrf, body => 'Edited from the page' } )
      ->status_is($HTTP_OK)
      ->json_is( '/status' => 'edited' );
    $test->post_ok( "/moderation/members/$member/notes/not-a-uuid" => form =>
          { csrf_token => $csrf, body => 'x' } )->status_is($HTTP_MISSING);
    $test->post_ok( '/moderation/members/not-a-uuid/notes' => form =>
          { csrf_token => $csrf, body => 'x' } )->status_is($HTTP_MISSING);
    $test->post_ok( "/moderation/members/$reader/notes/$command" => form =>
          { csrf_token => $csrf, body => 'x' } )->status_is($HTTP_MISSING);
    $test->post_ok(
        "/moderation/members/$member/notes" => $JSON => form => {
            csrf_token => $csrf,
            command_id => $command,
            body       => 'x',
        }
    )->status_is( $HTTP_OK, 'a replay answers what it added' );

    for my $user ( $member, $reader ) {
        my $other = _session($user);
        $other->post_ok( "/moderation/members/$member/notes" => form =>
              { csrf_token => _csrf($other), body => 'not staff' } )
          ->status_is( $HTTP_FORBIDDEN, 'no member_note.write, no note' );
    }
    my $away = _session($suspended);
    $away->post_ok( "/moderation/members/$member/notes" => form =>
          { csrf_token => _csrf($away), body => 'suspended' } )
      ->status_is( $HTTP_FORBIDDEN, 'a suspended staff member writes none' );

    $test->post_ok(
        "/moderation/members/$member/notes/$command/delete" => form =>
          { csrf_token => $csrf, confirm => 1 } )->status_is($HTTP_FOUND);
    ok( !_note($command), 'the delete removes the note' );
    $test->post_ok(
        "/moderation/members/$member/notes/$command/delete" => form =>
          { csrf_token => $csrf, confirm => 1 } )
      ->status_is( $HTTP_MISSING, 'a note deleted is gone' );
    is( _audits('member_note.deleted'), 1, 'the delete is audited' );
    is( _audits('member_note.edited'),  2, 'and so is every edit' );
    is( _containing('audit_log'), 0, 'no audit row holds a note\'s text' );
};

subtest 'erasure deletes the notes about the member, not by them' => sub {
    my $about_admin = $store->add(
        {
            subject_user_id => $admin,
            author_user_id  => $member,
            body            => 'A note the member wrote',
        }
    )->{note_id};
    my $revoked =
      $functions->row( 'privacy_revoke_user',
        { source => 'MemberNote', user_id => $member, at => $NOW } );
    ok( $revoked->{revoked} >= $FOUR, 'the member\'s notes are revoked' );
    is( _count($member), 0, 'none is left' );
    ok( _note($about_admin), 'a note the member wrote about another stays' );
    $dbh->do( q{UPDATE users SET status = 'deleted' WHERE id = ?},
        undef, $member );
    is(
        $store->add(
            {
                subject_user_id => $member,
                author_user_id  => $admin,
                body            => 'after',
            }
        )->{status},
        'not_found',
        'an erased member takes no new note'
    );
    is_deeply( $store->for_reports( [$profile_report] ),
        {}, 'and a report about them shows none' );
};

done_testing();

sub _note ($note_id) {
    return $dbh->selectrow_hashref(
        q{SELECT * FROM member_notes WHERE note_id = ?},
        undef, $note_id );
}

sub _count ($user_id) {
    return
      scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM member_notes WHERE subject_user_id = ?},
        undef, $user_id );
}

sub _audits ($action) {
    return
      scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM audit_log WHERE action = ?},
        undef, $action );
}

sub _audit_text ($action) {
    my $rows = $dbh->selectcol_arrayref(
        q{SELECT row_to_json(a)::text FROM audit_log a WHERE action = ?},
        undef, $action );

    return join "\n", @{$rows};
}

sub _containing ($table) {
    return
      scalar $dbh->selectrow_array(
        qq{SELECT count(*) FROM $table t WHERE row_to_json(t)::text LIKE ?},
        undef, "%$WORD%" );
}

# An open report on the target, older than any the seed made, so it is
# first in the queue.
sub _report ( $type, $target_id ) {
    my $report_id = $ids->uuid;
    $dbh->do(
        q{INSERT INTO reports (report_id, reporter_user_id, target_type,}
          . q{ target_id, reason, created_at)}
          . q{ VALUES (?, ?, ?, ?, 'abuse', '2001-01-01')},
        undef, $report_id, $reader, $type, $target_id
    );

    return $report_id;
}

# report.view_queue, and nothing of the notes, for a queue reader.
sub _grant_queue ($user_id) {
    my ($permission) = $dbh->selectrow_array(
q{SELECT permission_id FROM permissions WHERE name = 'report.view_queue'}
    );
    my ($role) = $dbh->selectrow_array(
            q{INSERT INTO roles (role_id, name) VALUES (gen_random_uuid(),}
          . q{ 'queue_reader') RETURNING role_id} );
    $dbh->do(
        q{INSERT INTO role_permissions (role_id, permission_id) VALUES (?, ?)},
        undef, $role, $permission
    );
    $dbh->do(
        q{INSERT INTO role_bindings (binding_id, user_id, role_id,}
          . q{ resource_type) VALUES (gen_random_uuid(), ?, ?, 'global')},
        undef, $user_id, $role
    );

    return;
}

sub _csrf ($test) {
    $test->get_ok('/settings');
    my $dom   = $test->tx->res->dom;
    my $input = $dom->at('input[name=csrf_token]');

    return $input ? $input->attr('value') : q{};
}

# A browser signed in as the user.
sub _session ($user_id) {
    my $test   = Test::Mojo->new('GPForum');
    my $routes = $test->app->routes;
    $routes->get('/__test/notes-session')->to(
        cb => sub ($c) {
            $c->session( user_id => $user_id );
            return $c->render( json => { ok => 1 } );
        }
    );
    $test->get_ok('/__test/notes-session')->status_is($HTTP_OK);

    return $test;
}

# A new active member, given the bootstrap administration role when asked.
sub _user ( $name, $administrator ) {
    my ($id) = $dbh->selectrow_array(
        q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{ password_hash, status, email_verified_at) VALUES}
          . q{ (gen_random_uuid(), ?, ?, ?, 'x', 'active', now()) RETURNING id},
        undef, $name, $name, "$name\@example.test"
    );
    if ($administrator) {
        GPForum::Test::PostgresHarness::quietly(
            sub {
                return GPForum::Command::AdminBootstrap->new->run( 'grant',
                    '--user-id', $id );
            }
        );
    }

    return $id;
}

1;
