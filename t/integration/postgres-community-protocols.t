# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Carp    qw(croak);
use English qw(-no_match_vars);
use Const::Fast;
use utf8;
use lib 'lib';
use lib 't/lib';
use Test::More;
use Test::Fatal qw(exception);
use Test::Mojo;
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Email::MIME;
use GPForum::Test::PgDatabase;
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Service::Operations::Backup;
use GPForum::Service::Forum::PostAttestor;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use IO::Socket::INET;
use IO::Socket::SSL;
use Time::HiRes ();
use POSIX       qw(_exit);
use GPForum::Service::Discovery::Gemini;
use GPForum::Service::Forum::Viewer;
use GPForum::Infrastructure::Row;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Config;

our $VERSION = '0.001';
const my $SIGNED_REVISIONS    => 3;
const my $LEGACY_BATCH_SIZE   => 120;
const my $TLS_START_ATTEMPTS  => 50;
const my $TLS_RETRY_DELAY     => 0.05;
const my $TLS_CONNECT_TIMEOUT => 0.2;

const my $ALL_POSTS         => 122;
const my $SIGNATURE_PAGES   => 2;
const my $HTTP_NOT_FOUND    => 404;
const my $HTTP_OK           => 200;
const my $HTTP_SERVER_ERROR => 500;
const my $PUBLIC_POSTS      => 119;
if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to exercise community protocols';
}
const my $LEGACY_BODIES_SQL => <<'SQL';
WITH inserted AS (INSERT INTO post_bodies(body_id,post_id,body_format,body_source,body_rendered_safe,source_hash)
    SELECT gen_random_uuid(),p.post_id,'markdown','legacy '||p.position,'legacy',md5(p.post_id::text)
    FROM posts p WHERE p.thread_id=? AND p.current_body_id IS NULL RETURNING body_id,post_id)
    UPDATE posts p SET current_body_id=i.body_id FROM inserted i WHERE p.post_id=i.post_id
SQL

const my $LEGACY_POSTS_SQL => <<'SQL';
INSERT INTO posts(post_id,thread_id,author_user_id,position,visibility,moderation_state)
    SELECT gen_random_uuid(), ?, ?, 2+n, 'public','visible' FROM generate_series(1,120) n
SQL

my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $scratch  = tempdir( CLEANUP => 1 );
local $ENV{GPFORUM_ENV}                = 'test';
local $ENV{GPFORUM_DATABASE_DSN}       = $database->dsn;
local $ENV{GPFORUM_POST_SIGNING_KEY}   = "$scratch/post-key.pem";
local $ENV{GPFORUM_MAIL_REPLY_ADDRESS} = 'reply@forum.example';
local $ENV{GPFORUM_PUBLIC_BASE_URL}    = 'http://forum.example';
local $ENV{GPFORUM_ATTACHMENT_ROOT}    = "$scratch/uploads";
path("$scratch/uploads")->make_path;
my $t        = Test::Mojo->new('GPForum');
my $c        = $t->app->build_controller;
my $dbh      = $database->dbh;
my $user     = seed_id( user     => 1 );
my $category = seed_id( category => 1 );
my $viewer =
  GPForum::Service::Forum::ViewerResolver->new( schema => $c->gp_schema )
  ->resolve($user);
my $workflow = $c->gp_posting_workflow;
my $created  = $workflow->create_thread(
    {
        command_id     => 'community-thread',
        author_user_id => $user,
        viewer         => $viewer,
        category_id    => $category,
        title          => 'Portable community',
        body_source    => 'Opening post'
    }
);
ok( $created->{ok}, 'thread created through production workflow' )
  or diag explain $created;
my $thread = GPForum::Infrastructure::Row->column( $created->{stored}{thread},
    'thread_id' );
my $first =
  GPForum::Infrastructure::Row->column( $created->{stored}{post}, 'post_id' );
if ( !$thread ) { BAIL_OUT('thread creation failed'); }
my $signature_count =
  $dbh->selectrow_array('SELECT count(*) FROM post_signatures');
is( $signature_count, 1,
    'first post signature persisted with thread transaction' );
my $reply = $workflow->create_reply(
    {
        command_id     => 'community-reply',
        author_user_id => $user,
        viewer         => $viewer,
        thread_id      => $thread,
        body_source    => "Caffè\nFrom a reader"
    }
);
ok( $reply->{ok}, 'reply created through the typed PostgreSQL function' )
  or diag explain $reply;
my $reply_id =
  GPForum::Infrastructure::Row->column( $reply->{stored}{post}, 'post_id' );
