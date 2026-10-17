# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Compress::Zlib ();
use Const::Fast;
use File::Temp qw(tempdir);
use Mojo::JSON qw(encode_json);
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::AdminBootstrap;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::ImageTool;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Attachment::FilesystemStorage;
use GPForum::Service::Attachment::MediaProcessor;
use GPForum::Service::Attachment::Store;
use GPForum::Service::Attachment::UploadPipeline;
use GPForum::Service::Community::AvatarStore;
use GPForum::Service::Community::Avatars;
use GPForum::Test::Antivirus;
use GPForum::Test::ImageTool;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';

const my $HTTP_OK           => 200;
const my $HTTP_FOUND        => 302;
const my $HTTP_NOT_MODIFIED => 304;
const my $HTTP_INVALID      => 400;
const my $HTTP_UNAUTHORIZED => 401;
const my $HTTP_FORBIDDEN    => 403;
const my $HTTP_MISSING      => 404;
const my $HTTP_TOO_LARGE    => 413;
const my $HTTP_UNSUPPORTED  => 415;
const my $HTTP_UNPROCESSED  => 422;
const my $HTTP_UNAVAILABLE  => 503;
const my $SIDES             => 3;
const my $TOO_MANY          => 9_000;
const my $JSON              => { Accept => 'application/json' };
const my $NOW               => '2026-10-17T10:00:00Z';
const my $LONG_REASON       => 501;
const my $MEGABYTE          => 1_024 * 1_024;
const my $CHURN_LIMIT       => 10;
const my $HTTP_TOO_MANY     => 429;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for members\' profile pictures';
}

# ADR 0144 on a migrated, seeded PostgreSQL: a member uploads a picture
# through the attachment validation and scan; it is cropped to its squares
# and shown on their profile and beside their posts; they replace and remove
# it; staff holding avatar.moderate remove one, audited; the scan's refusal,
# a slow scan and an unreadable picture are each told; erasure deletes the
# files and the rows, and the export says what is shown.
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $schema    = $database->schema;
my $dbh       = $database->dbh;
my $ids       = GPForum::Infrastructure::Id->new;
my $functions = GPForum::Infrastructure::SqlFunction->new( schema => $schema );
my $storage   = GPForum::Service::Attachment::FilesystemStorage->new(
    root => tempdir( CLEANUP => 1 ) );
my $tool      = GPForum::Test::ImageTool->new;
my $antivirus = GPForum::Test::Antivirus->new;
my $store =
  GPForum::Service::Community::AvatarStore->new( schema => $schema );

my ( $post_id, $thread_id, $member, $username ) = $dbh->selectrow_array(
        q{SELECT p.post_id, p.thread_id, p.author_user_id, u.username}
      . q{ FROM posts p JOIN threads t ON t.thread_id = p.thread_id}
      . q{ JOIN categories c ON c.category_id = t.category_id}
      . q{ JOIN spaces s ON s.space_id = c.space_id}
      . q{ JOIN users u ON u.id = p.author_user_id}
      . q{ WHERE p.position = 1 AND p.deleted_at IS NULL}
      . q{ AND p.moderation_state = 'visible' AND p.visibility = 'public'}
      . q{ AND t.deleted_at IS NULL AND t.moderation_state = 'visible'}
      . q{ AND t.visibility = 'public' AND c.visibility = 'public'}
      . q{ AND s.visibility = 'public' AND u.status = 'active'}
      . q{ AND u.deleted_at IS NULL ORDER BY p.post_id LIMIT 1} );
ok( $post_id, 'the seed has a public first post by an active member' );
my $other     = _user( 'avatar_other',     0 );
my $admin     = _user( 'avatar_admin',     1 );
my $suspended = _user( 'avatar_suspended', 0 );
my $away      = _user( 'avatar_staff_away', 1 );
for my $user ( $suspended, $away ) {
    $dbh->do(
        q{INSERT INTO suspensions (suspension_id, user_id, actor_user_id,}
          . q{ reason) VALUES (gen_random_uuid(), ?, ?, 'avatar test')},
        undef, $user, $admin
    );
}

