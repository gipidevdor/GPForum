# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

# Attachment uploads and profile pictures as the web worker runs them.
# Without a METHOD_p, call_p ran each in a forked child that opened a
# PostgreSQL connection of its own, one child at a time per worker. Each
# promise here must answer what its blocking write answers and leave the
# same rows and bytes behind, and only the scan, the hash of a large upload
# and the image tool may run in a child: through cpu_p, never a fork
# fallback.
package main;
use v5.40;
use Const::Fast;
use File::Temp qw(tempdir);
use Mojo::Asset::Memory;
use Mojo::Headers;
use Mojo::Upload;
use Test::More;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Infrastructure::AsyncWork;
use GPForum::Service::Attachment::PostgresStorage;
use GPForum::Service::Attachment::Store;
use GPForum::Service::Attachment::UploadPipeline;
use GPForum::Service::Attachment::Workflow;
use GPForum::Service::Community::AvatarStore;
use GPForum::Service::Community::Avatars;
use GPForum::Test::Antivirus;
use GPForum::Test::Forks qw(children_during);
use GPForum::Test::ImageTool;
use GPForum::Test::PgDatabase;
use GPForum::Test::Promise qw(await_result);

our $VERSION = '0.001';
const my $WIDTH  => 300;
const my $HEIGHT => 200;
const my $LARGE  => 2 * 1_024 * 1_024 + 17;
const my $HEX    => qr/[[:xdigit:]]/msx;
const my $UUID => qr/$HEX {8} - $HEX {4} - $HEX {4} - $HEX {4} - $HEX {12}/msx;
const my @VARIANTS  => qw(avatar_128 avatar_256 avatar_64);
const my $REASON    => 'not a portrait';
const my $NO_REASON => 'x' x 501;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all =>
      'set GPFORUM_TEST_DSN to compare attachment write promises';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
my $dbh    = $database->dbh;
my $schema = $database->schema;
my $t      = Test::Mojo->new('GPForum');
my $c      = $t->app->build_controller;
my $tool   = GPForum::Test::ImageTool->new(
    calls_file => tempdir( CLEANUP => 1 ) . '/image-tool-calls.bin' );
my $storage =
  GPForum::Service::Attachment::PostgresStorage->new( schema => $schema );

my ( $post_id, $author ) =
  $dbh->selectrow_array( q{SELECT p.post_id, p.author_user_id FROM posts p}
      . q{ JOIN threads t ON t.thread_id = p.thread_id}
      . q{ JOIN categories c ON c.category_id = t.category_id}
      . q{ JOIN spaces s ON s.space_id = c.space_id}
      . q{ JOIN users u ON u.id = p.author_user_id}
      . q{ WHERE p.deleted_at IS NULL AND p.moderation_state = 'visible'}
      . q{ AND p.visibility = 'public' AND t.deleted_at IS NULL}
      . q{ AND t.moderation_state = 'visible' AND t.visibility = 'public'}
      . q{ AND t.locked_at IS NULL AND c.visibility = 'public'}
      . q{ AND s.visibility = 'public' AND u.status = 'active'}
      . q{ AND u.deleted_at IS NULL ORDER BY p.post_id LIMIT 1} );
ok( $post_id, 'the seed has a public post by an active member' );

# Every child a write starts, recorded instead of trusted; a child on the
# CPU lane is the child it is meant to make, and counted.
my $children = children_during( \&writes );
is_deeply( $children->{other}, [], 'no write reached a fork fallback' );
ok( $children->{cpu} > 0, 'the scan, the hash and the crop ran through cpu_p' );

done_testing;

sub writes {
    subtest 'a post upload stores what the blocking upload stores' => sub {
        uploads_alike( GPForum::Test::ImageTool->png( $WIDTH, $HEIGHT ),
            'a small picture' );
        uploads_alike(
            GPForum::Test::ImageTool->png( $WIDTH, $HEIGHT ) . "\0" x $LARGE,
            'a picture of several chunks, hashed in a child' );
    };
    subtest 'a replayed and a refused upload answer alike' => \&upload_edges;
    subtest 'a profile picture is uploaded, replaced and removed alike' =>
      \&avatars_alike;
    subtest 'staff remove a picture alike' => \&moderated_alike;
    return;
}