is( $dbh->selectrow_array('SELECT count(*) FROM post_signatures'),
    2, 'fast reply transaction also stores signature' );
$t->get_ok("/t/$thread/archive.mbox")
  ->status_is($HTTP_OK)
  ->content_type_like(qr{application/mbox}msx);
$t->content_like(qr/Opening[ ]post/msx)
  ->content_like(qr/^>From[ ]a[ ]reader=?$/msx);
$t->get_ok("/p/$reply_id/signature")
  ->status_is($HTTP_OK)
  ->json_has('/envelope/signature');
$t->get_ok('/.well-known/gpforum-signing-keys')
  ->status_is($HTTP_OK)
  ->json_is( '/keys/0/crv' => 'Ed25519' );
my $edited = $workflow->edit_post(
    {
        command_id     => 'community-edit',
        author_user_id => $user,
        viewer         => $viewer,
        post_id        => $reply_id,
        body_source    => 'Edited reply'
    }
);
ok( $edited->{ok}, 'post edit succeeds' ) or diag explain $edited;
is( $dbh->selectrow_array('SELECT count(*) FROM post_signatures'),
    $SIGNED_REVISIONS,
    'edit retains original attestation and signs new revision' );
$t->get_ok("/p/$reply_id/signature")
  ->status_is($HTTP_OK)
  ->json_has('/envelope/signature');
$dbh->do(
'UPDATE post_bodies SET body_source = ? WHERE body_id = (SELECT current_body_id FROM posts WHERE post_id = ?)',
    undef, 'altered outside the workflow', $reply_id
);
$t->get_ok("/t/$thread/archive.mbox")->status_is($HTTP_SERVER_ERROR);
$dbh->do(
'UPDATE post_bodies SET body_source = ? WHERE body_id = (SELECT current_body_id FROM posts WHERE post_id = ?)',
    undef, 'Edited reply', $reply_id
);
$t->get_ok("/t/$thread/archive.mbox")->status_is($HTTP_OK);

# More than one reader page must survive the archive, and non-public posts
# must be filtered before writing the spool, including inside a public thread.
$dbh->do( $LEGACY_POSTS_SQL, undef, $thread, $user );
$dbh->do( $LEGACY_BODIES_SQL, undef, $thread );

# The signatures of a page of posts are one call (migration 1041); each was
# one of its own. The application's schema reports its statements to the
# query statistics, not to a callback, so the function layer's calls are
# counted where they are made.
my $execute = GPForum::Infrastructure::SqlFunction->can('_execute');
my @signature_reads;
my $spool = with_replaced_subs(
    'GPForum::Infrastructure::SqlFunction',
    {
        _execute => sub ( $functions, $entry, $bound ) {
            if ( $entry->{function} =~ /forum_protocol_signature/msx ) {
                push @signature_reads, $entry->{function};
            }
            return $execute->( $functions, $entry, $bound );
        },
    },
    sub {
        return $c->gp_archive->spool( 'thread', $thread,
            GPForum::Service::Forum::Viewer->anonymous );
    }
);
my $mbox = path( $spool->filename )->slurp;
is( scalar( () = $mbox =~ /^From[ ]gpforum\@/gmsx ),
    $ALL_POSTS, 'archive includes every post beyond the first page' );
is( scalar( grep { /signatures_v/msx } @signature_reads ),
    $SIGNATURE_PAGES, 'the signatures of each page of posts are one call' );
is( scalar( grep { /signature_v/msx } @signature_reads ),
    0, 'and none is read post by post' );
like(
    $mbox,
    qr/X-GPForum-Signature-Status:[ ]unsigned/msx,
    'legacy posts are honestly identified as unsigned'
);
my $attestor = GPForum::Service::Forum::PostAttestor->new(
    schema => $c->gp_schema,
    signer => $c->gp_post_signer
);
my $attested = $attestor->run;
ok( $attested->{signed} >= $LEGACY_BATCH_SIZE,
    'legacy revisions are attested in multiple bounded batches' );
is( $attestor->run->{signed},
    0, 'a repeated attestation does not overwrite existing signatures' );
$spool = $c->gp_archive->spool( 'thread', $thread,
    GPForum::Service::Forum::Viewer->anonymous );
