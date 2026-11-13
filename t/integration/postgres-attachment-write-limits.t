# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use lib 'lib';
use lib 't/lib';
use Const::Fast;
use File::Temp qw(tempdir);
use Mojo::Asset::Memory;
use Mojo::Headers;
use Mojo::Promise;
use Mojo::Upload;
use Test::More;
use GPForum::Config;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Attachment::ContentReview;
use GPForum::Service::Attachment::FilesystemStorage;
use GPForum::Service::Attachment::PostgresStorage;
use GPForum::Service::Attachment::Store;
use GPForum::Service::Attachment::UploadPipeline;
use GPForum::Service::Attachment::Workflow;
use GPForum::Service::Forum::PostReader;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::Antivirus;
use GPForum::Test::ImageTool;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';
const my $PNG                     => GPForum::Test::ImageTool->png( 2, 2 );
const my $EXACT_UPLOADS           => 2;
const my $PLENTY                  => 1_024 * 1_024;
const my $REVIEW_SIDE             => 3;
const my $RETAINED_REVIEW_UPLOADS => 3;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'temporary PostgreSQL required';
}
my $database = GPForum::Test::PgDatabase->fresh;
my $schema   = $database->schema;
my $dbh      = $database->dbh;
my $ids      = GPForum::Infrastructure::Id->new;
my $root     = tempdir( CLEANUP => 1 );
my $author   = user('author');
my $space    = $ids->uuid;
my $category = $ids->uuid;
my $thread   = $ids->uuid;
my $post     = $ids->uuid;
$dbh->do( 'INSERT INTO spaces(space_id,slug,title) VALUES(?,?,?)',
    undef, $space, 'files', 'Files' );
$dbh->do(
    'INSERT INTO categories(category_id,space_id,slug,title) VALUES(?,?,?,?)',
    undef, $category, $space, 'files', 'Files' );
$dbh->do(
'INSERT INTO threads(thread_id,category_id,author_user_id,title,slug) VALUES(?,?,?,?,?)',
    undef, $thread, $category, $author, 'Files', 'files'
);
$dbh->do(
'INSERT INTO posts(post_id,thread_id,author_user_id,position) VALUES(?,?,?,1)',
    undef, $post, $thread, $author
);

for my $backend (qw(filesystem postgres)) {
    subtest "$backend owner allowance" => sub {
        my $owner    = user($backend);
        my $pipeline = pipeline( $schema, $backend,
            owner_max_bytes => length($PNG) * $EXACT_UPLOADS );
        my @accepted = map { $pipeline->upload_and_link( input($owner) ) }
          1 .. $EXACT_UPLOADS;
        ok( !grep( { !$_->{ok} } @accepted ),
            'uploads fit exactly at the byte boundary' );
        my $count   = count_objects($backend);
        my $refused = $pipeline->upload_and_link( input($owner) );
        is(
            $refused->{errors}{attachment},
            'attachment storage quota exceeded',
            'next upload is refused'
        );
        is( count_objects($backend), $count,
            'refusal writes no source object' );
        GPForum::Service::Attachment::Store->new( schema => $schema )
          ->soft_delete( $accepted[0]{attachment}{attachment_id},
            $owner, 'author delete' );
        $refused = $pipeline->upload_and_link( input($owner) );
        is(
            $refused->{errors}{attachment},
            'attachment storage quota exceeded',
            'soft deletion cannot reset retained-byte allowance'
        );
        is( count_objects($backend), $count,
            'delete and retry retain the same source object count' );
    };
}

