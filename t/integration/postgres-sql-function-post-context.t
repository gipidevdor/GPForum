# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(carp croak);
use Const::Fast;
use English qw(-no_match_vars);
use JSON::MaybeXS;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::SqlFunctionCatalogue;
use GPForum::Schema;
use GPForum::Service::Community::MentionStore;
use GPForum::Service::Forum::CategoryReader;
use GPForum::Service::Forum::PostComposer;
use GPForum::Service::Forum::PostReader;
use GPForum::Service::Forum::PostStore;
use GPForum::Service::Forum::PostingWorkflow;
use GPForum::Service::Forum::ThreadComposer;
use GPForum::Service::Forum::ThreadDetailReader;
use GPForum::Service::Forum::ThreadStore;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Operations::ApiRole;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::LogLines;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';
const my $CONTEXT_CALLS => 1;
const my $WRITE_CALLS   => 2;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to test combined post preflight';
}

my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $admin    = $database->dbh;
my $owner    = "gpf_post_owner_$PROCESS_ID";
my $runtime  = "gpf_post_runtime_$PROCESS_ID";
my $password = GPForum::Infrastructure::Id->new->uuid;
my $schema;

END {
    if ($schema) { $schema->storage->disconnect; }
    if ( $admin && $admin->{Active} ) {
        for my $role ( $runtime, $owner ) {
            try {
                $admin->do(
                    'DROP OWNED BY ' . $admin->quote_identifier($role) );
                $admin->do(
                    'DROP ROLE IF EXISTS ' . $admin->quote_identifier($role) );
            }
            catch ($error) { carp $error; };
        }
    }
    undef $database;
}

for my $role ( $owner, $runtime ) {
    $admin->do( 'CREATE ROLE '
          . $admin->quote_identifier($role)
          . ' LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT PASSWORD '
          . $admin->quote($password) );
}
my $quoted_owner = $admin->quote_identifier($owner);
$admin->do("GRANT USAGE ON SCHEMA api, public TO $quoted_owner");
$admin->do("GRANT ALL ON ALL TABLES IN SCHEMA public TO $quoted_owner");
$admin->do("GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO $quoted_owner");
$admin->do(
    "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api, public TO $quoted_owner");
my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new;
for my $name ( @{ $catalogue->names } ) {
    my $entry = $catalogue->function($name);
    $admin->do( 'ALTER FUNCTION '
          . $entry->{function} . '('
          . join( ', ', @{ $entry->{types} } )
          . ") OWNER TO $quoted_owner" );
}
GPForum::Service::Operations::ApiRole->new( dbh => $admin )
  ->provision($runtime);
$schema = GPForum::Schema->connect( $database->dsn, $runtime, $password,
    { RaiseError => 1, PrintError => 0, AutoCommit => 1 } );
my $dbh = $schema->storage->dbh;
is( scalar $dbh->selectrow_array('SELECT current_user'),
    $runtime, 'the preflight uses a distinct restricted login' );
my $denied;
try { $dbh->selectrow_array('SELECT post_id FROM public.posts LIMIT 1'); }
catch ($error) { $denied = "$error"; };
like( $denied, qr/permission[ ]denied/msx, 'direct table access stays denied' );

my ( $post, $thread, $actor, $category, $space ) = $admin->selectrow_array(
'SELECT p.post_id, p.thread_id, p.author_user_id, t.category_id, c.space_id '
      . 'FROM posts p JOIN threads t USING(thread_id) JOIN categories c USING(category_id) '
      . 'WHERE p.position > 1 AND p.deleted_at IS NULL ORDER BY p.post_id LIMIT 1'
);
my ($other) = $admin->selectrow_array(
    'SELECT id FROM users WHERE id <> ? ORDER BY id LIMIT 1',
    undef, $actor );
my $viewer =
  GPForum::Service::Forum::Viewer->new( user_id => $actor, member => 1 );
my $function = _workflow($schema);
my $legacy   = _workflow( $database->schema, 1 );
_reset_fixture();

