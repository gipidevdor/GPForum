# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Carp qw(croak);
use Const::Fast;
use Mojo::File qw(path);
use Test::More;
use lib 'lib';
use lib 't/lib';
use GPForum::Infrastructure::Id;
use GPForum::Service::Attachment::ContentReview;
use GPForum::Service::Attachment::PostgresStorage;
use GPForum::Service::Attachment::Store;
use GPForum::Service::Attachment::UploadPipeline;
use GPForum::Test::Antivirus;
use GPForum::Test::ImageTool;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';
const my $PHOTO_SIDE => 64;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'requires PostgreSQL';
}
my $database = GPForum::Test::PgDatabase->fresh;
my $schema   = $database->schema;
my $dbh      = $database->dbh;
my $owner    = GPForum::Infrastructure::Id->new->uuid;
$dbh->do(
    join( q{ },
        q{INSERT INTO users(id,username,display_name,email_normalized,},
        q{password_hash,status) VALUES (?,'original_owner','Original Owner',},
        q{'original@example.test','x','active')} ),
    undef, $owner
);
my $store = GPForum::Service::Attachment::Store->new( schema => $schema );
my $storage =
  GPForum::Service::Attachment::PostgresStorage->new( schema => $schema );
my $review = GPForum::Service::Attachment::ContentReview->new(
    schema       => $schema,
    source_hosts => ['media.example.org']
);