subtest 'pending allowance and concurrent uploads' => sub {
    my $owner   = user('pending');
    my $pending = pipeline(
        $schema, 'postgres',
        owner_max_pending => 1,
        antivirus         => GPForum::Test::Antivirus->new( immediate => 0 )
    );
    my $awaiting = $pending->upload_and_link( input($owner) );
    ok( $awaiting->{ok}, 'first pending source is accepted' );
    is(
        $pending->upload_and_link( input($owner) )->{errors}{attachment},
        'too many pending attachments',
        'second pending source is refused'
    );
    $dbh->do(
q{UPDATE attachments SET scan_status='clean',state='intent' WHERE attachment_id=?},
        undef, $awaiting->{attachment}{attachment_id}
    );
    is(
        $pending->upload_and_link( input($owner) )->{errors}{attachment},
        'too many pending attachments',
        'unfinished intent counts even with a completed scan'
    );
    $dbh->do(
q{UPDATE attachments SET scan_status='pending',state='deleted' WHERE attachment_id=?},
        undef, $awaiting->{attachment}{attachment_id}
    );
    ok(
        $pending->upload_and_link( input($owner) )->{ok},
'deleted state releases pending allowance even without a deletion timestamp'
    );

    for my $limit (qw(bytes pending)) {
        my $racer    = user( 'race_' . $limit );
        my @outcomes = GPForum::Test::PostgresHarness::race(
            sub {
                my $connection = connect_schema();
                my $writer     = pipeline(
                    $connection, 'postgres',
                    owner_max_bytes => $limit eq 'bytes'
                    ? length($PNG)
                    : $PLENTY,
                    owner_max_pending => 1,
                    antivirus => GPForum::Test::Antivirus->new( immediate => 0 )
                );
                my $answer = $writer->upload_and_link( input($racer) );
                return { ok => $answer->{ok}, errors => $answer->{errors} };
            }
        );
        ok( !grep( { !$_->{ok} } @outcomes ), "$limit race workers completed" );
        is( scalar grep( { $_->{result}{ok} } @outcomes ),
            1, "$limit allowance admits exactly one simultaneous upload" );
        is(
            $dbh->selectrow_array(
                'SELECT count(*) FROM attachments WHERE owner_user_id=?',
                undef, $racer
            ),
            1,
            "$limit race retains one metadata row"
        );
    }
};

subtest 'clean uploads awaiting content review consume pending allowance' =>
  \&review_pending_allowance;

subtest 'author changes respect current thread and post state' => sub {
    my $store  = GPForum::Service::Attachment::Store->new( schema => $schema );
    my $writer = pipeline( $schema, 'postgres' );
    my $workflow = GPForum::Service::Attachment::Workflow->new(
        command_idempotency =>
          GPForum::Service::Operations::CommandIdempotency->new(
            schema => $schema
          ),
        store       => $store,
        pipeline    => $writer,
        delivery    => $store,
        post_reader =>
          GPForum::Service::Forum::PostReader->new( schema => $schema )
    );
    my $request =
      { actor_user_id => $author, post_id => $post, upload => upload() };
    my $allowed =
      $workflow->upload_for_post( { %{$request}, command_id => $ids->uuid } );
    ok( $allowed->{ok}, 'unlocked author upload succeeds' );
    my $attachment = $allowed->{stored}{attachment}{attachment_id};
    my $other      = user('private_viewer');
    $dbh->do( 'UPDATE posts SET visibility=? WHERE post_id=?',
        undef, 'private', $post );
    is(
        $workflow->upload_for_post(
            {
                %{$request},
                actor_user_id => $other,
                command_id    => $ids->uuid
            }
        )->{status},
        'not_found',
        'guard author refusal does not reveal an unreadable private post'
    );
    $dbh->do( 'UPDATE posts SET visibility=? WHERE post_id=?',
        undef, 'public', $post );
    $dbh->do( 'UPDATE threads SET locked_at=now() WHERE thread_id=?',
        undef, $thread );
    my $before = count_objects('postgres');
    my $locked =
      $workflow->upload_for_post( { %{$request}, command_id => $ids->uuid } );
    is( $locked->{status}, 'forbidden',
        'locked_at alone refuses author upload' );
    is( $locked->{error}, 'thread is locked', 'lock refusal is explicit' );
    is( count_objects('postgres'), $before,   'locked upload writes no bytes' );
    my $deleted = $workflow->delete_for_post(
        { %{$request}, attachment_id => $attachment, command_id => $ids->uuid }
    );
    is( $deleted->{status}, 'forbidden',
        'locked thread refuses attachment deletion' );
    is(
        $dbh->selectrow_array(
            'SELECT deleted_at FROM attachments WHERE attachment_id=?', undef,
            $attachment
        ),
        undef,
        'locked deletion leaves metadata intact'
    );
    $dbh->do( 'UPDATE threads SET locked_at=NULL WHERE thread_id=?',
        undef, $thread );
    $deleted = $workflow->delete_for_post(
        { %{$request}, attachment_id => $attachment, command_id => $ids->uuid }
    );
    ok( $deleted->{ok}, 'unlocked author deletion succeeds' );

    for my $state (
        [ thread => q{moderation_state='hidden'} ],
        [ thread => 'deleted_at=now()' ],
        [ post   => q{moderation_state='hidden'} ],
        [ post   => 'deleted_at=now()' ],
      )
    {
        my ( $kind, $change ) = @{$state};
        my $table = $kind eq 'thread' ? 'threads' : 'posts';
        my $key   = $kind eq 'thread' ? $thread   : $post;
        $dbh->do( "UPDATE $table SET $change WHERE ${kind}_id=?", undef, $key );
        is(
            $workflow->upload_for_post(
                { %{$request}, command_id => $ids->uuid }
            )->{status},
            'not_found',
            "$kind $change refuses author upload"
        );
        $dbh->do(
"UPDATE $table SET moderation_state='visible',deleted_at=NULL WHERE ${kind}_id=?",
            undef, $key
        );
    }
};