sub uploads_alike ( $bytes, $label ) {
    my $input = sub {
        return upload_input( $bytes, $c->gp_id->uuid );
    };
    my $blocking = workflow()->upload_for_post( $input->() );
    my $promised =
      await_result( workflow()->upload_for_post_p( $input->(), undef ) );
    ok( $blocking->{ok} && $promised->{ok}, "$label: both uploads succeed" )
      or diag explain [ $blocking, $promised ];
    is_deeply( without_ids($promised), without_ids($blocking),
        "$label: the promise answers what the blocking upload answers" );
    my ( $kept, $sent ) =
      map { $_->{stored}{attachment}{attachment_id} } $blocking, $promised;
    is_deeply( attachment_rows($sent), attachment_rows($kept),
        "$label: the same attachment, review, link, object and events" );
    is( stored_bytes($sent), $bytes, "$label: the bytes are stored whole" );
    my $rows = attachment_rows($sent);
    ok(
        $rows->{attachment}{scan_engine} eq 'Fake 1/1'
          && $rows->{review}
          && @{ $rows->{links} } == 1
          && $rows->{object}{complete},
        "$label: scanned, reviewed, linked and complete"
    ) or diag explain $rows;
    return;
}

sub upload_edges {
    my $bytes = GPForum::Test::ImageTool->png( $WIDTH, $HEIGHT );
    my $input = upload_input( $bytes, $c->gp_id->uuid );
    my $first = await_result( workflow()->upload_for_post_p( $input, undef ) );
    my $count = sub {
        return
          scalar $dbh->selectrow_array(q{SELECT count(*) FROM attachments});
    };
    my $before = $count->();
    is_deeply(
        await_result(
            workflow()->upload_for_post_p(
                upload_input( $bytes, $input->{command_id} ), undef
            )
        ),
        $first,
        'a repeated command id replays its answer'
    );
    is( $count->(), $before, 'and stores nothing more' );

    my %refused = (
        'no provenance'  => { source_kind   => undef },
        'another post'   => { post_id       => $c->gp_id->uuid },
        'no command id'  => { command_id    => q{} },
        'not the author' => { actor_user_id => $c->gp_id->uuid },
    );
    for my $case ( sort keys %refused ) {
        my $make = sub {
            return {
                %{ upload_input( $bytes, $c->gp_id->uuid ) },
                %{ $refused{$case} }
            };
        };
        my $blocking = workflow()->upload_for_post( $make->() );
        my $promised =
          await_result( workflow()->upload_for_post_p( $make->(), undef ) );
        ok( !$promised->{ok}, "$case: refused" );
        is_deeply( $promised, $blocking, "$case: refused alike" );
    }
    return;
}

sub avatars_alike {
    my ( $kept, $sent ) =
      ( member('avatar_blocking'), member('avatar_promised') );
    my $picture  = GPForum::Test::ImageTool->png( $WIDTH, $HEIGHT );
    my $blocking = avatars()->upload( avatar_input( $kept, $picture ) );
    my $promised =
      await_result(
        avatars()->upload_p( avatar_input( $sent, $picture ), undef ) );
    is( $promised->{status}, 'shown', 'the picture is shown at once' );
    is_deeply( $promised, $blocking, 'upload_p answers what upload answers' );
    is_deeply( avatar_state($sent), avatar_state($kept),
        'the same rows, squares and bytes' );
    is_deeply(
        [ map { $_->{variant_type} } @{ avatar_state($sent)->{squares} } ],
        [@VARIANTS], 'kept at its three sides' );

    my $portrait = GPForum::Test::ImageTool->png( $HEIGHT, $WIDTH );
    my ( $first_kept, $first_sent ) =
      map { shown_of($_) } $kept, $sent;
    is_deeply(
        await_result(
            avatars()->upload_p( avatar_input( $sent, $portrait ), undef )
        ),
        avatars()->upload( avatar_input( $kept, $portrait ) ),
        'a new picture replaces the old one alike'
    );
    is_deeply( avatar_state($sent), avatar_state($kept),
        'the replaced pictures leave the same rows' );
    is_deeply(
        deleted_state( $first_sent, $sent ),
        deleted_state( $first_kept, $kept ),
        'the replaced upload is deleted, files first, audited alike'
    );
    my $gone = deleted_state( $first_sent, $sent );
    ok(
        $gone->{state} eq 'deleted'
          && !$gone->{objects}
          && grep( { $_ eq 'attachment.deleted' } @{ $gone->{events} } ),
        'deleted, with no object left and its event recorded'
    ) or diag explain $gone;

    my ( $shown_kept, $shown_sent ) =
      map { shown_of($_) } $kept, $sent;
    is_deeply(
        await_result( avatars()->remove_own_p( $sent, undef ) ),
        avatars()->remove_own($kept),
        'remove_own_p answers what remove_own answers'
    );
    is_deeply( avatar_state($sent), avatar_state($kept),
        'and leaves no picture behind' );
    is_deeply(
        deleted_state( $shown_sent, $sent ),
        deleted_state( $shown_kept, $kept ),
        'the removed upload is deleted alike'
    );
    is_deeply(
        await_result( avatars()->remove_own_p( $sent, undef ) ),
        avatars()->remove_own($kept),
        'a second removal finds nothing alike'
    );

    my $square = await_result(
        avatars()->picture_from_input_p(
            { user_id => $sent, avatar_id => undef, side => 64 }, undef
        )
    );
    is( $square, undef, 'a removed picture is no longer served' );
    return;
}

