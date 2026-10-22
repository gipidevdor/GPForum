# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Mojo::JSON qw(decode_json);
use Test::Fatal;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Moderation::MemberNoteStore;
use GPForum::Test::MemberNotesController;
use GPForum::Test::SqlFunctionHandle;
use GPForum::ViewModel::Moderation::Presenter;
use GPForum::Web::MemberNotes;

our $VERSION = '0.001';

# Private staff notes on members (ADR 0138), on a handle that records the
# call and answers what the test gives: the text as stored, the calls and
# their audits (never with the text), the notes beside reports, the block
# the pages render, and who may read and write them.

const my $MEMBER   => '018f1002-0002-7000-8000-000000000002';
const my $STAFF    => '018f1002-0003-7000-8000-000000000003';
const my $NOTE     => '018f1009-0001-7000-8000-000000000001';
const my $REPORT   => '018f100a-0001-7000-8000-000000000001';
const my $OTHER    => '018f100a-0002-7000-8000-000000000002';
const my $MAXIMUM  => 2000;
const my $THREE    => 3;
const my $FOUR     => 4;
const my $TOO_LONG => 2001;

sub fixture ( $rows = [] ) {
    my $handle = GPForum::Test::SqlFunctionHandle->new( rows => $rows );
    my $store  = GPForum::Service::Moderation::MemberNoteStore->new(
        functions =>
          GPForum::Infrastructure::SqlFunction->new( schema => $handle ),
        schema => $handle,
    );
    return ( $handle, $store );
}

subtest 'a note is trimmed text of at most 2000 characters' => sub {
    my ( undef, $store ) = fixture();
    is( $store->maximum_body, $MAXIMUM, 'the bound' );
    is( $store->body(" one\r\ntwo\rthree \n"),
        "one\ntwo\nthree", 'line endings made one, the ends trimmed' );
    is( $store->body(" \n\t "),          undef,          'blank is no note' );
    is( $store->body(undef),             undef,          'nor is nothing' );
    is( $store->body( 'x' x $MAXIMUM ),  'x' x $MAXIMUM, 'at the bound' );
    is( $store->body( 'x' x $TOO_LONG ), undef,          'over it' );
    is(
        $store->body( "\N{LATIN SMALL LETTER E WITH GRAVE}" x $MAXIMUM ),
        "\N{LATIN SMALL LETTER E WITH GRAVE}" x $MAXIMUM,
        'characters are counted, not bytes'
    );
};

subtest 'adding calls the function, audited without the text' => sub {
    my ( $handle, $store ) =
      fixture( [ { status => 'ok', note_id => $NOTE } ] );
    is_deeply(
        $store->add(
            {
                subject_user_id => $MEMBER,
                author_user_id  => $STAFF,
                body            => ' Secret words ',
                command_id      => $NOTE,
            }
        ),
        { status => 'ok', note_id => $NOTE },
        'the function\'s answer'
    );
    like(
        $handle->prepared->[0],
        qr/api[.]moderation_member_note_add_v2/msx,
        'through the add function'
    );
    my @values = @{ $handle->executed->[0] };
    is_deeply(
        [ @values[ 0 .. $THREE ] ],
        [ $NOTE, $MEMBER, $STAFF, 'Secret words' ],
        'the command id is the note id'
    );
    my $audit = decode_json( $values[-1] );
    is( $audit->{action},      'member_note.added', 'audited as an addition' );
    is( $audit->{target_type}, 'member_note',       'of a note' );
    is( $audit->{target_id},   $NOTE,               'naming it' );
    unlike( $values[-1], qr/Secret/msx, 'without its text' );
    is( $audit->{metadata}{subject_user_id}, $MEMBER, 'with its member' );
};

subtest 'a command id that is not a uuid mints the note id' => sub {
    my ( $handle, $store ) =
      fixture( [ { status => 'ok', note_id => $NOTE } ] );
    $store->add(
        {
            subject_user_id => $MEMBER,
            author_user_id  => $STAFF,
            body            => 'x',
            command_id      => 'nope',
        }
    );
    isnt( $handle->executed->[0][0], 'nope', 'a fresh id' );
};

subtest 'refusals are answered before any call' => sub {
    my ( $handle, $store ) = fixture();
    is_deeply(
        $store->add( { subject_user_id => $MEMBER, body => q{ } } ),
        { status => 'invalid', field => 'body' },
        'an empty note'
    );
    is( $store->add( { subject_user_id => 'x', body => 'y' } )->{status},
        'not_found', 'a member id that is no uuid' );
    is(
        $store->edit(
            { subject_user_id => $MEMBER, note_id => 'x', body => 'y' }
        )->{status},
        'not_found',
        'a note id that is no uuid'
    );
    is(
        $store->remove( { subject_user_id => $MEMBER, note_id => 'x' } )
          ->{status},
        'not_found',
        'nor deleted'
    );
    is_deeply( $store->for_member('x'),      [], 'nor listed' );
    is_deeply( $store->for_reports( ['x'] ), {}, 'nor found beside reports' );
    is( scalar @{ $handle->prepared }, 0, 'and nothing was called' );
};