subtest 'moderation committed while an author waits is rechecked' => sub {
    my $holder = connect_schema();
    $holder->txn_begin;
    $holder->storage->dbh->do(
        'UPDATE threads SET locked_at=now() WHERE thread_id=?',
        undef, $thread );
    my $attempt = GPForum::Test::PostgresHarness::hold(
        sub ( $ready, $go ) {
            my $connection = connect_schema();
            $ready->(
                {
                    pid => $connection->storage->dbh->selectrow_array(
                        'SELECT pg_backend_pid()')
                }
            );
            return GPForum::Infrastructure::SqlFunction->settle(
                GPForum::Service::Attachment::Store->new(
                    schema => $connection
                ),
                'with_post_write_p',
                { post_id => $post, actor_user_id => $author },
                sub ($) { return Mojo::Promise->resolve( { ok => 1 } ); }
            );
        }
    );
    GPForum::Test::PostgresHarness::await_ready($attempt);
    ok(
        GPForum::Test::PostgresHarness::await_row_wait(
            $dbh,
            $holder->storage->dbh->selectrow_array('SELECT pg_backend_pid()')
        ),
        'attachment guard waits behind plain lock update'
    );
    $holder->txn_commit;
    my $outcome = GPForum::Test::PostgresHarness::collect($attempt);
    is(
        $outcome->{result}{error},
        'thread is locked',
        'committed lock is rechecked after waiting'
    );
};

done_testing();