unlike(
    path( $spool->filename )->slurp,
    qr/X-GPForum-Signature-Status:[ ]unsigned/msx,
    'backfilled thread exports only verified signed posts'
);
$dbh->do(
    q{UPDATE posts SET visibility='private' WHERE thread_id=? AND position=100},
    undef, $thread
);
$dbh->do(
q{UPDATE posts SET moderation_state='hidden' WHERE thread_id=? AND position=101},
    undef, $thread
);
$dbh->do(
    q{UPDATE posts SET deleted_at=now() WHERE thread_id=? AND position=102},
    undef, $thread );
$spool = $c->gp_archive->spool( 'thread', $thread,
    GPForum::Service::Forum::Viewer->anonymous );
$mbox = path( $spool->filename )->slurp;
is( scalar( () = $mbox =~ /^From[ ]gpforum\@/gmsx ),
    $PUBLIC_POSTS, 'private hidden and deleted posts are excluded' );
$t->get_ok("/c/$category/archive.mbox")
  ->status_is($HTTP_OK)
  ->content_like(qr/Opening[ ]post/msx);
$dbh->do( q{UPDATE categories SET visibility='members' WHERE category_id=?},
    undef, $category );
$t->get_ok("/t/$thread/archive.mbox")->status_is($HTTP_NOT_FOUND);
$t->get_ok("/c/$category/archive.mbox")->status_is($HTTP_NOT_FOUND);
$t->get_ok("/p/$reply_id/signature")->status_is($HTTP_NOT_FOUND);
$dbh->do( q{UPDATE categories SET visibility='public' WHERE category_id=?},
    undef, $category );

my $token = $c->gp_mail_reply_tokens->issue( $thread, $user, 'notification-1' );
my $raw   = Email::MIME->create(
    header_str => [
        From          => 'perf_user_1@example.invalid',
        To            => 'reply@forum.example',
        'In-Reply-To' => $token,
        'Message-ID'  => '<delivery-1@example.net>'
    ],
    attributes => {
        content_type => 'text/plain',
        charset      => 'UTF-8',
        encoding     => 'quoted-printable'
    },
    body_str => 'Via email'
)->as_string;
my $inbox    = $c->gp_mail_in;
my $received = $inbox->receive($raw);
ok( $received->{ok}, 'email uses real verified recipient and normal workflow' )
  or diag explain $received;
my $before =
  $dbh->selectrow_array( 'SELECT count(*) FROM posts WHERE thread_id=?',
    undef, $thread );
my $replayed = $inbox->receive($raw);
ok( $replayed->{ok} && $replayed->{idempotent},
    'MTA redelivery is idempotent' );
is(
    $dbh->selectrow_array(
        'SELECT count(*) FROM posts WHERE thread_id=?',
        undef, $thread
    ),
    $before,
    'redelivery makes no extra post'
);
$dbh->do(
q{UPDATE threads SET locked_at=now(),moderation_state='locked' WHERE thread_id=?},
    undef, $thread
);
my $locked = $inbox->receive( $raw =~ s/delivery-1/delivery-2/rmsx );
ok( !$locked->{ok}, 'reply by email respects locked threads' );

my $gemini = GPForum::Service::Discovery::Gemini->new(
    hostname             => 'forum.example',
    category_reader      => $c->gp_category_reader,
    thread_reader        => $c->gp_thread_reader,
    thread_detail_reader => $c->gp_thread_detail_reader
);
like( $gemini->response("gemini://forum.example/t/$thread\r\n"),
    qr/\A20/msx, 'Gemini reads production thread reader' );
$dbh->do( q{UPDATE categories SET visibility='private' WHERE category_id=?},
    undef, $category );
like( $gemini->response("gemini://forum.example/t/$thread\r\n"),
    qr/\A51/msx, 'Gemini cannot read a private category' );
$dbh->do( q{UPDATE categories SET visibility='public' WHERE category_id=?},
    undef, $category );

my $backup = GPForum::Service::Operations::Backup->new(
    config => GPForum::Config->from_environment,
    root   => "$scratch/code"
);
my $taken = $backup->take( "$scratch/backups", { verify => 1 } );
is( $taken->{manifest}{verification}{status},
    'verified', 'backup is restored before it claims verification' );
is_deeply(
    $taken->{manifest}{verification}{source_counts},
    $taken->{manifest}{verification}{restored_counts},
    'all snapshot counts survive restore'
);
ok( $taken->{manifest}{verification}{temporary_database_removed},
    'verification drops temporary database' );
is(
    $dbh->selectrow_array(
q{SELECT count(*) FROM pg_database WHERE datname LIKE 'gpforum_verify_%'}
    ),
    0,
    'no verification database remains'
);