my $first;
subtest 'a member uploads a picture and it is shown' => sub {
    my $test = _client($member);
    $test->get_ok('/settings/avatar')
      ->status_is($HTTP_OK)
      ->element_exists('form[enctype="multipart/form-data"] input[name=avatar]')
      ->header_is( 'Cache-Control' => 'no-store' );
    my $csrf = _csrf($test);

    $test->post_ok( '/settings/avatar' => form =>
          { avatar => _file( GPForum::Test::ImageTool->png( 300, 200 ) ) } )
      ->status_is( $HTTP_FORBIDDEN, 'no CSRF token, no upload' );
    $test->post_ok(
        '/settings/avatar' => form => {
            csrf_token => $csrf,
            avatar     => _file(
                GPForum::Test::ImageTool->png(
                    300, 200, comment => 'taken at home'
                )
            ),
        }
      )
      ->status_is($HTTP_FOUND)
      ->header_is( Location => '/settings/avatar' );
    my $row = _row($member);
    ok( $row->{attachment_id}, 'the picture is shown at once' );
    is( $row->{pending_attachment_id}, undef, 'and nothing waits' );
    $first = $row->{attachment_id};
    is_deeply(
        $dbh->selectcol_arrayref(
            q{SELECT variant_type FROM attachment_variants}
              . q{ WHERE attachment_id = ? ORDER BY byte_size},
            undef, $first
        ),
        [qw(avatar_64 avatar_128 avatar_256)],
        'kept at three sides, and no thumbnail copy of the original'
    );
    is_deeply(
        $tool->calls->[-1]{sides},
        [ 64, 128, 256 ],
        'the tool was asked for the three squares'
    );
    is( $tool->calls->[-1]{width}, 300, 'with the size read from the header' );
    is(
        scalar $dbh->selectrow_array(
            q{SELECT count(*) FROM attachment_links WHERE attachment_id = ?}
              . q{ AND target_type = 'profile' AND target_id = ?},
            undef, $first, $member
        ),
        1,
        'the upload is an attachment linked to the member\'s profile'
    );

    $test->get_ok("/u/$username")
      ->status_is($HTTP_OK)
      ->element_exists(
        qq{img.avatar--picture[src="/avatars/$member/$first/128"]},
        'the profile shows the picture' )
      ->element_exists(
        qq{img.avatar--picture[srcset="/avatars/$member/$first/256 2x"]} );
    $test->get_ok( "/u/$username" => $JSON )
      ->json_is( '/profile/user/avatar_id' => $first );
    $test->get_ok('/settings/avatar')
      ->element_exists(qq{img[src="/avatars/$member/$first/128"]})
      ->element_exists('form[action="/settings/avatar/remove"]');
};