sub moderated_alike {
    my $staff = $dbh->selectrow_array(
        q{SELECT id FROM users WHERE status = 'active' ORDER BY id LIMIT 1});
    my ( $kept, $sent ) = ( member('avatar_kept'), member('avatar_sent') );
    my $picture = GPForum::Test::ImageTool->png( $WIDTH, $HEIGHT );
    avatars()->upload( avatar_input( $kept, $picture ) );
    await_result(
        avatars()->upload_p( avatar_input( $sent, $picture ), undef ) );
    my ( $shown_kept, $shown_sent ) =
      map { shown_of($_) } $kept, $sent;
    my $order = sub ( $member, $shown, $reason ) {
        return {
            actor_user_id   => $staff,
            subject_user_id => $member,
            attachment_id   => $shown,
            reason          => $reason,
        };
    };

    is_deeply(
        await_result(
            avatars()
              ->moderate_p( $order->( $sent, $shown_sent, $NO_REASON ), undef )
        ),
        avatars()->moderate( $order->( $kept, $shown_kept, $NO_REASON ) ),
        'a reason too long is refused alike'
    );
    my $square = await_result(
        avatars()->picture_from_input_p(
            { user_id => $sent, avatar_id => $shown_sent, side => 128 }, undef
        )
    );
    ok( $square && $square->{current} && length $square->{content},
        'the picture is served before it is removed' );
    is_deeply(
        await_result(
            avatars()
              ->moderate_p( $order->( $sent, $shown_sent, $REASON ), undef )
        ),
        avatars()->moderate( $order->( $kept, $shown_kept, $REASON ) ),
        'moderate_p answers what moderate answers'
    );
    is_deeply( avatar_state($sent), avatar_state($kept),
        'no picture is shown after either' );
    is_deeply(
        deleted_state( $shown_sent, $sent ),
        deleted_state( $shown_kept, $kept ),
        'the removed upload is deleted alike'
    );
    is_deeply(
        audits( $shown_sent, $sent ),
        audits( $shown_kept, $kept ),
        'and audited alike'
    );
    return;
}

sub workflow {
    my $store = $c->gp_attachment_store;
    return GPForum::Service::Attachment::Workflow->new(
        command_idempotency => $c->gp_command_idempotency,
        delivery            => $c->gp_attachment_delivery,
        pipeline            => pipeline($store),
        post_reader         => $c->gp_post_reader,
        store               => $store,
    );
}

sub pipeline ($store) {
    return GPForum::Service::Attachment::UploadPipeline->new(
        antivirus => GPForum::Test::Antivirus->new,
        review    => $c->gp_attachment_content_review,
        storage   => $storage,
        store     => $store,
    );
}

sub avatars {
    my $attachments = $c->gp_attachment_store;
    return GPForum::Service::Community::Avatars->new(
        attachments => $attachments,
        image_tool  => $tool,
        pipeline    => pipeline($attachments),
        review      => $c->gp_attachment_content_review,
        storage     => $storage,
        store       =>
          GPForum::Service::Community::AvatarStore->new( schema => $schema ),
    );
}

sub upload_input ( $bytes, $command_id ) {
    my $upload = Mojo::Upload->new(
        asset    => Mojo::Asset::Memory->new->add_chunk($bytes),
        filename => 'picture.png',
        headers  => Mojo::Headers->new->content_type('image/png'),
        name     => 'attachment',
    );
    return {
        actor_user_id    => $author,
        command_id       => $command_id,
        post_id          => $post_id,
        upload           => $upload,
        viewer           => $c->gp_forum_viewer,
        source_kind      => 'original',
        source_url       => undef,
        rights_confirmed => '1',
    };
}

sub avatar_input ( $member, $bytes ) {
    return {
        user_id           => $member,
        content           => $bytes,
        original_filename => 'me.png',
        source_kind       => 'original',
        rights_confirmed  => '1',
    };
}

# An answer with the ids each upload draws for itself taken out.
sub without_ids ($answer) {
    my $stored = $answer->{stored} // return $answer;
    return {
        %{$answer},
        stored => {
            %{$stored},
            attachment => {
                %{ $stored->{attachment} }, attachment_id => 'id'
            },
            link => {
                %{ $stored->{link} },
                attachment_id      => 'id',
                attachment_link_id => 'id'
            },
        },
    };
}