sub review_pending_allowance {
    my $reviewer     = user('reviewer');
    my $both_owner   = user('scan_and_review');
    my $both_pending = pipeline(
        $schema,
        'postgres',
        owner_max_pending => $EXACT_UPLOADS,
        review            => GPForum::Service::Attachment::ContentReview->new(
            schema       => $schema,
            source_hosts => ['media.example.org']
        ),
        antivirus => GPForum::Test::Antivirus->new( immediate => 0 )
    );
    for ( 1 .. $EXACT_UPLOADS ) {
        ok(
            $both_pending->upload_and_link( input($both_owner) )->{ok},
            'a source awaiting both scan and human review counts once'
        );
    }
    is(
        $both_pending->upload_and_link( input($both_owner) )
          ->{errors}{attachment},
        'too many pending attachments',
        'combined pending states stop at the attachment count'
    );

    for my $mode (qw(off immediate)) {
        my $owner  = user( 'review_' . $mode );
        my $review = GPForum::Service::Attachment::ContentReview->new(
            schema       => $schema,
            source_hosts => ['media.example.org']
        );
        my $scanner = $mode eq 'off' ? undef : GPForum::Test::Antivirus->new;
        my $source  = {
            %{ input($owner) },
            content => GPForum::Test::ImageTool->png(
                $mode eq 'off' ? 2 : $REVIEW_SIDE, $REVIEW_SIDE
            )
        };
        my $writer = pipeline(
            $schema, 'postgres',
            review            => $review,
            antivirus         => $scanner,
            owner_max_pending => 1
        );
        my $first = $writer->upload_and_link($source);
        ok( $first->{ok}, "$mode scanning accepts first review submission" );
        my $first_id = $first->{attachment}{attachment_id};
        is(
            $dbh->selectrow_array(
                'SELECT scan_status FROM attachments WHERE attachment_id=?',
                undef, $first_id
            ),
            'clean',
            "$mode scanning completes before human review"
        );
        is(
            $dbh->selectrow_array(
'SELECT status FROM attachment_content_reviews WHERE attachment_id=?',
                undef,
                $first_id
            ),
            'pending',
            "$mode scan leaves human review pending"
        );
        my $before = count_objects('postgres');
        is(
            $writer->upload_and_link($source)->{errors}{attachment},
            'too many pending attachments',
            "$mode clean review backlog reaches pending limit"
        );
        is( count_objects('postgres'),
            $before, "$mode backlog refusal writes no source bytes" );
        is(
            $review->decide(
                {
                    attachment_id => $first_id,
                    actor_user_id => $reviewer,
                    decision      => 'approved',
                    reason        => 'content approved'
                }
            )->{status},
            'ok',
            "$mode approval completes clean content review"
        );
        my $replacement = $writer->upload_and_link($source);
        ok( $replacement->{ok}, "$mode approval releases pending allowance" );
        my $replacement_id = $replacement->{attachment}{attachment_id};
        GPForum::Service::Attachment::Store->new( schema => $schema )
          ->soft_delete( $replacement_id, $owner, 'author delete' );
        my $third = $writer->upload_and_link($source);
        ok( $third->{ok},
            "$mode deleted review does not occupy pending allowance" );
        is(
            $review->decide(
                {
                    attachment_id => $third->{attachment}{attachment_id},
                    actor_user_id => $reviewer,
                    decision      => 'rejected',
                    reason        => 'content rejected'
                }
            )->{status},
            'ok',
            "$mode rejection completes human review"
        );
        my $store =
          GPForum::Service::Attachment::Store->new( schema => $schema );
        my $quota = {
            owner_user_id => $owner,
            byte_size     => length( $source->{content} ),
            max_bytes     => $PLENTY,
            max_pending   => 1
        };
        ok(
            $schema->txn_do(
                sub { return $store->check_upload_quota($quota); }
            )->{ok},
"$mode approved and rejected clean files no longer occupy pending allowance"
        );
        is(
            $schema->txn_do(
                sub {
                    return $store->check_upload_quota(
                        {
                            %{$quota},
                            max_bytes => length( $source->{content} ) *
                              $RETAINED_REVIEW_UPLOADS
                        }
                    );
                }
            )->{errors}{attachment},
            'attachment storage quota exceeded',
"$mode approved, deleted and rejected sources all retain their byte charge"
        );

        my $racer    = user( 'review_race_' . $mode );
        my @outcomes = GPForum::Test::PostgresHarness::race(
            sub {
                my $connection  = connect_schema();
                my $race_writer = pipeline(
                    $connection,
                    'postgres',
                    owner_max_pending => 1,
                    antivirus         => $mode eq 'off'
                    ? undef
                    : GPForum::Test::Antivirus->new,
                    review => GPForum::Service::Attachment::ContentReview->new(
                        schema       => $connection,
                        source_hosts => ['media.example.org']
                    )
                );
                my $answer = $race_writer->upload_and_link( input($racer) );
                return { ok => $answer->{ok}, errors => $answer->{errors} };
            }
        );
        ok( !grep( { !$_->{ok} } @outcomes ),
            "$mode clean review race workers completed" );
        is( scalar grep( { $_->{result}{ok} } @outcomes ),
            1,
            "$mode clean review race admits exactly one pending submission" );
        is(
            $dbh->selectrow_array(
                join( q{ },
                    'SELECT count(*) FROM attachments a',
                    'JOIN attachment_content_reviews r USING(attachment_id)',
q{WHERE a.owner_user_id=? AND a.scan_status='clean' AND r.status='pending'}
                ),
                undef, $racer
            ),
            1,
            "$mode race retains one clean pending review"
        );
    }
    return;
}

sub user ($name) {
    my $id = $ids->uuid;
    $dbh->do(
q{INSERT INTO users(id,username,display_name,email_normalized,password_hash,status) VALUES(?,?,?,?,'x','active')},
        undef, $id, $name, $name, "$name\@example.test"
    );
    return $id;
}

sub pipeline ( $connection, $backend, %options ) {
    my $storage =
      $backend eq 'postgres'
      ? GPForum::Service::Attachment::PostgresStorage->new(
        schema => $connection )
      : GPForum::Service::Attachment::FilesystemStorage->new( root => $root );
    return GPForum::Service::Attachment::UploadPipeline->new(
        store =>
          GPForum::Service::Attachment::Store->new( schema => $connection ),
        storage => $storage,
        %options
    );
}

sub input ($owner) {
    return {
        actor_user_id     => $owner,
        content           => $PNG,
        media_type        => 'image/png',
        original_filename => 'photo.png',
        source_kind       => 'authorized',
        source_url        => 'https://media.example.org/file',
        rights_confirmed  => 1
    };
}

sub upload {
    return Mojo::Upload->new(
        filename => 'photo.png',
        headers  => Mojo::Headers->new->content_type('image/png'),
        asset    => Mojo::Asset::Memory->new->add_chunk($PNG)
    );
}

sub count_objects ($backend) {
    return $dbh->selectrow_array('SELECT count(*) FROM attachment_objects')
      if $backend eq 'postgres';
    require Mojo::File;
    return scalar @{ Mojo::File->new($root)->list_tree->to_array };
}

sub connect_schema {
    local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
    return GPForum::Test::PostgresHarness::connect_schema();
}

1;