sub upload ( $tag, %options ) {
    my $pipeline = GPForum::Service::Attachment::UploadPipeline->new(
        store     => $store,
        storage   => $storage,
        review    => $review,
        antivirus => GPForum::Test::Antivirus->new,
        %{ delete $options{pipeline} // {} }
    );
    return $pipeline->upload_and_link(
        {
            actor_user_id     => $owner,
            original_filename => 'original.png',
            content           => GPForum::Test::ImageTool->png(
                $PHOTO_SIDE, $PHOTO_SIDE, comment => $tag
            ),
            source_kind      => 'original',
            rights_confirmed => 1,
            %options
        }
    );
}

sub attachment_state ($id) {
    return $dbh->selectrow_array(
        'SELECT state FROM attachments WHERE attachment_id=?',
        undef, $id );
}

sub legacy ( $tag, $verdict = 'clean' ) {
    my $file = upload(
        $tag,
        pipeline => {
            review    => undef,
            antivirus => GPForum::Test::Antivirus->new( immediate => 0 )
        }
    );
    croak 'legacy upload failed' if !$file->{ok};
    my $id = $file->{attachment}{attachment_id};
    $dbh->selectrow_array(
        'SELECT submitted FROM api.attachment_review_submit_v2(?,?,?)',
        undef, $id, 'original', q{} );
    if ( $verdict ne 'pending' ) {
        $store->record_scan(
            {
                attachment_id => $id,
                scan_status   => $verdict,
                scan_engine   => 'test',
                actor_id      => 'test'
            }
        );
    }
    return $id;
}

my $original = upload('new original');
ok( $original->{ok}, 'a rights-attested original is accepted' );
my $original_id = $original->{attachment}{attachment_id};
is( attachment_state($original_id),
    'available', 'a clean original publishes without staff' );
is( $review->find($original_id)->{status},
    'approved', 'original content policy is satisfied' );
ok(
    !defined $dbh->selectrow_array(
'SELECT reviewed_by FROM attachment_content_reviews WHERE attachment_id=?',
        undef,
        $original_id
    ),
    'automatic acceptance invents no staff reviewer'
);
is(
    $review->decide(
        {
            attachment_id => $original_id,
            actor_user_id => $owner,
            decision      => 'approved',
            reason        => 'already accepted original'
        }
    )->{status},
    'unchanged',
    'a stale approval form for an original no longer says refused'
);

my $third = upload(
    'third-party',
    source_kind => 'authorized',
    source_url  => 'https://media.example.org/file'
);
my $third_id = $third->{attachment}{attachment_id};
is( attachment_state($third_id),
    'quarantined', 'clean third-party content still waits for staff' );
is(
    $review->decide(
        {
            attachment_id => $third_id,
            actor_user_id => $owner,
            decision      => 'approved',
            reason        => 'my upload'
        }
    )->{status},
    'refused',
    'the uploader cannot approve third-party content'
);
my $queue = $review->queue;
ok(
    !( grep { $_->{attachment_id} eq $original_id } $queue->@* ),
    'originals do not appear in the manual review queue'
);
ok(
    ( grep { $_->{attachment_id} eq $third_id } $queue->@* ),
    'third-party content remains in the manual review queue'
);
ok(
    !upload( 'no attestation', rights_confirmed => 0 )->{ok},
    'original content still requires the rights attestation'
);

my $slow = upload(
    'slow original',
    pipeline => {
        antivirus => GPForum::Test::Antivirus->new( immediate => 0 )
    }
);
my $slow_id = $slow->{attachment}{attachment_id};
is( attachment_state($slow_id),
    'uploaded', 'original content is not public while its scan waits' );
$store->record_scan(
    {
        attachment_id => $slow_id,
        scan_status   => 'clean',
        scan_engine   => 'test',
        actor_id      => 'test'
    }
);
is( attachment_state($slow_id),
    'available', 'a later clean scan publishes the original' );
my $infected = upload(
    'infected original',
    pipeline => {
        antivirus => GPForum::Test::Antivirus->new(
            verdict => {
                status    => 'infected',
                engine    => 'Test scanner',
                signature => 'Test malware'
            }
        )
    }
);
is( attachment_state( $infected->{attachment}{attachment_id} ),
    'quarantined',
    'automatic original acceptance never overrides an infected verdict' );

my $waiting        = legacy('waiting original');
my $still_scanning = legacy( 'waiting scan', 'pending' );
my $failed_scan    = legacy( 'failed scan',  'failed' );
my $rejected       = legacy('rejected original');
$review->decide(
    {
        attachment_id => $rejected,
        actor_user_id => $owner,
        decision      => 'rejected',
        reason        => 'withdraw this exact content'
    }
);
my $blocked  = legacy('blocked pending original');
my $checksum = $dbh->selectrow_array(
    'SELECT checksum FROM attachments WHERE attachment_id=?',
    undef, $blocked );
$dbh->do(
'INSERT INTO attachment_content_blocks(checksum,reason,blocked_by) VALUES (?,?,?)',
    undef, $checksum, 'withdrawn duplicate', $owner
);
my $deleted = legacy('deleted original');
$dbh->do(
q{UPDATE attachments SET state='deleted',deleted_at=now() WHERE attachment_id=?},
    undef, $deleted
);
my $sql = path('migrations/2049_original_upload_publication.sql')->slurp;
my ($upgrade) = $sql =~ / ( DO \s+ \$\$ .*? \$\$ ; ) /msx;
croak 'upgrade statement missing' if !defined $upgrade;
$dbh->do($upgrade);
is( attachment_state($waiting),
    'available', 'upgrade releases a clean original already waiting' );
is( attachment_state($still_scanning),
    'uploaded', 'upgrade retains a pending scan' );
is( attachment_state($failed_scan),
    'quarantined', 'upgrade retains a failed scan' );
is( $review->find($rejected)->{status},
    'rejected', 'upgrade retains staff rejection' );
is( attachment_state($rejected),
    'quarantined', 'a rejected original stays private' );
is( attachment_state($blocked),
    'quarantined', 'upgrade retains checksum withdrawal' );
is( attachment_state($deleted),
    'deleted', 'upgrade does not restore deleted files' );
is( attachment_state($third_id),
    'quarantined', 'upgrade does not release third-party content' );
my $key    = 'original-upload-policy:' . $waiting;
my $events = $dbh->selectrow_array(
    'SELECT count(*) FROM event_log WHERE idempotency_key=?',
    undef, $key );
is( $events, 1,
    'upgrade records one publication event to resume media processing' );
is(
    $dbh->selectrow_array(
        join( q{ },
q{SELECT count(*) FROM outbox_messages o JOIN event_log e USING(event_id)},
            q{WHERE e.idempotency_key=? AND o.status='pending'} ),
        undef, $key
    ),
    1,
    'publication work is durably queued in the same upgrade'
);
$dbh->do($upgrade);
is(
    $dbh->selectrow_array(
        'SELECT count(*) FROM event_log WHERE idempotency_key=?',
        undef, $key
    ),
    $events,
    'repeating the upgrade queues no duplicate work'
);
ok( !upload('rejected original')->{ok},
    'withdrawn bytes cannot be reuploaded as original' );

done_testing();
1;