subtest 'the picture is served to anyone, cached by its address' => sub {
    my $anonymous = _client(undef);
    $anonymous->get_ok("/avatars/$member/$first/64")
      ->status_is($HTTP_OK)
      ->content_type_is('image/png')
      ->header_is( 'Cache-Control'          => 'public, max-age=3600' )
      ->header_is( 'X-Content-Type-Options' => 'nosniff' )
      ->header_is( ETag                     => qq{"$first-64"} );
    my $body = $anonymous->tx->res->body;
    is( $body, GPForum::Test::ImageTool->png( 64, 64 ), 'the 64 pixel square' );
    unlike( $body, qr/taken[ ]at[ ]home/msx,
        'with nothing of the original\'s metadata' );
    $anonymous->get_ok( "/avatars/$member/$first/64" =>
          { 'If-None-Match' => qq{"$first-64"} } )
      ->status_is($HTTP_NOT_MODIFIED);
    $anonymous->get_ok("/avatars/$member/$first/99")
      ->status_is( $HTTP_MISSING, 'only the three sides have an address' );
    $anonymous->get_ok("/avatars/$other/$first/64")
      ->status_is( $HTTP_MISSING, 'a member without a picture has none' );
    $anonymous->get_ok("/avatars/not-a-uuid/$first/64")
      ->status_is($HTTP_MISSING);
    my $older = $ids->uuid;
    $anonymous->get_ok("/avatars/$member/$older/64")
      ->status_is( $HTTP_OK, 'an address of an older picture answers' )
      ->header_is( 'Cache-Control' => 'public, max-age=60',
        'with the picture shown now, briefly' );

    $anonymous->get_ok("/t/$thread_id")
      ->status_is($HTTP_OK)
      ->element_exists(
        qq{#post-$post_id img.post__avatar[src="/avatars/$member/$first/64"]},
        'the thread page shows the author\'s picture beside the post'
      );
    my $initials = $dbh->selectrow_array(
        q{SELECT count(*) FROM posts p WHERE p.thread_id = ?}
          . q{ AND p.author_user_id <> ? AND p.deleted_at IS NULL},
        undef, $thread_id, $member
    );
    if ($initials) {
        $anonymous->element_exists( 'span.avatar.post__avatar',
            'and the initials of authors who show none' );
    }
    $anonymous->get_ok( "/t/$thread_id" => $JSON )->status_is($HTTP_OK);
    like( $anonymous->tx->res->body, qr/\Q$first\E/msx,
        'the page\'s JSON names the picture shown' );
};

my $second;
subtest 'a new picture replaces the old one, whose files go' => sub {
    my @old_keys = _keys($first);
    is( scalar @old_keys, 1 + $SIDES, 'the old picture has four files' );
    ok( $storage->exists_object($_), "$_ is stored" ) for @old_keys;

    my $test = _client($member);
    $test->post_ok( '/settings/avatar' => $JSON => form =>
          { csrf_token => _csrf($test), avatar => _file( _jpeg( 640, 480 ) ) }
    )->status_is($HTTP_OK)->json_is( '/status' => 'shown' );
    $second = _row($member)->{attachment_id};
    isnt( $second, $first, 'a new picture is shown' );
    ok( !$storage->exists_object($_), "$_ is deleted" ) for @old_keys;
    is( _attachment($first)->{state}, 'deleted', 'the old upload is deleted' );
    is( $tool->calls->[-1]{media_type},
        'image/jpeg', 'the type is sniffed, not taken from the client' );
    _client(undef)
      ->get_ok("/avatars/$member/$first/64")
      ->status_is( $HTTP_OK, 'the old address answers with the new one' )
      ->header_is( ETag => qq{"$second-64"} );
};

subtest 'uploads are refused before anything is stored' => sub {
    my $test   = _client($member);
    my $csrf   = _csrf($test);
    my $before = _count('attachments');
    my @cases  = (
        [ 'no file', undef, $HTTP_INVALID, 'missing' ],
        [ 'text', _file( "plain words\n", 'notes.txt', 'text/plain' ),
            $HTTP_UNSUPPORTED, 'not_image' ],
        [ 'a PDF', _file( "%PDF-1.4\n", 'doc.pdf', 'application/pdf' ),
            $HTTP_UNSUPPORTED, 'not_image' ],
        [
            'over 5 MB',
            _file( "\x89PNG\x0d\x0a\x1a\x0a" . ( "\0" x ( 5 * $MEGABYTE ) ) ),
            $HTTP_TOO_LARGE, 'too_large'
        ],
        [ 'a broken header', _file("\x89PNG\x0d\x0a\x1a\x0a broken"),
            $HTTP_UNPROCESSED, 'unreadable' ],
        [ 'too many pixels', _file( _png_header( $TOO_MANY, 10 ) ),
            $HTTP_UNPROCESSED, 'too_many_pixels' ],
    );
    for my $case (@cases) {
        my ( $label, $file, $status, $answer ) = @{$case};
        $test->post_ok( '/settings/avatar' => $JSON => form =>
              { csrf_token => $csrf, ( $file ? ( avatar => $file ) : () ) } )
          ->status_is( $status, "$label is refused" )
          ->json_is( '/status' => $answer );
    }
    $test->post_ok(
        '/settings/avatar' => form => {
            csrf_token => $csrf,
            avatar     => _file( "plain words\n", 'notes.txt', 'text/plain' )
        }
      )
      ->status_is($HTTP_UNSUPPORTED)
      ->text_like( '.ui-alert--error' => qr/PNG,[ ]JPEG,[ ]GIF[ ]or[ ]WebP/msx,
        'the page says why' );
    is( _count('attachments'), $before, 'and nothing was stored' );
    is( _row($member)->{attachment_id}, $second, 'the picture shown stays' );

    $tool->installed(0);
    $test->post_ok( '/settings/avatar' => $JSON => form =>
          { csrf_token => $csrf, avatar => _file( _png( 10, 10 ) ) } )
      ->status_is( $HTTP_UNAVAILABLE, 'no image tool, no picture' )
      ->json_is( '/status' => 'unavailable' );
    $test->get_ok('/settings/avatar')
      ->element_exists_not('input[name=avatar]')
      ->content_like(qr/not[ ]available/msx);
    $tool->installed(1);
};

subtest 'the tool that cannot read a picture, or cannot run' => sub {
    my $test = _client($member);
    my $csrf = _csrf($test);
    $tool->answer('unreadable');
    $test->post_ok( '/settings/avatar' => $JSON => form =>
          { csrf_token => $csrf, avatar => _file( _png( 50, 40 ) ) } )
      ->status_is($HTTP_UNPROCESSED)
      ->json_is( '/status' => 'unreadable' );
    my $row = _row($member);
    is( $row->{attachment_id}, $second, 'the picture shown stays' );
    is( $row->{pending_state}, 'unreadable', 'the member is told' );
    is( _attachment( $row->{pending_attachment_id} )->{state},
        'deleted', 'and the unreadable upload is discarded' );
    $test->get_ok('/settings/avatar')
      ->content_like( qr/could[ ]not[ ]be[ ]read/msx );

    $tool->answer('unavailable');
    $test->post_ok( '/settings/avatar' => $JSON => form =>
          { csrf_token => $csrf, avatar => _file( _png( 50, 40 ) ) } )
      ->status_is($HTTP_OK)
      ->json_is( '/status' => 'checking', 'a tool that cannot run leaves it'
          . ' waiting for the media worker' );
    my $waiting = _row($member)->{pending_attachment_id};
    is( _row($member)->{pending_state}, 'checking', 'waiting' );

    $tool->answer('squares');
    my $answer = _media_processor()->process($waiting);
    is( $answer->{status}, 'shown', 'the media worker shows it later' );
    ok( $answer->{avatar}, 'as a picture, not a thumbnail' );
    is( _row($member)->{attachment_id}, $waiting, 'it is the one shown' );
    is( _attachment($second)->{state}, 'deleted', 'the one before is gone' );
    is( _media_processor()->process($waiting)->{status},
        'shown', 'a redelivered event changes nothing' );
    $second = $waiting;
};

subtest 'a slow scan waits; the scan refuses an infected picture' => sub {
    $antivirus->immediate(0);
    my $test = _client($member);
    my $csrf = _csrf($test);
    $test->post_ok( '/settings/avatar' => $JSON => form =>
          { csrf_token => $csrf, avatar => _file( _png( 80, 80 ) ) } )
      ->status_is($HTTP_OK)
      ->json_is( '/status' => 'checking' );
    my $waiting = _row($member)->{pending_attachment_id};
    is( _attachment($waiting)->{scan_status}, 'pending', 'the scan waits' );
    is( _media_processor()->process($waiting)->{skipped},
        'not_available', 'nothing is cropped before the scan' );
    $test->get_ok('/settings/avatar')
      ->content_like( qr/being[ ]checked/msx, 'the member is told' );

    _attachments()->record_scan(
        {
            actor_id      => 'antivirus',
            attachment_id => $waiting,
            scan_engine   => 'Fake 1/1',
            scan_status   => 'clean',
        }
    );
    is( _media_processor()->process($waiting)->{status},
        'shown', 'a clean scan, and it is shown' );

    $test->post_ok( '/settings/avatar' => $JSON => form =>
          { csrf_token => $csrf, avatar => _file( _png( 90, 90 ) ) } )
      ->json_is( '/status' => 'checking' );
    my $infected = _row($member)->{pending_attachment_id};
    _attachments()->record_scan(
        {
            actor_id       => 'antivirus',
            attachment_id  => $infected,
            reason         => 'malware: Test.Signature',
            scan_engine    => 'Fake 1/1',
            scan_signature => 'Test.Signature',
            scan_status    => 'infected',
        }
    );
    is( $store->status($member)->{pending_state},
        'refused', 'an infected picture is refused' );
    is( _row($member)->{attachment_id}, $waiting, 'never shown' );
    $test->get_ok('/settings/avatar')
      ->content_like( qr/refused[ ]by[ ]the[ ]safety[ ]check/msx );
    $antivirus->immediate(1);

    $antivirus->verdict(
        { status => 'infected', engine => 'Fake 1/1', signature => 'Eicar' } );
    $test->post_ok( '/settings/avatar' => $JSON => form =>
          { csrf_token => $csrf, avatar => _file( _png( 70, 70 ) ) } )
      ->status_is($HTTP_UNPROCESSED)
      ->json_is( '/status' => 'refused', 'a scan at upload refuses at once' );
    $antivirus->verdict( { status => 'clean', engine => 'Fake 1/1' } );
    $second = $waiting;
};

subtest 'uploads need a member, CSRF, and an active account' => sub {
    my $anonymous = _client(undef);
    $anonymous->get_ok('/settings/avatar')->status_is($HTTP_UNAUTHORIZED);
    my $test = _client($suspended);
    $test->post_ok( '/settings/avatar' => form =>
          { csrf_token => _csrf($test), avatar => _file( _png( 10, 10 ) ) } )
      ->status_is( $HTTP_FORBIDDEN, 'a suspended member uploads none' );
    is( _row($suspended), undef, 'and has no picture' );
};

subtest 'uploads and removals are held to ten a minute' => sub {
    my $test = _client($member);
    my $csrf = _csrf($test);
    for ( 1 .. $CHURN_LIMIT ) {
        $test->post_ok( '/settings/avatar' => $JSON => form =>
              { csrf_token => $csrf } )->status_is($HTTP_INVALID);
    }
    $test->post_ok( '/settings/avatar' => $JSON => form =>
          { csrf_token => $csrf } )
      ->status_is( $HTTP_TOO_MANY, 'the eleventh in a minute is refused' );
};

subtest 'staff remove a picture, audited; nobody else does' => sub {
    my $member_view = _client($other);
    $member_view->get_ok("/u/$username")
      ->element_exists_not( 'form[action$="/avatar/remove"]',
        'a member sees no removal form' );
    $member_view->post_ok(
        "/moderation/members/$member/avatar/remove" => form => {
            csrf_token => _csrf($member_view),
            avatar_id  => $second,
        }
    )->status_is( $HTTP_FORBIDDEN, 'and cannot remove one' );
    my $staff_away = _client($away);
    $staff_away->post_ok(
        "/moderation/members/$member/avatar/remove" => form => {
            csrf_token => _csrf($staff_away),
            avatar_id  => $second,
        }
    )->status_is( $HTTP_FORBIDDEN, 'nor can suspended staff' );

    my $staff = _client($admin);
    $staff->get_ok("/u/$username")
      ->element_exists(
qq{form[action="/moderation/members/$member/avatar/remove"] input[name=avatar_id][value="$second"]},
        'staff see the form for the picture shown'
      );
    my $csrf = _csrf($staff);
    $staff->post_ok( "/moderation/members/$member/avatar/remove" => form =>
          { avatar_id => $second } )->status_is( $HTTP_FORBIDDEN, 'CSRF' );
    $staff->post_ok(
        "/moderation/members/$member/avatar/remove" => form => {
            csrf_token => $csrf,
            avatar_id  => $ids->uuid,
        }
    )->status_is( $HTTP_MISSING, 'a picture not shown is not removed' );
    $staff->post_ok(
        "/moderation/members/$member/avatar/remove" => form => {
            csrf_token => $csrf,
            avatar_id  => $second,
            reason     => 'x' x $LONG_REASON,
        }
    )->status_is($HTTP_INVALID);
    my @keys = _keys($second);
    $staff->post_ok(
        "/moderation/members/$member/avatar/remove" => form => {
            csrf_token => $csrf,
            avatar_id  => $second,
            reason     => '  Not a picture of a person.  ',
            return_to  => "/u/$username",
        }
    )->status_is($HTTP_FOUND)->header_is( Location => "/u/$username" );
    is( _row($member)->{attachment_id}, undef, 'the picture is removed' );
    ok( !$storage->exists_object($_), "$_ is deleted" ) for @keys;
    my $audit = $dbh->selectrow_hashref(
        q{SELECT * FROM audit_log WHERE action = 'avatar.removed'});
    ok( $audit, 'the removal is audited' );
    is( $audit->{actor_id}, $admin, 'with who removed it' );
    like( encode_json($audit), qr/Not[ ]a[ ]picture[ ]of[ ]a[ ]person/msx,
        'and the reason given' );
    like( encode_json($audit), qr/\Q$member\E/msx, 'and whose it was' );
    _client(undef)
      ->get_ok("/avatars/$member/$second/64")
      ->status_is( $HTTP_MISSING, 'the address answers no more' );
    $staff->get_ok("/u/$username")
      ->element_exists_not('img.avatar--picture')
      ->element_exists( 'span.avatar.avatar--large',
        'the initial stands in its place' );
    $staff->get_ok( "/u/$username" => $JSON )
      ->json_is( '/profile/user/avatar_id' => undef );
};

subtest 'the member removes their own picture' => sub {
    my $test = _client($member);
    my $csrf = _csrf($test);
    $test->post_ok( '/settings/avatar' => $JSON => form =>
          { csrf_token => $csrf, avatar => _file( _png( 64, 64 ) ) } )
      ->json_is( '/status' => 'shown' );
    my $shown = _row($member)->{attachment_id};
    my @keys  = _keys($shown);
    $test->post_ok('/settings/avatar/remove')
      ->status_is( $HTTP_FORBIDDEN, 'CSRF' );
    $test->post_ok( '/settings/avatar/remove' => form =>
          { csrf_token => $csrf } )
      ->status_is($HTTP_FOUND)
      ->header_is( Location => '/settings/avatar' );
    is( _row($member)->{attachment_id}, undef, 'it is removed' );
    ok( !$storage->exists_object($_), "$_ is deleted" ) for @keys;
    $test->post_ok( '/settings/avatar/remove' => $JSON => form =>
          { csrf_token => $csrf } )
      ->status_is( $HTTP_MISSING, 'there is none to remove' );
    _client(undef)->get_ok("/t/$thread_id")
      ->element_exists_not(
        qq{#post-$post_id img.post__avatar},
        'the post shows the initial again'
      );
};

subtest 'the store refuses what is not the member\'s' => sub {
    my $avatars = _avatars();
    my $answer  = $avatars->upload(
        { user_id => $other, content => _png( 40, 40 ) } );
    is( $answer->{status}, 'shown', 'another member shows one' );
    my $theirs = _row($other)->{attachment_id};
    is( $store->offer( $member, $theirs )->{status},
        'not_found', 'nobody offers another member\'s upload' );
    is( $store->settle( $member, $theirs, 'ready' )->{status},
        'stale', 'nor settles it' );
    is( $store->offer( $member, 'not-a-uuid' )->{status}, 'invalid' );
    is( $store->settle( $other, $theirs, 'ready' )->{status},
        'shown', 'settling the picture shown again changes nothing' );
    is( $store->remove_by_staff(
            {
                subject_user_id => $other,
                attachment_id   => $theirs,
                actor_user_id   => $admin,
                reason          => 'y' x $LONG_REASON,
            }
        )->{status},
        'invalid',
        'a reason over 500 characters is refused'
    );
};

subtest 'the export says what is shown; erasure deletes it all' => sub {
    my $document =
      $functions->row( 'portability_export_parts', { user_id => $other } )
      ->{document};
    is( $document->{avatar}{attachment_id},
        _row($other)->{attachment_id}, 'the export names the picture shown' );
    ok( $document->{avatar}{shown_at}, 'and since when' );
    ok(
        grep( { $_->{attachment_id} eq $document->{avatar}{attachment_id} }
            @{ $document->{attachments} // [] } ),
        'the upload is among the member\'s attachments'
    ) if ref $document->{attachments} eq 'ARRAY';
    is(
        $functions->row( 'portability_export_parts', { user_id => $admin } )
          ->{document}{avatar}{attachment_id},
        undef,
        'a member without one exports none'
    );

    my @keys = map { $_->{object_key} } @{ $store->objects($other) };
    ok( scalar @keys, 'the member has stored files' );
    is( _avatars()->erase_files($other), scalar @keys, 'erasure deletes' );
    ok( !$storage->exists_object($_), "$_ is deleted" ) for @keys;
    my $revoked =
      $functions->row( 'privacy_revoke_user',
        { source => 'Avatar', user_id => $other, at => $NOW } );
    ok( $revoked->{revoked} >= 2, 'and the rows go' );
    is( _row($other), undef, 'no picture row is left' );
    is(
        scalar $dbh->selectrow_array(
            q{SELECT count(*) FROM attachments a JOIN attachment_links l}
              . q{ ON l.attachment_id = a.attachment_id}
              . q{ WHERE l.target_type = 'profile' AND l.target_id = ?}
              . q{ AND a.state <> 'deleted'},
            undef, $other
        ),
        0,
        'every profile upload of theirs is deleted'
    );
};

subtest 'the full erasure takes the picture' => sub {
    my $avatars = _avatars();
    is( $avatars->upload( { user_id => $suspended, content => _png( 40, 40 ) } )
          ->{status},
        'shown', 'a picture to erase' );
    my @keys = map { $_->{object_key} } @{ $store->objects($suspended) };
    my $test = Test::Mojo->new('GPForum');
    _wire( $test->app );
    my $deletion = $test->app->build_controller->gp_deletion_workflow;
    ok( $deletion->avatars, 'the erasure is given the pictures' );
    $deletion->avatars($avatars);
    my $request = $deletion->request_deletion(
        {
            reason            => 'leaving',
            request_type      => 'anonymize',
            requester_user_id => $suspended,
            resource_id       => $suspended,
            resource_type     => 'user',
        }
    );
    my $approved = $deletion->approve_request( $request->{deletion_request_id},
        $admin, 'verified' );
    my $completed =
      $deletion->complete_job( $approved->{job}{erasure_job_id}, $admin );
    ok( $completed && $completed->{ok}, 'the erasure completes' );
    is( _row($suspended), undef, 'the erasure removes the picture row' );
    ok( !grep( { $storage->exists_object($_) } @keys ), 'and its files' );
};

done_testing();

sub _row ($user_id) {
    return $dbh->selectrow_hashref(
        q{SELECT * FROM member_avatars WHERE user_id = ?},
        undef, $user_id );
}

sub _attachment ($attachment_id) {
    return $dbh->selectrow_hashref(
        q{SELECT * FROM attachments WHERE attachment_id = ?},
        undef, $attachment_id );
}

sub _keys ($attachment_id) {
    return map { $_->{object_key} }
      @{ $store->objects( _attachment($attachment_id)->{owner_user_id},
            $attachment_id ) };
}

sub _count ($table) {
    return scalar $dbh->selectrow_array(qq{SELECT count(*) FROM $table});
}

sub _file ( $content, $filename = 'me.png', $type = 'image/png' ) {
    return {
        content        => $content,
        filename       => $filename,
        'Content-Type' => $type,
    };
}

sub _png ( $width, $height ) {
    return GPForum::Test::ImageTool->png( $width, $height );
}

# A PNG's signature and header alone: its size, and no picture.
sub _png_header ( $width, $height ) {
    my $header = pack 'N N C C C C C', $width, $height, 8, 2, 0, 0, 0;

    return "\x89PNG\x0d\x0a\x1a\x0a"
      . pack( 'N', length $header )
      . 'IHDR'
      . $header
      . pack( 'N', Compress::Zlib::crc32( 'IHDR' . $header ) );
}

# A JPEG's start and frame header: enough to be sniffed and measured; the
# fake tool draws the squares.
sub _jpeg ( $width, $height ) {
    return "\xff\xd8\xff\xe0"
      . pack( 'n', 16 )
      . "JFIF\0\x01\x01\0\0\x01\0\x01\0\0"
      . "\xff\xc0"
      . pack( 'n C n n C', 11, 8, $height, $width, 1 )
      . "\x01\x11\0"
      . "\xff\xd9";
}

sub _attachments {
    return GPForum::Service::Attachment::Store->new(
        schema  => $schema,
        storage => $storage,
    );
}

sub _avatars {
    return GPForum::Service::Community::Avatars->new(
        attachments => _attachments(),
        image_tool  => $tool,
        pipeline    => GPForum::Service::Attachment::UploadPipeline->new(
            antivirus => $antivirus,
            storage   => $storage,
            store     => _attachments(),
        ),
        storage => $storage,
        store   => $store,
    );
}

sub _media_processor {
    return GPForum::Service::Attachment::MediaProcessor->new(
        avatars => _avatars(),
        storage => $storage,
        store   => _attachments(),
    );
}

sub _csrf ($test) {
    $test->get_ok('/settings');
    my $input = $test->tx->res->dom->at('input[name=csrf_token]');

    return $input ? $input->attr('value') : q{};
}

sub _wire ($application) {
    $application->helper( gp_attachment_storage => sub { return $storage; } );
    $application->helper( gp_image_tool         => sub { return $tool; } );
    $application->helper( gp_antivirus          => sub { return $antivirus; } );

    return;
}

# A browser, signed in as the user when one is given.
sub _client ($user_id) {
    $dbh->do(q{DELETE FROM rate_limit_buckets});
    my $test = Test::Mojo->new('GPForum');
    _wire( $test->app );
    return $test if !defined $user_id;

    $test->app->routes->get('/__test/avatar-session')->to(
        cb => sub ($c) {
            $c->session( user_id => $user_id );
            return $c->render( json => { ok => 1 } );
        }
    );
    $test->get_ok('/__test/avatar-session')->status_is($HTTP_OK);

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