my $context = GPForum::Infrastructure::SqlFunction->for_schema($schema)
  ->row( 'forum_post_context', { post_id => $post } );
my $old_post = $legacy->post_reader->find_post($post);
my $old_head = $legacy->thread_detail_reader->find_thread_row($thread);
is_deeply(
    $context->{post},
    { $old_post->get_columns },
    'combined context preserves every legacy post column and timestamp'
);
is_deeply(
    $context->{thread},
    { $old_head->get_columns },
    'combined context preserves the legacy head columns and scalar types'
);
$admin->do( 'UPDATE threads SET pinned = true WHERE thread_id = ?',
    undef, $thread );
my $pinned_context = GPForum::Infrastructure::SqlFunction->for_schema($schema)
  ->row( 'forum_post_context', { post_id => $post } );
is_deeply(
    $pinned_context->{thread},
    { $legacy->thread_detail_reader->find_thread_row($thread)->get_columns },
    'a pinned head preserves the legacy boolean representation'
);
$admin->do( 'UPDATE threads SET pinned = false WHERE thread_id = ?',
    undef, $thread );

# Compare the exact domain refusal and row with the old two-reader path.
# The new path must not bypass an unreadable category, even for a post author.
my @cases = (
    { name => 'public author', expected => undef },
    {
        name           => 'foreign author',
        author_user_id => $other,
        expected       => 'not the post author'
    },
    {
        name  => 'private category',
        setup => sub {
            $admin->do(
                'UPDATE categories SET visibility = ? WHERE category_id = ?',
                undef, 'private', $category );
        },
        expected => 'thread not found'
    },
    {
        name  => 'granted private category',
        setup => sub {
            $admin->do(
                'UPDATE categories SET visibility = ? WHERE category_id = ?',
                undef, 'private', $category );
        },
        viewer => GPForum::Service::Forum::Viewer->new(
            user_id      => $actor,
            member       => 1,
            category_ids => [$category]
        ),
        expected => undef
    },
    {
        name  => 'private space',
        setup => sub {
            $admin->do( 'UPDATE spaces SET visibility = ? WHERE space_id = ?',
                undef, 'private', $space );
        },
        expected => 'thread not found'
    },
    {
        name  => 'anonymous in members category',
        setup => sub {
            $admin->do(
                'UPDATE categories SET visibility = ? WHERE category_id = ?',
                undef, 'members', $category );
        },
        viewer   => GPForum::Service::Forum::Viewer->anonymous,
        expected => 'thread not found'
    },
    {
        name  => 'member in members category',
        setup => sub {
            $admin->do(
                'UPDATE categories SET visibility = ? WHERE category_id = ?',
                undef, 'members', $category );
        },
        expected => undef
    },
    {
        name  => 'locked thread',
        setup => sub {
            $admin->do(
                'UPDATE threads SET locked_at = now() WHERE thread_id = ?',
                undef, $thread );
        },
        expected => 'thread is locked'
    },
    {
        name  => 'hidden thread',
        setup => sub {
            $admin->do(
                'UPDATE threads SET moderation_state = ? WHERE thread_id = ?',
                undef, 'hidden', $thread );
        },
        expected => 'thread not found'
    },
    {
        name  => 'hidden post',
        setup => sub {
            $admin->do(
'UPDATE posts SET hidden_at = now(), moderation_state = ? WHERE post_id = ?',
                undef, 'hidden', $post
            );
        },
        expected => 'post is hidden'
    },
    {
        name  => 'deleted post edit',
        setup => sub {
            $admin->do( 'UPDATE posts SET deleted_at = now() WHERE post_id = ?',
                undef, $post );
        },
        expected => 'post not found'
    },
    {
        name  => 'deleted post restore',
        rule  => 'restore_refusal',
        setup => sub {
            $admin->do( 'UPDATE posts SET deleted_at = now() WHERE post_id = ?',
                undef, $post );
        },
        expected => undef
    },
    {
        name     => 'live post restore',
        rule     => 'restore_refusal',
        expected => 'post not found'
    },
    {
        name     => 'missing post',
        post_id  => GPForum::Infrastructure::Id->new->uuid,
        expected => 'post not found'
    },
    {
        name     => 'malformed post',
        post_id  => 'not-a-uuid',
        calls    => 0,
        expected => 'post not found'
    },
    {
        name     => 'empty post',
        post_id  => q{},
        calls    => 0,
        expected => 'post not found'
    },
);
for my $case (@cases) {
    _reset_fixture();
    if ( $case->{setup} ) {
        $case->{setup}->();
    }
    my $input = {
        post_id        => $post,
        author_user_id => $actor,
        viewer         => $viewer,
        %{$case}
    };
    my $rule = $case->{rule} // 'edit_refusal';
    my ( $actual, $sent ) = _trace(
        $schema,
        sub {
            return [ $function->_post_checked( $input, $rule ) ];
        }
    );
    my @previous = $legacy->_post_checked( $input, $rule );
    is_deeply( $actual->[1], $previous[1],
        "$case->{name}: legacy refusal preserved" );
    is( $actual->[1] ? $actual->[1]{error} : undef,
        $case->{expected}, "$case->{name}: expected domain result" );
    is(
        scalar @{$sent},
        $case->{calls} // $CONTEXT_CALLS,
        "$case->{name}: at most one preflight invocation"
    );
    if ( $actual->[0] ) {
        is_deeply(
            { $actual->[0]->get_columns },
            { $previous[0]->get_columns },
            "$case->{name}: post row unchanged"
        );
    }
}