sub attachment_rows ($attachment_id) {
    my $row = $dbh->selectrow_hashref(
        q{SELECT owner_user_id, media_type, byte_size, checksum, state,}
          . q{ scan_status, scan_engine, original_filename,}
          . q{ object_key = 'attachments/' || owner_user_id || '/'}
          . q{ || attachment_id AS keyed, uploaded_at IS NOT NULL AS uploaded,}
          . q{ deleted_at FROM attachments WHERE attachment_id = ?},
        undef, $attachment_id
    );
    return {
        attachment => $row,
        review     => $dbh->selectrow_hashref(
            q{SELECT source_kind, source_url FROM attachment_content_reviews}
              . q{ WHERE attachment_id = ?},
            undef,
            $attachment_id
        ),
        links => $dbh->selectall_arrayref(
            q{SELECT target_type, target_id FROM attachment_links}
              . q{ WHERE attachment_id = ?},
            { Slice => {} },
            $attachment_id
        ),
        object => $dbh->selectrow_hashref(
            q{SELECT o.byte_size, o.checksum, o.complete, count(c.*) AS chunks}
              . q{ FROM attachments a JOIN attachment_objects o}
              . q{ ON o.object_key = a.object_key}
              . q{ LEFT JOIN attachment_object_chunks c}
              . q{ ON c.object_key = o.object_key WHERE a.attachment_id = ?}
              . q{ GROUP BY o.byte_size, o.checksum, o.complete},
            undef,
            $attachment_id
        ),
        events => events($attachment_id),
    };
}

sub events ($attachment_id) {
    return $dbh->selectcol_arrayref(
        q{SELECT event_type FROM event_log WHERE aggregate_id = ?}
          . q{ ORDER BY event_type},
        undef, $attachment_id
    );
}

sub stored_bytes ($attachment_id) {
    my $chunks = $dbh->selectcol_arrayref(
        q{SELECT c.data FROM attachments a JOIN attachment_object_chunks c}
          . q{ ON c.object_key = a.object_key WHERE a.attachment_id = ?}
          . q{ ORDER BY c.chunk_number},
        undef, $attachment_id
    );
    return join q{}, @{$chunks};
}

# The member's picture as the store keeps it: whether one is shown and
# waits, the shown upload's squares, each square's bytes present, and the
# uploads linked to the profile that are not deleted.
sub avatar_state ($member) {
    my $status =
      GPForum::Service::Community::AvatarStore->new( schema => $schema )
      ->status($member);
    my $shown = $status->{attachment_id};
    return {
        has => {
            map { $_ => defined $status->{$_} ? 1 : 0 }
              qw(attachment_id pending_attachment_id)
        },
        squares => $shown
        ? $dbh->selectall_arrayref(
            q{SELECT v.variant_type, v.media_type, o.complete}
              . q{ FROM attachment_variants v JOIN attachment_objects o}
              . q{ ON o.object_key = v.object_key WHERE v.attachment_id = ?}
              . q{ ORDER BY v.variant_type},
            { Slice => {} },
            $shown
          )
        : [],
        live => scalar $dbh->selectrow_array(
            q{SELECT count(*) FROM attachments a JOIN attachment_links l}
              . q{ ON l.attachment_id = a.attachment_id}
              . q{ WHERE l.target_type = 'profile' AND l.target_id = ?}
              . q{ AND a.deleted_at IS NULL},
            undef,
            $member
        ),
    };
}

sub shown_of ($member) {
    return GPForum::Service::Community::AvatarStore->new( schema => $schema )
      ->status($member)->{attachment_id};
}

sub deleted_state ( $attachment_id, $member ) {
    return {
        state => scalar $dbh->selectrow_array(
            q{SELECT state FROM attachments WHERE attachment_id = ?}, undef,
            $attachment_id
        ),
        objects => scalar $dbh->selectrow_array(
            q{SELECT count(*) FROM attachment_objects o}
              . q{ JOIN attachments a ON o.object_key LIKE a.object_key || '%'}
              . q{ WHERE a.attachment_id = ?},
            undef,
            $attachment_id
        ),
        events => events($attachment_id),
    };
}

sub audits ( $attachment_id, $member ) {
    return $dbh->selectall_arrayref(
        q{SELECT action, target_type, metadata->>'reason' AS reason,}
          . q{ metadata->>'subject_user_id' = ? AS subject}
          . q{ FROM audit_log WHERE target_id = ? ORDER BY action},
        { Slice => {} }, $member, $attachment_id
    );
}

sub member ($name) {
    my ($id) = $dbh->selectrow_array(
        q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{ password_hash, status, email_verified_at) VALUES}
          . q{ (gen_random_uuid(), ?, ?, ?, 'x', 'active', now()) RETURNING id},
        undef, $name, $name, "$name\@example.test"
    );
    return $id;
}

1;