my $source_posts = $dbh->selectrow_array('SELECT count(*) FROM posts');
my $restore =
  GPForum::Service::Operations::StagingDrill::PgTools->can('restore_database');
with_replaced_subs(
    'GPForum::Service::Operations::StagingDrill::PgTools',
    {
        restore_database => sub ( $tools, $dsn, $dump ) {
            $restore->( $tools, $dsn, $dump );
            croak 'test refuses any non-verification database'
              if $dsn !~ /dbname=gpforum_verify_/msx;
            my $copy = DBI->connect(
                $dsn,
                $ENV{GPFORUM_DATABASE_USER},
                $ENV{GPFORUM_DATABASE_PASSWORD},
                { RaiseError => 1, PrintError => 0 }
            );
            $copy->do('TRUNCATE TABLE public.posts CASCADE');
            $copy->disconnect;
        },
    },
    sub {
        like(
            exception { $backup->take( "$scratch/backups", { verify => 1 } ) },
            qr/mismatch/msx,
            'a restore with missing rows fails verification'
        );
    }
);
is(
    $dbh->selectrow_array(
q{SELECT count(*) FROM pg_database WHERE datname LIKE 'gpforum_verify_%'}
    ),
    0,
    'verification also drops the database after a count mismatch'
);
is( $dbh->selectrow_array('SELECT count(*) FROM posts'),
    $source_posts, 'failed verification leaves the source unchanged' );

subtest 'Gemini CLI serves one request over TLS 1.2' => \&_gemini_tls;
$c->gp_schema->storage->disconnect;
done_testing();

sub _gemini_tls {
    my $cert = "$scratch/gemini.crt";
    my $key  = "$scratch/gemini.key";
    my $log  = "$scratch/gemini.log";
    _generate_certificate( $cert, $key, $log );
    ok( -f $key && -f $cert, 'a real test certificate and key were generated' )
      or return;
    my $reservation = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1',
        LocalPort => 0,
        Listen    => 1
    ) or croak 'cannot reserve TLS port';
    my $port = $reservation->sockport;
    close $reservation or croak 'cannot release TLS port';
    my $pid = _spawn_gemini( $port, $cert, $key, $log );
    my $failure;
    try {
        my $client;
        for ( 1 .. $TLS_START_ATTEMPTS ) {
            $client = IO::Socket::SSL->new(
                PeerAddr        => '127.0.0.1',
                PeerPort        => $port,
                SSL_verify_mode => 0,
                SSL_version     => 'TLSv1_2',
                Timeout         => $TLS_CONNECT_TIMEOUT
            );
            last if $client;
            Time::HiRes::sleep($TLS_RETRY_DELAY);
        }
        ok( $client, 'Gemini listener accepts TLS 1.2' );
        if ($client) {
            print {$client} "gemini://forum.example:$port/t/$thread\r\n"
              or croak 'cannot send Gemini request';
            my $response =
              do { local $INPUT_RECORD_SEPARATOR = undef; <$client> };
            like(
                $response,
                qr/\A20[ ]text\/gemini.*Portable[ ]community/msx,
                'TLS response contains the public thread'
            );
            close $client or croak 'cannot close Gemini client';
        }
        else { diag path($log)->slurp; }
    }
    catch ($error) { $failure = $error; };
    kill 'TERM', $pid;
    waitpid $pid, 0;
    if ( defined $failure ) { fail("Gemini TLS test: $failure"); }
    return;
}

sub _generate_certificate ( $cert, $key, $log ) {
    my $cert_pid = fork;
    croak 'cannot fork certificate tool' if !defined $cert_pid;
    if ( !$cert_pid ) {
        _redirect_child($log);
        exec 'openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
          '-keyout', $key, '-out', $cert, '-subj', '/CN=forum.example',
          '-days', '1'
          or _exit(1);
    }
    waitpid $cert_pid, 0;
    return;
}

sub _spawn_gemini ( $port, $cert, $key, $log ) {
    my $pid = fork;
    croak 'cannot fork Gemini service' if !defined $pid;
    if ( !$pid ) {
        _redirect_child($log);
        exec {$EXECUTABLE_NAME} $EXECUTABLE_NAME, 'bin/gpforum', 'gemini',
          '--port', $port,
          '--hostname', 'forum.example', '--cert', $cert, '--key', $key
          or _exit(1);
    }
    return $pid;
}

sub _redirect_child ($log) {
    open STDOUT, q{>>}, $log     or _exit(1);
    open STDERR, q{>&}, \*STDOUT or _exit(1);
    return;
}

1;