_reset_fixture();
my $request = {
    post_id        => $post,
    author_user_id => $actor,
    viewer         => $viewer,
    body_source    => 'Combined preflight body',
    command_id     => 'context-edit'
};
my ( $edited, $edit_calls ) =
  _trace( $schema, sub { return $function->edit_post($request); } );
ok( $edited->{ok},
    'the restricted login edits through the normal command workflow' );
is( scalar @{$edit_calls},
    $WRITE_CALLS, 'edit costs one preflight plus one atomic command' );
like(
    $edit_calls->[0],
    qr/api[.]forum_post_context_v2/msx,
    'first call is the combined context'
);
like(
    $edit_calls->[1],
    qr/api[.]forum_write_command_v2/msx,
    'second call retains the atomic write'
);
my $snapshot = _snapshot();
my ( $replay, $replay_calls ) =
  _trace( $schema, sub { return $function->edit_post($request); } );
ok( $replay->{ok} && $replay->{idempotent}, 'the same command still replays' );
is( scalar @{$replay_calls},
    $WRITE_CALLS, 'replay retains the bounded call count' );
is_deeply( _snapshot(), $snapshot,
    'replay changes no body, revision, event, outbox, audit or counter' );
my $conflict =
  $function->edit_post( { %{$request}, body_source => 'Different request' } );
is( $conflict->{status}, 'conflict',
    'a changed request under the command id conflicts' );
is_deeply( _snapshot(), $snapshot, 'a conflict writes nothing' );

for my $method (qw(delete_post restore_post)) {
    my ( $result, $calls ) = _trace(
        $schema,
        sub {
            return $function->$method(
                {
                    post_id        => $post,
                    author_user_id => $actor,
                    viewer         => $viewer,
                    command_id     => "context-$method"
                }
            );
        }
    );
    ok( $result->{ok}, "$method succeeds through the restricted login" );
    is( scalar @{$calls}, $WRITE_CALLS, "$method also uses two calls" );
}
my $invalid = $function->edit_post(
    { %{$request}, body_source => q{}, command_id => 'context-invalid' } );
