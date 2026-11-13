# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Mojo::JSON   qw(encode_json);
use Scalar::Util qw(blessed);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Forum::PostStore;
use GPForum::Service::Forum::PostingCommand;
use GPForum::Service::Forum::PostingWorkflow;
use GPForum::Service::Forum::ThreadStore;
use GPForum::Test::CommandIdempotency;
use GPForum::Test::PostingDouble;
use GPForum::Test::PostingFunctions;

our $VERSION = '0.001';

# What the forum's write path hands to the command log, captured as
# canonical JSON (keys sorted). The command log keeps a request fingerprint
# and a response for every command, and replays the response for a repeat
# of the same request: a fingerprint that changes turns every retry of a
# command recorded before the change into a conflict, and a response or
# replay that changes gives a retry a different answer than the first run.
# The log is api.forum_write_command's and api.forum_create_reply's (ADR
# 0177), stood in for by GPForum::Test::PostingFunctions; the event
# envelopes are the functions' too, and are pinned there.
#
# A case missing from __DATA__ fails and notes its JSON, which is how the
# lines below were written.

my %golden = map { split m/\t/msx, $_, 2 } grep { length }
  map { s/\s+\z//msxr } <DATA>;

my %seen;

sub golden ( $name, $value ) {
    $seen{$name} = 1;
    my $json = encode_json( _plain($value) );
    if ( !exists $golden{$name} ) {
        fail("$name has a golden line");
        note("$name\t$json");
        return;
    }
    is( $json, $golden{$name}, $name );

    return;
}

# The input of every command, padded so the fingerprint shows what is
# trimmed, with fields no fingerprint keeps (viewer, edit_reason) set so it
# shows what is left out.
my %INPUT = (
    'thread.create' => {
        author_user_id => ' user-1 ',
        body_source    => " Opening body \n",
        category_id    => ' general ',
        title          => ' Hello ',
        visibility     => ' public ',
    },
    'reply.create' => {
        author_user_id => ' user-1 ',
        body_source    => ' Reply body ',
        thread_id      => ' thread-1 ',
        visibility     => q{},
    },
    'thread.edit' => {
        author_user_id => 'user-1',
        thread_id      => ' thread-1 ',
        title          => ' New title ',
    },
    'thread.move' => {
        author_user_id => 'user-1',
        category_id    => ' other ',
        thread_id      => 'thread-1',
    },
    'thread.delete' => {
        author_user_id => 'user-1',
        thread_id      => ' thread-1 ',
    },
    'thread.restore' => {
        author_user_id => 'user-1',
        thread_id      => 'thread-deleted',
    },
    'post.edit' => {
        author_user_id => 'user-1',
        body_source    => ' Edited body ',
        edit_reason    => 'typo',
        post_id        => ' post-1 ',
    },
    'post.delete' => {
        author_user_id => 'user-1',
        post_id        => ' post-1 ',
    },
    'post.restore' => {
        author_user_id => 'user-1',
        post_id        => 'post-deleted',
    },
);

my %METHOD = (
    'post.delete'    => 'delete_post',
    'post.edit'      => 'edit_post',
    'post.restore'   => 'restore_post',
    'reply.create'   => 'create_reply',
    'thread.create'  => 'create_thread',
    'thread.delete'  => 'delete_thread',
    'thread.edit'    => 'edit_thread',
    'thread.move'    => 'move_thread',
    'thread.restore' => 'restore_thread',
);

# How each command is made to take each path: the input it is changed with
# and the double that is told to refuse or die.
my %PATH = (
    ok        => {},
    invalid   => { composer => 'invalid' },
    not_found => {
        input => {
            'post.delete'    => { post_id     => 'post-gone' },
            'post.edit'      => { post_id     => 'post-gone' },
            'post.restore'   => { post_id     => 'post-1' },
            'reply.create'   => { thread_id   => 'thread-gone' },
            'thread.create'  => { category_id => 'missing' },
            'thread.delete'  => { thread_id   => 'thread-gone' },
            'thread.edit'    => { thread_id   => 'thread-gone' },
            'thread.move'    => { category_id => 'missing' },
            'thread.restore' => { thread_id   => 'thread-1' },
        },
    },
    forbidden => {
        input => {
            'post.delete'    => { author_user_id => 'user-2' },
            'post.edit'      => { author_user_id => 'user-2' },
            'post.restore'   => { author_user_id => 'user-2' },
            'reply.create'   => { thread_id      => 'thread-locked' },
            'thread.delete'  => { author_user_id => 'user-2' },
            'thread.edit'    => { author_user_id => 'user-2' },
            'thread.move'    => { author_user_id => 'user-2' },
            'thread.restore' => { author_user_id => 'user-2' },
        },
    },
    store_refusal => { store => 'refuse' },
    store_failure => { store => 'die' },
);

my %HAS_COMPOSER =
  map { $_ => 1 }
  qw(thread.create reply.create thread.edit thread.move post.edit);

for my $type ( sort keys %METHOD ) {
    for my $path ( sort keys %PATH ) {
        next if $path eq 'invalid' && !$HAS_COMPOSER{$type};
        next
          if $path eq 'forbidden' && !$PATH{forbidden}{input}{$type};
        _command_case( $type, $path );
    }
}

sub _command_case ( $type, $path ) {
    my $spec  = $PATH{$path};
    my $input = {
        %{ $INPUT{$type} },
        %{ $spec->{input}{$type} // {} },
        command_id => " command-$type ",
        viewer     => undef,
    };
    my $method = $METHOD{$type};
    my ( $workflow, $functions ) = _workflow($spec);
    my $result = $workflow->$method( { %{$input} } );
    golden( "$type $path request", _request( $functions, $type, $input ) );
    golden( "$type $path result",  $result );
    my $logged = $functions->log->{"command-$type"};
    golden( "$type $path response", $logged ? $logged->{response} : undef );
    golden( "$type $path replay",   $workflow->$method( { %{$input} } ) );

    return;
}

# A value with its result rows as the column hashes they hold.
sub _plain ($value) {
    return { $value->get_columns }
      if blessed $value && $value->can('get_columns');
    return { map { $_ => _plain( $value->{$_} ) } keys %{$value} }
      if ref $value eq 'HASH';
    return [ map { _plain($_) } @{$value} ] if ref $value eq 'ARRAY';

    return $value;
}

# The command log's row as the call hands it over, with the request its
# hash is the fingerprint of.
sub _request ( $functions, $type, $input ) {
    my ($call) =
      grep { $_->[0] ne 'forum_post_context' } @{ $functions->calls };
    return undef if !$call;
    my $values = $call->[1];
    my $log    = $values->{log} // $values;

    return {
        actor_id        => $log->{actor_id},
        command_id      => $log->{idempotency_key},
        command_type    => $log->{command_type},
        idempotency_key => $log->{idempotency_key},
        request => GPForum::Service::Forum::PostingCommand->new->request(
            $type, $input
        ),
    };
}

golden( 'missing command id',
    ( _workflow( {} ) )[0]->create_reply( { %{ $INPUT{'reply.create'} } } ) );
my ($conflicted) = _workflow( {} );
$conflicted->edit_post( { %{ $INPUT{'post.edit'} }, command_id => 'c-1' } );
golden(
    'command log conflict',
    $conflicted->edit_post(
        {
            %{ $INPUT{'post.edit'} },
            body_source => 'Another body',
            command_id  => 'c-1'
        }
    )
);

for my $name ( sort keys %golden ) {
    ok( $seen{$name}, "golden line $name is still checked" );
}

done_testing();

# The workflow on one double for every collaborator, its writes taken by
# the posting functions over it: the workflow and the functions.
sub _workflow ($spec) {
    my $double = GPForum::Test::PostingDouble->new(
        composer => $spec->{composer},
        store    => $spec->{store},
    );
    my $functions = GPForum::Test::PostingFunctions->new(
        reader => $double,
        sink   => $double
    );

    return (
        GPForum::Service::Forum::PostingWorkflow->new(
            category_reader     => $double,
            command_idempotency => GPForum::Test::CommandIdempotency->new,
            mention_store       => $double,
            post_composer       => $double,
            post_store          => GPForum::Service::Forum::PostStore->new(
                functions => $functions,
                schema    => {}
            ),
            thread_composer      => $double,
            thread_detail_reader => $double,
            thread_store         => GPForum::Service::Forum::ThreadStore->new(
                functions => $functions,
                schema    => {}
            ),
        ),
        $functions
    );
}

1;

__DATA__
command log conflict	{"error":"idempotency key was already used for another request","ok":0,"prepared":null,"status":"conflict","stored":null}
missing command id	{"error":null,"ok":0,"prepared":{"errors":{"command_id":"command_id is required"},"ok":0,"values":{"author_user_id":" user-1 ","body_source":" Reply body ","thread_id":" thread-1 ","visibility":""}},"status":"invalid","stored":null}
post.delete forbidden replay	{"error":"not the post author","idempotent":1,"ok":0,"prepared":null,"status":"forbidden","stored":null}
post.delete forbidden request	{"actor_id":"user-2","command_id":"command-post.delete","command_type":"post.delete","idempotency_key":"command-post.delete","request":{"author_user_id":"user-2","post_id":"post-1"}}
post.delete forbidden response	{"error":"not the post author","ok":0,"status":"forbidden"}
post.delete forbidden result	{"error":"not the post author","ok":0,"prepared":null,"status":"forbidden","stored":null}
post.delete not_found replay	{"error":"post not found","idempotent":1,"ok":0,"prepared":null,"status":"not_found","stored":null}
post.delete not_found request	{"actor_id":"user-1","command_id":"command-post.delete","command_type":"post.delete","idempotency_key":"command-post.delete","request":{"author_user_id":"user-1","post_id":"post-gone"}}
post.delete not_found response	{"error":"post not found","ok":0,"status":"not_found"}
post.delete not_found result	{"error":"post not found","ok":0,"prepared":null,"status":"not_found","stored":null}
post.delete ok replay	{"error":null,"idempotent":1,"ok":1,"prepared":null,"status":"ok","stored":{"ok":1,"post":{"post_id":" post-1 ","thread_id":"thread-1"}}}
post.delete ok request	{"actor_id":"user-1","command_id":"command-post.delete","command_type":"post.delete","idempotency_key":"command-post.delete","request":{"author_user_id":"user-1","post_id":"post-1"}}
post.delete ok response	{"ok":1,"post_id":" post-1 ","status":"ok","thread_id":"thread-1"}
post.delete ok result	{"error":null,"ok":1,"prepared":null,"status":"ok","stored":{"ok":1,"post":{"author_user_id":"user-1","post_id":" post-1 ","thread_id":"thread-1"}}}
post.delete store_failure replay	{"error":"post store failed","ok":0,"prepared":null,"status":"failed","stored":null}
post.delete store_failure request	{"actor_id":"user-1","command_id":"command-post.delete","command_type":"post.delete","idempotency_key":"command-post.delete","request":{"author_user_id":"user-1","post_id":"post-1"}}
post.delete store_failure response	null
post.delete store_failure result	{"error":"post store failed","ok":0,"prepared":null,"status":"failed","stored":null}
post.delete store_refusal replay	{"error":"post not found","idempotent":1,"ok":0,"prepared":null,"status":"not_found","stored":null}
post.delete store_refusal request	{"actor_id":"user-1","command_id":"command-post.delete","command_type":"post.delete","idempotency_key":"command-post.delete","request":{"author_user_id":"user-1","post_id":"post-1"}}
post.delete store_refusal response	{"error":"post not found","ok":0,"status":"not_found"}
post.delete store_refusal result	{"error":"post not found","ok":0,"prepared":null,"status":"not_found","stored":null}
post.edit forbidden replay	{"error":"not the post author","idempotent":1,"ok":0,"prepared":null,"status":"forbidden","stored":null}
post.edit forbidden request	{"actor_id":"user-2","command_id":"command-post.edit","command_type":"post.edit","idempotency_key":"command-post.edit","request":{"author_user_id":"user-2","body_hash":"a59675f5bf314a572c5ac85c448c8f05aa5559624c04781993985b60d892d795","post_id":"post-1"}}
post.edit forbidden response	{"error":"not the post author","ok":0,"status":"forbidden"}
post.edit forbidden result	{"error":"not the post author","ok":0,"prepared":null,"status":"forbidden","stored":null}
post.edit invalid replay	{"error":null,"idempotent":1,"ok":0,"prepared":{"errors":{"field":"field is invalid"},"ok":0,"values":{"body_hash":"a59675f5bf314a572c5ac85c448c8f05aa5559624c04781993985b60d892d795","body_source":" Edited body ","edit_reason":"typo","editor_user_id":"user-1","idempotency_key":"command-post.edit","post_id":" post-1 ","thread_id":"thread-1"}},"status":"invalid","stored":null}
post.edit invalid request	{"actor_id":"user-1","command_id":"command-post.edit","command_type":"post.edit","idempotency_key":"command-post.edit","request":{"author_user_id":"user-1","body_hash":"a59675f5bf314a572c5ac85c448c8f05aa5559624c04781993985b60d892d795","post_id":"post-1"}}
post.edit invalid response	{"errors":{"field":"field is invalid"},"ok":0,"status":"invalid","values":{"body_hash":"a59675f5bf314a572c5ac85c448c8f05aa5559624c04781993985b60d892d795","body_source":" Edited body ","edit_reason":"typo","editor_user_id":"user-1","idempotency_key":"command-post.edit","post_id":" post-1 ","thread_id":"thread-1"}}
post.edit invalid result	{"error":null,"ok":0,"prepared":{"errors":{"field":"field is invalid"},"ok":0,"values":{"body_hash":"a59675f5bf314a572c5ac85c448c8f05aa5559624c04781993985b60d892d795","body_source":" Edited body ","edit_reason":"typo","editor_user_id":"user-1","idempotency_key":"command-post.edit","post_id":" post-1 ","thread_id":"thread-1"}},"status":"invalid","stored":null}
post.edit not_found replay	{"error":"post not found","idempotent":1,"ok":0,"prepared":null,"status":"not_found","stored":null}
post.edit not_found request	{"actor_id":"user-1","command_id":"command-post.edit","command_type":"post.edit","idempotency_key":"command-post.edit","request":{"author_user_id":"user-1","body_hash":"a59675f5bf314a572c5ac85c448c8f05aa5559624c04781993985b60d892d795","post_id":"post-gone"}}
post.edit not_found response	{"error":"post not found","ok":0,"status":"not_found"}
post.edit not_found result	{"error":"post not found","ok":0,"prepared":null,"status":"not_found","stored":null}
post.edit ok replay	{"error":null,"idempotent":1,"ok":1,"prepared":null,"status":"ok","stored":{"ok":1,"post":{"post_id":" post-1 ","thread_id":"thread-1"}}}
post.edit ok request	{"actor_id":"user-1","command_id":"command-post.edit","command_type":"post.edit","idempotency_key":"command-post.edit","request":{"author_user_id":"user-1","body_hash":"a59675f5bf314a572c5ac85c448c8f05aa5559624c04781993985b60d892d795","post_id":"post-1"}}
post.edit ok response	{"ok":1,"post_id":" post-1 ","status":"ok","thread_id":"thread-1"}
post.edit ok result	{"error":null,"ok":1,"prepared":{"command":{"body":{"body_source":" Edited body "},"post":{"editor_user_id":"user-1","post_id":" post-1 ","thread_id":"thread-1"}},"ok":1},"status":"ok","stored":{"ok":1,"post":{"author_user_id":"user-1","post_id":" post-1 ","thread_id":"thread-1"}}}
post.edit store_failure replay	{"error":"post store failed","ok":0,"prepared":null,"status":"failed","stored":null}
post.edit store_failure request	{"actor_id":"user-1","command_id":"command-post.edit","command_type":"post.edit","idempotency_key":"command-post.edit","request":{"author_user_id":"user-1","body_hash":"a59675f5bf314a572c5ac85c448c8f05aa5559624c04781993985b60d892d795","post_id":"post-1"}}
post.edit store_failure response	null
post.edit store_failure result	{"error":"post store failed","ok":0,"prepared":null,"status":"failed","stored":null}
post.edit store_refusal replay	{"error":"post is hidden","idempotent":1,"ok":0,"prepared":null,"status":"forbidden","stored":null}
post.edit store_refusal request	{"actor_id":"user-1","command_id":"command-post.edit","command_type":"post.edit","idempotency_key":"command-post.edit","request":{"author_user_id":"user-1","body_hash":"a59675f5bf314a572c5ac85c448c8f05aa5559624c04781993985b60d892d795","post_id":"post-1"}}
post.edit store_refusal response	{"error":"post is hidden","ok":0,"status":"forbidden"}
post.edit store_refusal result	{"error":"post is hidden","ok":0,"prepared":null,"status":"forbidden","stored":null}
post.restore forbidden replay	{"error":"not the post author","idempotent":1,"ok":0,"prepared":null,"status":"forbidden","stored":null}
post.restore forbidden request	{"actor_id":"user-2","command_id":"command-post.restore","command_type":"post.restore","idempotency_key":"command-post.restore","request":{"author_user_id":"user-2","post_id":"post-deleted"}}
post.restore forbidden response	{"error":"not the post author","ok":0,"status":"forbidden"}
post.restore forbidden result	{"error":"not the post author","ok":0,"prepared":null,"status":"forbidden","stored":null}
post.restore not_found replay	{"error":"post not found","idempotent":1,"ok":0,"prepared":null,"status":"not_found","stored":null}
post.restore not_found request	{"actor_id":"user-1","command_id":"command-post.restore","command_type":"post.restore","idempotency_key":"command-post.restore","request":{"author_user_id":"user-1","post_id":"post-1"}}
post.restore not_found response	{"error":"post not found","ok":0,"status":"not_found"}
post.restore not_found result	{"error":"post not found","ok":0,"prepared":null,"status":"not_found","stored":null}
post.restore ok replay	{"error":null,"idempotent":1,"ok":1,"prepared":null,"status":"ok","stored":{"ok":1,"post":{"post_id":"post-deleted","thread_id":"thread-1"}}}
post.restore ok request	{"actor_id":"user-1","command_id":"command-post.restore","command_type":"post.restore","idempotency_key":"command-post.restore","request":{"author_user_id":"user-1","post_id":"post-deleted"}}
post.restore ok response	{"ok":1,"post_id":"post-deleted","status":"ok","thread_id":"thread-1"}
post.restore ok result	{"error":null,"ok":1,"prepared":null,"status":"ok","stored":{"ok":1,"post":{"author_user_id":"user-1","post_id":"post-deleted","thread_id":"thread-1"}}}
post.restore store_failure replay	{"error":"post store failed","ok":0,"prepared":null,"status":"failed","stored":null}
post.restore store_failure request	{"actor_id":"user-1","command_id":"command-post.restore","command_type":"post.restore","idempotency_key":"command-post.restore","request":{"author_user_id":"user-1","post_id":"post-deleted"}}
post.restore store_failure response	null
post.restore store_failure result	{"error":"post store failed","ok":0,"prepared":null,"status":"failed","stored":null}
post.restore store_refusal replay	{"error":"thread not found","idempotent":1,"ok":0,"prepared":null,"status":"not_found","stored":null}
post.restore store_refusal request	{"actor_id":"user-1","command_id":"command-post.restore","command_type":"post.restore","idempotency_key":"command-post.restore","request":{"author_user_id":"user-1","post_id":"post-deleted"}}
post.restore store_refusal response	{"error":"thread not found","ok":0,"status":"not_found"}
post.restore store_refusal result	{"error":"thread not found","ok":0,"prepared":null,"status":"not_found","stored":null}
reply.create forbidden replay	{"error":"thread is locked","idempotent":1,"ok":0,"prepared":null,"status":"forbidden","stored":null}
reply.create forbidden request	{"actor_id":"user-1","command_id":"command-reply.create","command_type":"reply.create","idempotency_key":"command-reply.create","request":{"author_user_id":"user-1","body_hash":"b87e74db2baf019fb26d1a764aa329723024c6be7f13e5a92a60690b301bc3e9","thread_id":"thread-locked","visibility":""}}
reply.create forbidden response	{"error":"thread is locked","ok":0,"status":"forbidden"}
reply.create forbidden result	{"error":"thread is locked","ok":0,"prepared":null,"status":"forbidden","stored":null}
reply.create invalid replay	{"error":null,"idempotent":1,"ok":0,"prepared":{"errors":{"field":"field is invalid"},"ok":0,"values":{"allocate_position":1,"author_user_id":" user-1 ","body_hash":"b87e74db2baf019fb26d1a764aa329723024c6be7f13e5a92a60690b301bc3e9","body_source":" Reply body ","idempotency_key":"command-reply.create","thread_id":" thread-1 ","visibility":"","visibility_floor":"private"}},"status":"invalid","stored":null}
reply.create invalid request	{"actor_id":"user-1","command_id":"command-reply.create","command_type":"reply.create","idempotency_key":"command-reply.create","request":{"author_user_id":"user-1","body_hash":"b87e74db2baf019fb26d1a764aa329723024c6be7f13e5a92a60690b301bc3e9","thread_id":"thread-1","visibility":""}}
reply.create invalid response	{"errors":{"field":"field is invalid"},"ok":0,"status":"invalid","values":{"allocate_position":1,"author_user_id":" user-1 ","body_hash":"b87e74db2baf019fb26d1a764aa329723024c6be7f13e5a92a60690b301bc3e9","body_source":" Reply body ","idempotency_key":"command-reply.create","thread_id":" thread-1 ","visibility":"","visibility_floor":"private"}}
reply.create invalid result	{"error":null,"ok":0,"prepared":{"errors":{"field":"field is invalid"},"ok":0,"values":{"allocate_position":1,"author_user_id":" user-1 ","body_hash":"b87e74db2baf019fb26d1a764aa329723024c6be7f13e5a92a60690b301bc3e9","body_source":" Reply body ","idempotency_key":"command-reply.create","thread_id":" thread-1 ","visibility":"","visibility_floor":"private"}},"status":"invalid","stored":null}
reply.create not_found replay	{"error":"thread not found","idempotent":1,"ok":0,"prepared":null,"status":"not_found","stored":null}
reply.create not_found request	{"actor_id":"user-1","command_id":"command-reply.create","command_type":"reply.create","idempotency_key":"command-reply.create","request":{"author_user_id":"user-1","body_hash":"b87e74db2baf019fb26d1a764aa329723024c6be7f13e5a92a60690b301bc3e9","thread_id":"thread-gone","visibility":""}}
reply.create not_found response	{"error":"thread not found","ok":0,"status":"not_found"}
reply.create not_found result	{"error":"thread not found","ok":0,"prepared":null,"status":"not_found","stored":null}
reply.create ok replay	{"error":null,"idempotent":1,"ok":1,"prepared":null,"status":"ok","stored":{"ok":1,"post":{"post_id":"post-new","thread_id":" thread-1 "}}}
reply.create ok request	{"actor_id":"user-1","command_id":"command-reply.create","command_type":"reply.create","idempotency_key":"command-reply.create","request":{"author_user_id":"user-1","body_hash":"b87e74db2baf019fb26d1a764aa329723024c6be7f13e5a92a60690b301bc3e9","thread_id":"thread-1","visibility":""}}
reply.create ok response	{"ok":1,"post_id":"post-new","status":"ok","thread_id":" thread-1 "}
reply.create ok result	{"error":null,"ok":1,"prepared":{"command":{"body":{"body_source":" Reply body "},"idempotency_key":"command-reply.create","post":{"author_user_id":" user-1 ","post_id":"post-new","thread_id":" thread-1 "},"thread":{"thread_id":" thread-1 "},"visibility":"private"},"ok":1},"status":"ok","stored":{"ok":1,"post":{"author_user_id":"user-1","current_body_id":null,"current_revision_id":null,"deleted_at":null,"deleted_by":null,"hidden_at":null,"locked_at":null,"moderation_state":null,"permission_version":null,"position":null,"post_id":"post-new","thread_id":" thread-1 ","version":null,"visibility":null,"visibility_version":null},"skipped":null}}
reply.create store_failure replay	{"error":"post store failed","ok":0,"prepared":null,"status":"failed","stored":null}
reply.create store_failure request	{"actor_id":"user-1","command_id":"command-reply.create","command_type":"reply.create","idempotency_key":"command-reply.create","request":{"author_user_id":"user-1","body_hash":"b87e74db2baf019fb26d1a764aa329723024c6be7f13e5a92a60690b301bc3e9","thread_id":"thread-1","visibility":""}}
reply.create store_failure response	null
reply.create store_failure result	{"error":"post store failed","ok":0,"prepared":null,"status":"failed","stored":null}
reply.create store_refusal replay	{"error":"thread is locked","idempotent":1,"ok":0,"prepared":null,"status":"forbidden","stored":null}
reply.create store_refusal request	{"actor_id":"user-1","command_id":"command-reply.create","command_type":"reply.create","idempotency_key":"command-reply.create","request":{"author_user_id":"user-1","body_hash":"b87e74db2baf019fb26d1a764aa329723024c6be7f13e5a92a60690b301bc3e9","thread_id":"thread-1","visibility":""}}
reply.create store_refusal response	{"error":"thread is locked","ok":0,"status":"forbidden"}
reply.create store_refusal result	{"error":"thread is locked","ok":0,"prepared":null,"status":"forbidden","stored":null}
thread.create invalid replay	{"error":null,"idempotent":1,"ok":0,"prepared":{"errors":{"field":"field is invalid"},"ok":0,"values":{"author_user_id":" user-1 ","body_hash":"6c34176bd33df102be3cb1bc385f04bbf3d3461d14419fd4652c8cbf09f0395f","body_source":" Opening body \n","category_id":"general","idempotency_key":"command-thread.create","title":" Hello ","visibility":" public ","visibility_floor":"members"}},"status":"invalid","stored":null}
thread.create invalid request	{"actor_id":"user-1","command_id":"command-thread.create","command_type":"thread.create","idempotency_key":"command-thread.create","request":{"author_user_id":"user-1","body_hash":"6c34176bd33df102be3cb1bc385f04bbf3d3461d14419fd4652c8cbf09f0395f","category_id":"general","title":"Hello","visibility":"public"}}
thread.create invalid response	{"errors":{"field":"field is invalid"},"ok":0,"status":"invalid","values":{"author_user_id":" user-1 ","body_hash":"6c34176bd33df102be3cb1bc385f04bbf3d3461d14419fd4652c8cbf09f0395f","body_source":" Opening body \n","category_id":"general","idempotency_key":"command-thread.create","title":" Hello ","visibility":" public ","visibility_floor":"members"}}
thread.create invalid result	{"error":null,"ok":0,"prepared":{"errors":{"field":"field is invalid"},"ok":0,"values":{"author_user_id":" user-1 ","body_hash":"6c34176bd33df102be3cb1bc385f04bbf3d3461d14419fd4652c8cbf09f0395f","body_source":" Opening body \n","category_id":"general","idempotency_key":"command-thread.create","title":" Hello ","visibility":" public ","visibility_floor":"members"}},"status":"invalid","stored":null}
thread.create not_found replay	{"error":"category not found","idempotent":1,"ok":0,"prepared":null,"status":"not_found","stored":null}
thread.create not_found request	{"actor_id":"user-1","command_id":"command-thread.create","command_type":"thread.create","idempotency_key":"command-thread.create","request":{"author_user_id":"user-1","body_hash":"6c34176bd33df102be3cb1bc385f04bbf3d3461d14419fd4652c8cbf09f0395f","category_id":"missing","title":"Hello","visibility":"public"}}
thread.create not_found response	{"error":"category not found","ok":0,"status":"not_found"}
thread.create not_found result	{"error":"category not found","ok":0,"prepared":null,"status":"not_found","stored":null}
thread.create ok replay	{"error":null,"idempotent":1,"ok":1,"prepared":null,"status":"ok","stored":{"ok":1,"post":{"post_id":"post-new"},"thread":{"thread_id":"thread-new"}}}
thread.create ok request	{"actor_id":"user-1","command_id":"command-thread.create","command_type":"thread.create","idempotency_key":"command-thread.create","request":{"author_user_id":"user-1","body_hash":"6c34176bd33df102be3cb1bc385f04bbf3d3461d14419fd4652c8cbf09f0395f","category_id":"general","title":"Hello","visibility":"public"}}
thread.create ok response	{"ok":1,"post_id":"post-new","status":"ok","thread_id":"thread-new"}
thread.create ok result	{"error":null,"ok":1,"prepared":{"command":{"body":{"body_source":" Opening body \n"},"idempotency_key":"command-thread.create","post":{"author_user_id":" user-1 ","post_id":"post-new","thread_id":"thread-new"},"thread":{"thread_id":"thread-new"},"visibility":"members"},"ok":1},"status":"ok","stored":{"ok":1,"post":{"author_user_id":"user-1","post_id":"post-new","thread_id":"thread-new"},"skipped":null,"thread":{"category_id":"general","slug":"hello","thread_id":"thread-new","title":"Hello"}}}
thread.create store_failure replay	{"error":"thread store failed","ok":0,"prepared":null,"status":"failed","stored":null}
thread.create store_failure request	{"actor_id":"user-1","command_id":"command-thread.create","command_type":"thread.create","idempotency_key":"command-thread.create","request":{"author_user_id":"user-1","body_hash":"6c34176bd33df102be3cb1bc385f04bbf3d3461d14419fd4652c8cbf09f0395f","category_id":"general","title":"Hello","visibility":"public"}}
thread.create store_failure response	null
thread.create store_failure result	{"error":"thread store failed","ok":0,"prepared":null,"status":"failed","stored":null}
thread.create store_refusal replay	{"error":"thread not found","idempotent":1,"ok":0,"prepared":null,"status":"not_found","stored":null}
thread.create store_refusal request	{"actor_id":"user-1","command_id":"command-thread.create","command_type":"thread.create","idempotency_key":"command-thread.create","request":{"author_user_id":"user-1","body_hash":"6c34176bd33df102be3cb1bc385f04bbf3d3461d14419fd4652c8cbf09f0395f","category_id":"general","title":"Hello","visibility":"public"}}
thread.create store_refusal response	{"error":"thread not found","ok":0,"status":"not_found"}
thread.create store_refusal result	{"error":"thread not found","ok":0,"prepared":null,"status":"not_found","stored":null}
thread.delete forbidden replay	{"error":"not the thread author","idempotent":1,"ok":0,"prepared":null,"status":"forbidden","stored":null}
thread.delete forbidden request	{"actor_id":"user-2","command_id":"command-thread.delete","command_type":"thread.delete","idempotency_key":"command-thread.delete","request":{"author_user_id":"user-2","thread_id":"thread-1"}}
thread.delete forbidden response	{"error":"not the thread author","ok":0,"status":"forbidden"}
thread.delete forbidden result	{"error":"not the thread author","ok":0,"prepared":null,"status":"forbidden","stored":null}
thread.delete not_found replay	{"error":"thread not found","idempotent":1,"ok":0,"prepared":null,"status":"not_found","stored":null}
thread.delete not_found request	{"actor_id":"user-1","command_id":"command-thread.delete","command_type":"thread.delete","idempotency_key":"command-thread.delete","request":{"author_user_id":"user-1","thread_id":"thread-gone"}}
thread.delete not_found response	{"error":"thread not found","ok":0,"status":"not_found"}
thread.delete not_found result	{"error":"thread not found","ok":0,"prepared":null,"status":"not_found","stored":null}
thread.delete ok replay	{"error":null,"idempotent":1,"ok":1,"prepared":null,"status":"ok","stored":{"ok":1,"thread":{"thread_id":" thread-1 "}}}
thread.delete ok request	{"actor_id":"user-1","command_id":"command-thread.delete","command_type":"thread.delete","idempotency_key":"command-thread.delete","request":{"author_user_id":"user-1","thread_id":"thread-1"}}
thread.delete ok response	{"ok":1,"status":"ok","thread_id":" thread-1 "}
thread.delete ok result	{"error":null,"ok":1,"prepared":null,"status":"ok","stored":{"ok":1,"thread":{"category_id":"general","slug":"new-title","thread_id":" thread-1 ","title":"New title"}}}
thread.delete store_failure replay	{"error":"thread store failed","ok":0,"prepared":null,"status":"failed","stored":null}
thread.delete store_failure request	{"actor_id":"user-1","command_id":"command-thread.delete","command_type":"thread.delete","idempotency_key":"command-thread.delete","request":{"author_user_id":"user-1","thread_id":"thread-1"}}
thread.delete store_failure response	null
thread.delete store_failure result	{"error":"thread store failed","ok":0,"prepared":null,"status":"failed","stored":null}
thread.delete store_refusal replay	{"error":"thread not found","idempotent":1,"ok":0,"prepared":null,"status":"not_found","stored":null}
thread.delete store_refusal request	{"actor_id":"user-1","command_id":"command-thread.delete","command_type":"thread.delete","idempotency_key":"command-thread.delete","request":{"author_user_id":"user-1","thread_id":"thread-1"}}
thread.delete store_refusal response	{"error":"thread not found","ok":0,"status":"not_found"}
thread.delete store_refusal result	{"error":"thread not found","ok":0,"prepared":null,"status":"not_found","stored":null}
thread.edit forbidden replay	{"error":"not the thread author","idempotent":1,"ok":0,"prepared":null,"status":"forbidden","stored":null}
thread.edit forbidden request	{"actor_id":"user-2","command_id":"command-thread.edit","command_type":"thread.edit","idempotency_key":"command-thread.edit","request":{"author_user_id":"user-2","thread_id":"thread-1","title":"New title"}}
thread.edit forbidden response	{"error":"not the thread author","ok":0,"status":"forbidden"}
thread.edit forbidden result	{"error":"not the thread author","ok":0,"prepared":null,"status":"forbidden","stored":null}
thread.edit invalid replay	{"error":null,"idempotent":1,"ok":0,"prepared":{"errors":{"field":"field is invalid"},"ok":0,"values":{"editor_user_id":"user-1","idempotency_key":"command-thread.edit","thread_id":" thread-1 ","title":" New title "}},"status":"invalid","stored":null}
thread.edit invalid request	{"actor_id":"user-1","command_id":"command-thread.edit","command_type":"thread.edit","idempotency_key":"command-thread.edit","request":{"author_user_id":"user-1","thread_id":"thread-1","title":"New title"}}
thread.edit invalid response	{"errors":{"field":"field is invalid"},"ok":0,"status":"invalid","values":{"editor_user_id":"user-1","idempotency_key":"command-thread.edit","thread_id":" thread-1 ","title":" New title "}}
thread.edit invalid result	{"error":null,"ok":0,"prepared":{"errors":{"field":"field is invalid"},"ok":0,"values":{"editor_user_id":"user-1","idempotency_key":"command-thread.edit","thread_id":" thread-1 ","title":" New title "}},"status":"invalid","stored":null}
thread.edit not_found replay	{"error":"thread not found","idempotent":1,"ok":0,"prepared":null,"status":"not_found","stored":null}
thread.edit not_found request	{"actor_id":"user-1","command_id":"command-thread.edit","command_type":"thread.edit","idempotency_key":"command-thread.edit","request":{"author_user_id":"user-1","thread_id":"thread-gone","title":"New title"}}
thread.edit not_found response	{"error":"thread not found","ok":0,"status":"not_found"}
thread.edit not_found result	{"error":"thread not found","ok":0,"prepared":null,"status":"not_found","stored":null}
thread.edit ok replay	{"error":null,"idempotent":1,"ok":1,"prepared":null,"status":"ok","stored":{"ok":1,"thread":{"slug":"new-title","thread_id":" thread-1 ","title":"New title"}}}
thread.edit ok request	{"actor_id":"user-1","command_id":"command-thread.edit","command_type":"thread.edit","idempotency_key":"command-thread.edit","request":{"author_user_id":"user-1","thread_id":"thread-1","title":"New title"}}
thread.edit ok response	{"ok":1,"slug":"new-title","status":"ok","thread_id":" thread-1 ","title":"New title"}
thread.edit ok result	{"error":null,"ok":1,"prepared":{"command":{"thread":{"slug":"new-title","thread_id":" thread-1 ","title":"New title"}},"ok":1},"status":"ok","stored":{"ok":1,"thread":{"category_id":"general","slug":"new-title","thread_id":" thread-1 ","title":"New title"}}}
thread.edit store_failure replay	{"error":"thread store failed","ok":0,"prepared":null,"status":"failed","stored":null}
thread.edit store_failure request	{"actor_id":"user-1","command_id":"command-thread.edit","command_type":"thread.edit","idempotency_key":"command-thread.edit","request":{"author_user_id":"user-1","thread_id":"thread-1","title":"New title"}}
thread.edit store_failure response	null
thread.edit store_failure result	{"error":"thread store failed","ok":0,"prepared":null,"status":"failed","stored":null}
thread.edit store_refusal replay	{"error":"thread is locked","idempotent":1,"ok":0,"prepared":null,"status":"forbidden","stored":null}
thread.edit store_refusal request	{"actor_id":"user-1","command_id":"command-thread.edit","command_type":"thread.edit","idempotency_key":"command-thread.edit","request":{"author_user_id":"user-1","thread_id":"thread-1","title":"New title"}}
thread.edit store_refusal response	{"error":"thread is locked","ok":0,"status":"forbidden"}
thread.edit store_refusal result	{"error":"thread is locked","ok":0,"prepared":null,"status":"forbidden","stored":null}
thread.move forbidden replay	{"error":"not the thread author","idempotent":1,"ok":0,"prepared":null,"status":"forbidden","stored":null}
thread.move forbidden request	{"actor_id":"user-2","command_id":"command-thread.move","command_type":"thread.move","idempotency_key":"command-thread.move","request":{"author_user_id":"user-2","category_id":"other","thread_id":"thread-1"}}
thread.move forbidden response	{"error":"not the thread author","ok":0,"status":"forbidden"}
thread.move forbidden result	{"error":"not the thread author","ok":0,"prepared":null,"status":"forbidden","stored":null}
thread.move invalid replay	{"error":null,"idempotent":1,"ok":0,"prepared":{"errors":{"field":"field is invalid"},"ok":0,"values":{"category_id":" other ","editor_user_id":"user-1","idempotency_key":"command-thread.move","thread_id":"thread-1"}},"status":"invalid","stored":null}
thread.move invalid request	{"actor_id":"user-1","command_id":"command-thread.move","command_type":"thread.move","idempotency_key":"command-thread.move","request":{"author_user_id":"user-1","category_id":"other","thread_id":"thread-1"}}
thread.move invalid response	{"errors":{"field":"field is invalid"},"ok":0,"status":"invalid","values":{"category_id":" other ","editor_user_id":"user-1","idempotency_key":"command-thread.move","thread_id":"thread-1"}}
thread.move invalid result	{"error":null,"ok":0,"prepared":{"errors":{"field":"field is invalid"},"ok":0,"values":{"category_id":" other ","editor_user_id":"user-1","idempotency_key":"command-thread.move","thread_id":"thread-1"}},"status":"invalid","stored":null}
thread.move not_found replay	{"error":"category not found","idempotent":1,"ok":0,"prepared":null,"status":"not_found","stored":null}
thread.move not_found request	{"actor_id":"user-1","command_id":"command-thread.move","command_type":"thread.move","idempotency_key":"command-thread.move","request":{"author_user_id":"user-1","category_id":"missing","thread_id":"thread-1"}}
thread.move not_found response	{"error":"category not found","ok":0,"status":"not_found"}
thread.move not_found result	{"error":"category not found","ok":0,"prepared":null,"status":"not_found","stored":null}
thread.move ok replay	{"error":null,"idempotent":1,"ok":1,"prepared":null,"status":"ok","stored":{"ok":1,"thread":{"category_id":" other ","thread_id":"thread-1"}}}
thread.move ok request	{"actor_id":"user-1","command_id":"command-thread.move","command_type":"thread.move","idempotency_key":"command-thread.move","request":{"author_user_id":"user-1","category_id":"other","thread_id":"thread-1"}}
thread.move ok response	{"category_id":" other ","ok":1,"status":"ok","thread_id":"thread-1"}
thread.move ok result	{"error":null,"ok":1,"prepared":{"command":{"thread":{"category_id":" other ","thread_id":"thread-1"}},"ok":1},"status":"ok","stored":{"ok":1,"thread":{"category_id":" other ","slug":"new-title","thread_id":"thread-1","title":"New title"}}}
thread.move store_failure replay	{"error":"thread store failed","ok":0,"prepared":null,"status":"failed","stored":null}
thread.move store_failure request	{"actor_id":"user-1","command_id":"command-thread.move","command_type":"thread.move","idempotency_key":"command-thread.move","request":{"author_user_id":"user-1","category_id":"other","thread_id":"thread-1"}}
thread.move store_failure response	null
thread.move store_failure result	{"error":"thread store failed","ok":0,"prepared":null,"status":"failed","stored":null}
thread.move store_refusal replay	{"error":"thread not found","idempotent":1,"ok":0,"prepared":null,"status":"not_found","stored":null}
thread.move store_refusal request	{"actor_id":"user-1","command_id":"command-thread.move","command_type":"thread.move","idempotency_key":"command-thread.move","request":{"author_user_id":"user-1","category_id":"other","thread_id":"thread-1"}}
thread.move store_refusal response	{"error":"thread not found","ok":0,"status":"not_found"}
thread.move store_refusal result	{"error":"thread not found","ok":0,"prepared":null,"status":"not_found","stored":null}
thread.restore forbidden replay	{"error":"not the thread author","idempotent":1,"ok":0,"prepared":null,"status":"forbidden","stored":null}
thread.restore forbidden request	{"actor_id":"user-2","command_id":"command-thread.restore","command_type":"thread.restore","idempotency_key":"command-thread.restore","request":{"author_user_id":"user-2","thread_id":"thread-deleted"}}
thread.restore forbidden response	{"error":"not the thread author","ok":0,"status":"forbidden"}
thread.restore forbidden result	{"error":"not the thread author","ok":0,"prepared":null,"status":"forbidden","stored":null}
thread.restore not_found replay	{"error":"thread not found","idempotent":1,"ok":0,"prepared":null,"status":"not_found","stored":null}
thread.restore not_found request	{"actor_id":"user-1","command_id":"command-thread.restore","command_type":"thread.restore","idempotency_key":"command-thread.restore","request":{"author_user_id":"user-1","thread_id":"thread-1"}}
thread.restore not_found response	{"error":"thread not found","ok":0,"status":"not_found"}
thread.restore not_found result	{"error":"thread not found","ok":0,"prepared":null,"status":"not_found","stored":null}
thread.restore ok replay	{"error":null,"idempotent":1,"ok":1,"prepared":null,"status":"ok","stored":{"ok":1,"thread":{"thread_id":"thread-deleted"}}}
thread.restore ok request	{"actor_id":"user-1","command_id":"command-thread.restore","command_type":"thread.restore","idempotency_key":"command-thread.restore","request":{"author_user_id":"user-1","thread_id":"thread-deleted"}}
thread.restore ok response	{"ok":1,"status":"ok","thread_id":"thread-deleted"}
thread.restore ok result	{"error":null,"ok":1,"prepared":null,"status":"ok","stored":{"ok":1,"thread":{"category_id":"general","slug":"new-title","thread_id":"thread-deleted","title":"New title"}}}
thread.restore store_failure replay	{"error":"thread store failed","ok":0,"prepared":null,"status":"failed","stored":null}
thread.restore store_failure request	{"actor_id":"user-1","command_id":"command-thread.restore","command_type":"thread.restore","idempotency_key":"command-thread.restore","request":{"author_user_id":"user-1","thread_id":"thread-deleted"}}
thread.restore store_failure response	null
thread.restore store_failure result	{"error":"thread store failed","ok":0,"prepared":null,"status":"failed","stored":null}
thread.restore store_refusal replay	{"error":"thread is locked","idempotent":1,"ok":0,"prepared":null,"status":"forbidden","stored":null}
thread.restore store_refusal request	{"actor_id":"user-1","command_id":"command-thread.restore","command_type":"thread.restore","idempotency_key":"command-thread.restore","request":{"author_user_id":"user-1","thread_id":"thread-deleted"}}
thread.restore store_refusal response	{"error":"thread is locked","ok":0,"status":"forbidden"}
thread.restore store_refusal result	{"error":"thread is locked","ok":0,"prepared":null,"status":"forbidden","stored":null}