subtest 'edits and deletes are audited by their actor' => sub {
    my ( $handle, $store ) =
      fixture( [ { status => 'ok', note_id => $NOTE } ] );
    $store->edit(
        {
            subject_user_id => $MEMBER,
            note_id         => $NOTE,
            actor_user_id   => $STAFF,
            body            => 'New text',
        }
    );
    $store->remove(
        {
            subject_user_id => $MEMBER,
            note_id         => $NOTE,
            actor_user_id   => $STAFF,
        }
    );
    like(
        $handle->prepared->[0],
        qr/moderation_member_note_edit_v2/msx,
        'the edit function'
    );
    like(
        $handle->prepared->[1],
        qr/moderation_member_note_delete_v2/msx,
        'the delete function'
    );
    my $edit   = decode_json( $handle->executed->[0][-1] );
    my $remove = decode_json( $handle->executed->[1][-1] );
    is_deeply(
        [ map { @{$_}{qw(action actor_id)} } $edit, $remove ],
        [ 'member_note.edited', $STAFF, 'member_note.deleted', $STAFF ],
        'each audited as what it did, by whom'
    );
    is(
        $edit->{metadata}{body_length},
        length 'New text',
        'an edit records the length, not the text'
    );
};

subtest 'notes beside reports are grouped by report' => sub {
    my ( $handle, $store ) = fixture(
        [
            {
                report_id        => $REPORT,
                subject_user_id  => $MEMBER,
                subject_username => 'member',
                note_total       => 2,
                note_id          => $NOTE,
                body             => 'first',
            },
            {
                report_id        => $REPORT,
                subject_user_id  => $MEMBER,
                subject_username => 'member',
                note_total       => 2,
                note_id          => $OTHER,
                body             => 'second',
            },
            {
                report_id        => $OTHER,
                subject_user_id  => $STAFF,
                subject_username => 'staff',
                note_total       => 0,
                note_id          => undef,
            },
        ]
    );
    my $found = $store->for_reports( [ $REPORT, $OTHER ] );
    is_deeply( [ map { $_->{body} } @{ $found->{$REPORT}{notes} } ],
        [qw(first second)], 'the notes of the report\'s member, in order' );
    is( $found->{$REPORT}{note_total}, 2, 'with their total' );
    is_deeply( $found->{$OTHER}{notes}, [], 'a member without notes' );
    is( $handle->executed->[0][1], $store->per_report, 'three per report' );
};

subtest 'without the function layer the store is unavailable' => sub {
    my $store = GPForum::Service::Moderation::MemberNoteStore->new(
        schema    => GPForum::Test::SqlFunctionHandle->new,
        functions => undef,
    );
    like(
        exception { $store->for_member($MEMBER) },
        qr/function[ ]layer/msx,
        'a clear failure'
    );
};

subtest 'the block keeps each note\'s lines and its ids apart' => sub {
    my $presenter = GPForum::ViewModel::Moderation::Presenter->new;
    my $block     = $presenter->member_notes(
        add_command_id  => $NOTE,
        can_write       => 1,
        maximum         => $MAXIMUM,
        notes           => [ { note_id => $NOTE, body => "a\nb" } ],
        scope           => "report-$REPORT",
        subject_user_id => $MEMBER,
    );
    is_deeply( $block->{notes}[0]{body_lines}, [qw(a b)], 'lines' );
    is( $block->{note_total}, 1, 'the total defaults to what is shown' );
    like( $block->{ui}{heading_id},
        qr/\Amember-notes-report-/msx, 'ids scoped to the block' );
    isnt(
        $block->{notes}[0]{ui}{body_id},
        $block->{ui}{add_body_id},
        'and apart from each other'
    );
    is( $presenter->member_notes( can_write => 0 )->{can_write},
        0, 'writing is off unless allowed' );
};

subtest 'reading and writing need their own global binding' => sub {
    my %held = ( view => 1, write => 0 );
    my @asked;
    my $controller = GPForum::Test::MemberNotesController->new(
        answer => sub ($permission) {
            push @asked, $permission;
            return $held{ $permission->{action} };
        },
        rows => [ { note_id => $NOTE, body => 'x', note_total => 1 } ],
    );
    my $notes = GPForum::Web::MemberNotes->new;
    my $block = $notes->for_member( $controller, $STAFF, $MEMBER );
    is( $block->{note_total}, 1, 'a reader with view reads the notes' );
    is( $block->{can_write},  0, 'without write, no forms' );
    is_deeply(
        $asked[0],
        {
            action        => 'view',
            resource_type => 'member_note',
            resource_id   => undef,
            space_id      => undef,
        },
        'the global binding is what counts'
    );
    %held = ( view => 0, write => 1 );
    is( $notes->for_member( $controller, $STAFF, $MEMBER ),
        undef, 'without view, nothing' );
    is_deeply(
        [ $notes->for_reports( $controller, $STAFF, [ {} ] ) ],
        [ {}, 0 ],
        'nor beside reports'
    );
    is( $notes->may( $controller, undef, 'view' ), 0, 'nobody may nothing' );
    is( scalar @asked, $FOUR, 'one check per question' );
};

subtest 'notes that cannot be read do not fail the page' => sub {
    my $controller = GPForum::Test::MemberNotesController->new(
        answer => sub ($permission) { return 1; },
        rows   => 'unreadable',
    );
    my $warned = q{};
    my $log    = $controller->app->log->level('warn');
    $log->unsubscribe('message');
    $log->on(
        message => sub ( $from, $level, @lines ) {
            $warned .= join q{ }, @lines;
            return;
        }
    );
    my $notes = GPForum::Web::MemberNotes->new;
    is_deeply(
        $notes->for_member( $controller, $STAFF, $MEMBER ),
        { unavailable => 1 },
        'the admin page says they are unavailable'
    );
    is_deeply(
        [
            $notes->for_reports(
                $controller, $STAFF, [ { report_id => $REPORT } ]
            )
        ],
        [ {}, 1 ],
        'and so does the queue'
    );
    like(
        $warned,
        qr/member[ ]notes[ ]unavailable/msx,
        'the failure is logged'
    );
};

done_testing();

1;