is( $invalid->{status}, 'invalid', 'body validation stays in the composer' );
is(
    $invalid->{prepared}{errors}{body_source},
    'body is required',
    'body validation error is preserved'
);
my ( $missing, $missing_calls ) = _trace(
    $schema,
    sub {
        return $function->delete_post(
            {
                %{$request},
                post_id    => 'not-a-uuid',
                command_id => 'context-invalid-id'
            }
        );
    }
);
is( $missing->{status}, 'not_found', 'malformed ids still answer not found' );
is( scalar @{$missing_calls},
    $CONTEXT_CALLS, 'malformed id sends only the refusal command' );
_reset_fixture();
$admin->do( 'UPDATE categories SET visibility = ? WHERE category_id = ?',
    undef, 'private', $category );
my $before_acl = _snapshot();
my $forbidden  = $function->delete_post(
    { %{$request}, command_id => 'context-private-delete' } );
is( $forbidden->{status}, 'not_found',
    'the author cannot write across an unreadable category' );
is(
    $forbidden->{error},
    'thread not found',
    'unreadable category does not disclose its thread'
);
is_deeply( _snapshot(), $before_acl,
    'unreadable context records no domain mutation' );

done_testing();

sub _reset_fixture {
    $admin->do(
'UPDATE threads SET visibility = ?, moderation_state = ?, locked_at = NULL, deleted_at = NULL WHERE thread_id = ?',
        undef, 'public', 'visible', $thread
    );
    $admin->do(
'UPDATE posts SET author_user_id = ?, visibility = ?, moderation_state = ?, hidden_at = NULL, deleted_at = NULL WHERE post_id = ?',
        undef, $actor, 'public', 'visible', $post
    );
    $admin->do( 'UPDATE categories SET visibility = ? WHERE category_id = ?',
        undef, 'public', $category );
    $admin->do( 'UPDATE spaces SET visibility = ? WHERE space_id = ?',
        undef, 'public', $space );
    return;
}

sub _workflow ( $given, $old = 0 ) {
    my %path = $old ? ( functions => undef ) : ();
    my $posts =
      GPForum::Service::Forum::PostReader->new( schema => $given, %path );
    return GPForum::Service::Forum::PostingWorkflow->new(
        logger          => GPForum::Test::LogLines->new,
        category_reader => GPForum::Service::Forum::CategoryReader->new(
            schema => $given,
            %path
        ),
        command_idempotency =>
          GPForum::Service::Operations::CommandIdempotency->new(
            schema => $given,
            %path
          ),
        mention_store => GPForum::Service::Community::MentionStore->new(
            schema => $given,
            %path
        ),
        post_composer => GPForum::Service::Forum::PostComposer->new,
        post_reader   => $posts,
        post_store    =>
          GPForum::Service::Forum::PostStore->new( schema => $given, %path ),
        thread_composer      => GPForum::Service::Forum::ThreadComposer->new,
        thread_detail_reader =>
          GPForum::Service::Forum::ThreadDetailReader->new(
            schema      => $given,
            post_reader => $posts,
            %path
          ),
        thread_store =>
          GPForum::Service::Forum::ThreadStore->new( schema => $given, %path ),
        %path,
    );
}

sub _trace ( $given, $code ) {
    my @sent;
    my $storage = $given->storage;
    $storage->debugcb(
        sub { my ( undef, $statement ) = @_; push @sent, $statement; return; }
    );
    $storage->debug(1);
    my ( $result, $error );
    try { $result = $code->(); }
    catch ($caught) { $error = $caught; };
    $storage->debug(0);
    $storage->debugcb(undef);
    croak $error if $error;
    return ( $result, \@sent );
}

sub _snapshot {
    my $json = JSON::MaybeXS->new( canonical => 1 );
    my %tables;
    for my $table (
        qw(posts post_bodies post_revisions thread_counters event_log outbox_messages audit_log)
      )
    {
        my $rows =
          $admin->selectall_arrayref( "SELECT * FROM $table", { Slice => {} } );
        $tables{$table} =
          [ sort { $json->encode($a) cmp $json->encode($b) } @{$rows} ];
    }
    return \%tables;
}

1;
