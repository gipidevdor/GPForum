# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::PostingWorkflow;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Domain::Post;
use GPForum::Domain::Thread;
use GPForum::Infrastructure::Row;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Forum::PostingCommand;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Forum::Visibility;

our $VERSION = '0.001';

# The store call of each command: the store (post or thread), its method,
# the words its death is logged with, whether the mentions in the stored post
# are recorded after it (a new thread, a reply and a post edit), and whether
# the store's answer can be a refusal: the creation of a thread has nothing to
# check again under a lock.
const my %STORE => (
    'post.delete'    => [ 'post',   'delete_post',    'post delete',    0, 1 ],
    'post.edit'      => [ 'post',   'edit_post',      'post edit',      1, 1 ],
    'post.restore'   => [ 'post',   'restore_post',   'post restore',   0, 1 ],
    'reply.create'   => [ 'post',   'create_post',    'reply create',   1, 1 ],
    'thread.create'  => [ 'thread', 'create_thread',  'thread create',  1, 0 ],
    'thread.delete'  => [ 'thread', 'delete_thread',  'thread delete',  0, 1 ],
    'thread.edit'    => [ 'thread', 'edit_thread',    'thread edit',    0, 1 ],
    'thread.move'    => [ 'thread', 'move_thread',    'thread move',    0, 1 ],
    'thread.restore' => [ 'thread', 'restore_thread', 'thread restore', 0, 1 ],
);

const my $MAX_MENTIONS => 10;
const my $REPLY        => 'reply.create';

# A store failure raised inside api.forum_create_reply_v1: the server names
# the store's function in the error's context (ADR 0126).
const my $STORE_FUNCTION => qr/\b api[.]core_forum_store_reply_v1 \b/msx;

# A body without an at sign mentions no one (Community::MentionExtractor).
const my $MENTION_SIGN => q{@};

__PACKAGE__->requires(
    qw(category_reader mention_store post_composer post_reader post_store
      thread_composer thread_detail_reader thread_store)
);

has codec => sub { return GPForum::Service::Forum::PostingCommand->new; };
has command_idempotency => undef;    # optional: without it every call runs
has logger              => undef;    # optional: without it nothing is logged

# ADR 0126: on PostgreSQL a reply's command log and store run in one call to
# api.forum_create_reply_v1, on the post store's schema. Without a command
# log (CommandIdempotency) or a post store (PostStore) on PostgreSQL -- the
# in-memory doubles -- the Perl path runs.
has functions => sub ($self) {
    my ( $log, $store ) = ( $self->command_idempotency, $self->post_store );
    return undef
      if !blessed $log
      || !$log->isa('GPForum::Service::Operations::CommandIdempotency')
      || !blessed $store
      || !$store->isa('GPForum::Service::Forum::PostStore');

    return GPForum::Infrastructure::SqlFunction->for_schema( $store->schema );
};

sub create_thread ( $self, $input ) {
    return $self->_run( 'thread.create', $input,
        sub { return $self->_create_thread_once($input); } );
}

sub create_reply ( $self, $input ) {
    if ( my $functions = $self->functions ) {
        return $self->_create_reply_by_function( $functions, $input );
    }

    return $self->_run( $REPLY, $input,
        sub { return $self->_create_reply_once($input); } );
}

sub edit_thread ( $self, $input ) {
    return $self->_run( 'thread.edit', $input,
        sub { return $self->_edit_thread_once($input); } );
}

sub move_thread ( $self, $input ) {
    return $self->_run( 'thread.move', $input,
        sub { return $self->_move_thread_once($input); } );
}

sub delete_thread ( $self, $input ) {
    return $self->_run( 'thread.delete', $input,
        sub { return $self->_delete_thread_once($input); } );
}

sub restore_thread ( $self, $input ) {
    return $self->_run( 'thread.restore', $input,
        sub { return $self->_restore_thread_once($input); } );
}

sub edit_post ( $self, $input ) {
    return $self->_run( 'post.edit', $input,
        sub { return $self->_edit_post_once($input); } );
}

sub delete_post ( $self, $input ) {
    return $self->_run( 'post.delete', $input,
        sub { return $self->_delete_post_once($input); } );
}

sub restore_post ( $self, $input ) {
    return $self->_run( 'post.restore', $input,
        sub { return $self->_restore_post_once($input); } );
}

sub _create_thread_once ( $self, $input ) {
    my $category_id = _trim( $input->{category_id} );
    my $category;
    if ( length $category_id ) {
        $category =
          $self->category_reader->find_category( $category_id,
            _viewer($input) );
        return _result( status => 'not_found', error => 'category not found' )
          if !$category;
    }

    return $self->_store_composed(
        'thread.create',
        $self->thread_composer->prepare(
            {
                author_user_id => $input->{author_user_id},
                body_hash   => $self->codec->body_hash( $input->{body_source} ),
                body_source => $input->{body_source},
                category_id => $category_id,
                idempotency_key  => _command_id($input),
                title            => $input->{title},
                visibility       => $input->{visibility},
                visibility_floor => _effective_visibility(
                    $category, qw(space_visibility visibility)
                ),
            }
        )
    );
}

# The reply as the function runs it. Perl does what is not the database's:
# the request's fingerprint, the ids and the clock the command log draws,
# the workflow's check before the lock (the thread as the author reads it)
# and the composer. Their answer, when they refuse, is the response the
# function records; otherwise the function stores the post under the lock
# and records its answer. A failure of either step is answered as the Perl
# path answers it: command log failed, or post store failed when the store's
# own statements raised.
sub _create_reply_by_function ( $self, $functions, $input ) {
    my $key = _command_id($input);
    return _missing_command_id_result($input) if !length $key;

    my ( $call, $prepared );
    try {
        ( $call, $prepared ) = $self->_reply_call( $key, $input );
    }
    catch ($error) {
        $self->_log( error => "command log failed: $error" );
        return _result( status => 'failed', error => 'command log failed' );
    };

    my $result;
    try {
        $result = $self->_reply_called( $functions, $call, $prepared );
    }
    catch ($error) {
        if ( "$error" =~ $STORE_FUNCTION ) {
            $self->_log( error => "reply create failed: $error" );
            return _result( status => 'failed', error => 'post store failed' );
        }
        $self->_log( error => "command log failed: $error" );
        return _result( status => 'failed', error => 'command log failed' );
    };

    return $result;
}

# The call's parameters, and the composer's answer when it ran. The ids and
# the time come in the order the Perl path draws them: the command row's
# id and correlation id and its time, then the composer's, then the store's.
sub _reply_call ( $self, $key, $input ) {
    my $log  = $self->command_idempotency;
    my %call = (
        actor_id               => _nullable( $input->{author_user_id} ),
        command_id             => $log->id_service->uuid,
        command_correlation_id => $log->id_service->uuid,
        command_at             => $log->clock->now_iso8601,
        command_type           => $REPLY,
        idempotency_key        => $key,
        request_hash           =>
          $log->request_hash( $self->codec->request( $REPLY, $input ) ),
        store_refusals => $self->_store_refusals,
    );

    my $thread =
      $self->thread_detail_reader->find_thread( $input->{thread_id},
        _viewer($input) );
    my $answer = _refused( GPForum::Domain::Thread->reply_refusal($thread) );
    my $prepared;
    if ( !$answer ) {
        $prepared = $self->post_composer->prepare(
            {
                allocate_position => 1,
                author_user_id    => $input->{author_user_id},
                body_hash   => $self->codec->body_hash( $input->{body_source} ),
                body_source => $input->{body_source},
                idempotency_key  => $key,
                thread_id        => $input->{thread_id},
                visibility       => $input->{visibility},
                visibility_floor => _effective_visibility(
                    $thread,
                    qw(space_visibility category_visibility visibility)
                ),
            }
        );
        if ( !$prepared->{ok} ) {
            $answer = _result( status => 'invalid', prepared => $prepared );
        }
    }

    $call{answer} = $answer ? $self->codec->response( $REPLY, $answer ) : undef;
    my $store =
      $answer
      ? { map { $_ => undef } $self->post_store->reply_parameter_names }
      : $self->post_store->reply_parameters( $prepared->{command} );

    # The command's own key wins over the store's undefined one.
    return ( { %{$store}, %call }, $prepared );
}

# The response the command log keeps for each refusal the store can give
# under its lock, by the code the function answers with: the words and the
# status the Perl path records.
sub _store_refusals ($self) {
    return {
        map {
            $_ => $self->codec->response( $REPLY,
                _refused( GPForum::Domain::Thread->reply_refusal_words($_) ) )
        } GPForum::Domain::Thread->reply_refusal_codes
    };
}

# The call, and the answer it gives as the Perl path gives it. A body that
# may mention someone has its mentions recorded in the reply's transaction,
# as the Perl path recorded them in the command's; one that cannot is one
# statement in autocommit.
sub _reply_called ( $self, $functions, $call, $prepared ) {
    my $run = sub {
        my $result =
          $self->_reply_result( $functions->row( 'forum_create_reply', $call ),
            $prepared );
        if ( $result->{ok} && !$result->{idempotent} ) {
            $self->_record_post_mentions( $result->{stored},
                $prepared->{command} );
        }
        return $result;
    };
    my $body =
        $prepared && $prepared->{ok}
      ? $prepared->{command}{body}{body_source} // q{}
      : q{};

    return $run->() if index( $body, $MENTION_SIGN ) < 0;

    return $self->post_store->schema->txn_do($run);
}

# The function's row as the result the Perl path answers: a replay of the
# stored response, a conflict in the command log's words, or the answer it
# recorded -- the post stored, the composer's invalid answer, or a refusal.
sub _reply_result ( $self, $row, $prepared ) {
    my $outcome = $row->{outcome} // q{};
    return $self->codec->replay( $REPLY, $row->{response} )
      if $outcome eq 'replayed';
    if ( $outcome ne 'recorded' ) {
        return _result(
            status => 'conflict',
            error  =>
              GPForum::Service::Operations::CommandIdempotency->refusal_error(
                $outcome),
        );
    }

    my $status = $row->{response}{status} // q{};
    if ( $status eq 'ok' ) {
        my $result = _result(
            status => 'ok',
            stored => $self->post_store->reply_answer($row),
        );
        $result->{prepared} = $prepared;
        return $result;
    }
    return _result( status => 'invalid', prepared => $prepared )
      if $status eq 'invalid';

    return _refused( $row->{response}{error} );
}

sub _create_reply_once ( $self, $input ) {
    my $thread =
      $self->thread_detail_reader->find_thread( $input->{thread_id},
        _viewer($input) );
    my $refused = _refused( GPForum::Domain::Thread->reply_refusal($thread) );
    return $refused if $refused;

    return $self->_store_composed(
        'reply.create',
        $self->post_composer->prepare(
            {
                allocate_position => 1,
                author_user_id    => $input->{author_user_id},
                body_hash   => $self->codec->body_hash( $input->{body_source} ),
                body_source => $input->{body_source},
                idempotency_key  => _command_id($input),
                thread_id        => $input->{thread_id},
                visibility       => $input->{visibility},
                visibility_floor => _effective_visibility(
                    $thread,
                    qw(space_visibility category_visibility visibility)
                ),
            }
        )
    );
}

sub _edit_thread_once ( $self, $input ) {
    my ( undef, $refused ) = $self->_thread_checked( $input, 'edit_refusal' );
    return $refused if $refused;

    return $self->_store_composed(
        'thread.edit',
        $self->thread_composer->prepare_title(
            {
                editor_user_id  => $input->{author_user_id},
                idempotency_key => _command_id($input),
                thread_id       => $input->{thread_id},
                title           => $input->{title},
            }
        )
    );
}

# Only the thread's author may move it, and only into a category they can
# read.
sub _move_thread_once ( $self, $input ) {
    my ( undef, $refused ) = $self->_thread_checked( $input, 'edit_refusal' );
    return $refused if $refused;

    my $category_id = _trim( $input->{category_id} );
    return _result( status => 'not_found', error => 'category not found' )
      if length $category_id
      && !$self->category_reader->find_category( $category_id,
        _viewer($input) );

    return $self->_store_composed(
        'thread.move',
        $self->thread_composer->prepare_move(
            {
                category_id     => $input->{category_id},
                editor_user_id  => $input->{author_user_id},
                idempotency_key => _command_id($input),
                thread_id       => $input->{thread_id},
            }
        )
    );
}

sub _delete_thread_once ( $self, $input ) {
    my ( $thread, $refused ) = $self->_thread_checked( $input, 'edit_refusal' );
    return $refused if $refused;

    return $self->_call_store(
        'thread.delete',
        {
            idempotency_key => _command_id($input),
            thread          => {
                category_id => _column( $thread, 'category_id' ),
                deleted_by  => _trim( $input->{author_user_id} ),
                thread_id   => $input->{thread_id},
            },
        }
    );
}

sub _restore_thread_once ( $self, $input ) {
    my ( $thread, $refused ) =
      $self->_thread_checked( $input, 'restore_refusal' );
    return $refused if $refused;

    return $self->_call_store(
        'thread.restore',
        {
            idempotency_key => _command_id($input),
            thread          => {
                author_user_id => _column( $thread, 'author_user_id' ),
                category_id    => _column( $thread, 'category_id' ),
                restored_by    => _trim( $input->{author_user_id} ),
                thread_id      => $input->{thread_id},
            },
        }
    );
}

sub _edit_post_once ( $self, $input ) {
    my ( $post, $refused ) = $self->_post_checked( $input, 'edit_refusal' );
    return $refused if $refused;

    return $self->_store_composed(
        'post.edit',
        $self->post_composer->prepare_revision(
            {
                body_hash   => $self->codec->body_hash( $input->{body_source} ),
                body_source => $input->{body_source},
                edit_reason => $input->{edit_reason},
                editor_user_id  => $input->{author_user_id},
                idempotency_key => _command_id($input),
                post_id         => $input->{post_id},
                thread_id       => _column( $post, 'thread_id' ),
            }
        )
    );
}

sub _delete_post_once ( $self, $input ) {
    my ( $post, $refused ) = $self->_post_checked( $input, 'edit_refusal' );
    return $refused if $refused;

    return $self->_call_store(
        'post.delete',
        {
            idempotency_key => _command_id($input),
            post            => {
                deleted_by => _trim( $input->{author_user_id} ),
                post_id    => $input->{post_id},
                thread_id  => _column( $post, 'thread_id' ),
            },
        }
    );
}

sub _restore_post_once ( $self, $input ) {
    my ( $post, $refused ) = $self->_post_checked( $input, 'restore_refusal' );
    return $refused if $refused;

    return $self->_call_store(
        'post.restore',
        {
            idempotency_key => _command_id($input),
            post            => {
                author_user_id => _column( $post, 'author_user_id' ),
                post_id        => $input->{post_id},
                restored_by    => _trim( $input->{author_user_id} ),
                thread_id      => _column( $post, 'thread_id' ),
            },
        }
    );
}

# The thread as the author reads it, and the refusal of a GPForum::Domain::
# Thread rule for it as a result, or undef.
sub _thread_checked ( $self, $input, $rule ) {
    my $thread =
      $self->thread_detail_reader->find_thread( $input->{thread_id},
        _viewer($input) );

    return (
        $thread,
        _refused(
            GPForum::Domain::Thread->$rule(
                $thread, _trim( $input->{author_user_id} )
            )
        )
    );
}

# The post, its thread as the author reads it, and the refusal of a
# GPForum::Domain::Post rule for them as a result, or undef.
sub _post_checked ( $self, $input, $rule ) {
    my $post = $self->post_reader->find_post( $input->{post_id} );
    my $thread =
      $post
      ? $self->thread_detail_reader->find_thread( _column( $post, 'thread_id' ),
        _viewer($input) )
      : undef;

    return (
        $post,
        _refused(
            GPForum::Domain::Post->$rule(
                $post, $thread, _trim( $input->{author_user_id} )
            )
        )
    );
}

# A refusal of the rules in GPForum::Domain, as a result with the status it
# means; undef when there is none.
sub _refused ($error) {
    return undef if !$error;

    return _result(
        status => GPForum::Domain::Post->status_of($error),
        error  => $error
    );
}

# Once per command id. With a command log the request and the response are
# kept (GPForum::Service::Forum::PostingCommand), a repeat of the request is
# answered from the response, and another request under the same id is a
# conflict.
sub _run ( $self, $type, $input, $run ) {
    return $self->_run_by_function( $type, $input, $run ) if $self->functions;
    my $command_id = _command_id($input);
    return _missing_command_id_result($input) if !length $command_id;
    return $run->()                           if !$self->command_idempotency;

    my $guarded;
    try {
        $guarded = $self->command_idempotency->run(
            {
                actor_id        => $input->{author_user_id},
                command_id      => $command_id,
                command_type    => $type,
                idempotency_key => $command_id,
                request         => $self->codec->request( $type, $input ),
            },
            $run,
            sub ($result) { return $self->codec->response( $type, $result ); },
        );
    }
    catch ($error) {
        $self->_log( error => "command log failed: $error" );
        return _result( status => 'failed', error => 'command log failed' );
    };

    return _missing_command_id_result($input) if $guarded->{invalid};
    return _result( status => 'conflict', error => $guarded->{error} )
      if $guarded->{conflict} || $guarded->{in_progress};
    return $self->codec->replay( $type, $guarded->{response} )
      if $guarded->{replayed};

    return $guarded->{result};
}

# Reuse the workflow's validation and composition before the database call.
# During preparation the store handoff is deferred. The function then owns
# the command row, store locks and event/audit/outbox writes atomically.
sub _run_by_function ( $self, $type, $input, $run ) {
    my $key = _command_id($input);
    return _missing_command_id_result($input) if !length $key;
    my ( $call, $prepared );
    try {
        my $log         = $self->command_idempotency;
        my $command_log = {
            actor_id               => _nullable( $input->{author_user_id} ),
            command_id             => $log->id_service->uuid,
            command_correlation_id => $log->id_service->uuid,
            command_at             => $log->clock->now_iso8601,
            command_type           => $type,
            idempotency_key        => $key,
            request_hash           =>
              $log->request_hash( $self->codec->request( $type, $input ) ),
        };
        my $answer;
        {
            # This handoff flag is scoped to preparation and restored on errors.
            ## no critic (Variables::ProhibitLocalVars)
            local $self->{preparing_function} = 1;
            ## use critic
            $answer = $run->();
        }
        $prepared = $answer->{prepared};
        my $store = $self->_function_store($type);
        my $values =
          $answer->{pending}
          ? $store->function_parameters( _function_type($type),
            $answer->{command} )
          : {
            store_type => _function_type($type),
            command    => undef,
            record     => undef
          };
        $call = {
            %{$values},
            log    => $command_log,
            answer => $answer->{pending}
            ? undef
            : $self->codec->response( $type, $answer )
        };
    }
    catch ($error) {
        $self->_log( error => "command log failed: $error" );
        return _result( status => 'failed', error => 'command log failed' );
    };
    my $execute = sub {
        my $row     = $self->functions->row( 'forum_write_command', $call );
        my $outcome = $row->{outcome} // q{};
        return $self->codec->replay( $type, $row->{response} )
          if $outcome eq 'replayed';
        return _result(
            status => 'conflict',
            error  =>
              GPForum::Service::Operations::CommandIdempotency->refusal_error(
                $outcome)
        ) if $outcome ne 'recorded';
        my $response = $row->{response};
        return _result( status => 'invalid', prepared => $prepared )
          if $response->{status} eq 'invalid';
        return _result(
            status => $response->{status},
            error  => $response->{error}
        ) if !$response->{ok};
        my $stored =
          $self->_function_store($type)->function_answer( $row->{stored} );
        my $result =
          _result( status => 'ok', stored => $stored, prepared => $prepared );
        my ( undef, undef, undef, $mentions ) = @{ $STORE{$type} };

        if ($mentions) {
            $self->_record_post_mentions( $stored, $call->{command} );
        }
        return $result;
    };
    my $result;
    try {
        my $body =
            $call->{command}
          ? $call->{command}{body}{body_source} // q{}
          : q{};
        $result =
          index( $body, $MENTION_SIGN ) < 0
          ? $execute->()
          : $self->_function_store($type)->schema->txn_do($execute);
    }
    catch ($error) {
        my ( $noun, undef, $label ) = @{ $STORE{$type} };
        if ( "$error" =~ /\bapi[.]core_forum_\w+_v1\b/msx ) {
            $self->_log( error => "$label failed: $error" );
            return _result( status => 'failed', error => "$noun store failed" );
        }
        $self->_log( error => "command log failed: $error" );
        return _result( status => 'failed', error => 'command log failed' );
    };
    return $result;
}

sub _function_store ( $self, $type ) {
    my $method = $STORE{$type}[0] . '_store';
    return $self->$method;
}

sub _function_type ($type) {
    my ( $noun, $verb ) = split /[.]/msx, $type;
    my %event = (
        create  => 'created',
        edit    => 'updated',
        move    => 'moved',
        delete  => 'deleted',
        restore => 'undeleted',
    );
    return "$noun.$event{$verb}";
}

# A composer's answer: invalid, or its command stored, and then the mentions
# in the stored post recorded.
sub _store_composed ( $self, $type, $prepared ) {
    return _result( status => 'invalid', prepared => $prepared )
      if !$prepared->{ok};

    my $stored = $self->_call_store( $type, $prepared->{command} );
    if ( $stored->{pending} ) {
        $stored->{prepared} = $prepared;
    }
    return $stored if !$stored->{ok};

    my ( undef, undef, undef, $mentions ) = @{ $STORE{$type} };
    if ($mentions) {
        $self->_record_post_mentions( $stored->{stored}, $prepared->{command} );
    }
    $stored->{prepared} = $prepared;

    return $stored;
}

# A store checks again, under its row locks, what the workflow checked before
# the transaction, because a moderator may have locked or hidden the thread or
# the post since, or the author deleted or restored one. Its refusal is an
# answer, not a failure: the status the first check gives, recorded with the
# command and replayed with it. A death, or an answer that is neither, is a
# failure.
sub _call_store ( $self, $type, $command ) {
    return { pending => 1, command => $command }
      if $self->{preparing_function};
    my ( $noun, $method, $label, undef, $refusals ) = @{ $STORE{$type} };
    my $store   = "${noun}_store";
    my $failure = "$noun store failed";

    my $stored;
    try { $stored = $self->$store->$method($command); }
    catch ($error) {
        $self->_log( error => "$label failed: $error" );
        return _result( status => 'failed', error => $failure );
    };

    my $refusal =
      ref $stored eq 'HASH' && !$stored->{ok} ? $stored->{error} : undef;
    return _refused($refusal)
      if $refusals
      && defined GPForum::Domain::Post->status_of($refusal);
    return _result( status => 'failed', error => $failure, stored => $stored )
      if ref $stored ne 'HASH' || !$stored->{ok};

    return _result( status => 'ok', stored => $stored );
}

# At most ten, and a failure only degrades: the post is stored.
sub _record_post_mentions ( $self, $stored, $command ) {
    try {
        $self->mention_store->record_for_source(
            {
                actor_id => _column( $stored->{post}, 'author_user_id' )
                  || $command->{post}{author_user_id},
                body_source  => $command->{body}{body_source},
                max_mentions => $MAX_MENTIONS,
                source_id    => _column( $stored->{post}, 'post_id' ),
                source_type  => 'post',
                thread_id    => $command->{post}{thread_id},
            }
        );
    }
    catch ($error) {
        $self->_log( warn => "mention recording degraded: $error" );
    };

    return;
}

# ADR 0102: the effective visibility a new thread or reply may not exceed,
# from the columns of the category or thread it goes in. No category (the
# composer rejects that) sets no floor.
sub _effective_visibility ( $row, @columns ) {
    return undef if !$row;

    return GPForum::Service::Forum::Visibility->effective(
        map { _column( $row, $_ ) } @columns );
}

sub _command_id ($input) {
    my $command_id = _trim( $input->{command_id} );
    return $command_id if length $command_id;

    return _trim( $input->{idempotency_key} );
}

# No input at all is answered like input without a command id.
sub _missing_command_id_result ($input) {
    return _result(
        status   => 'invalid',
        prepared => {
            errors => { command_id => 'command_id is required' },
            ok     => 0,
            values => { %{ $input // {} } },
        },
    );
}

sub _result (%input) {
    return {
        error    => $input{error},
        ok       => ( $input{status} || q{} ) eq 'ok' ? 1 : 0,
        prepared => $input{prepared},
        status   => $input{status} || 'failed',
        stored   => $input{stored},
    };
}

sub _trim ($value) {
    return ( $value // q{} ) =~ s/\A \s+ | \s+ \z//grmsx;
}

# Trimmed, and undef when nothing is left, as the command log keeps an actor.
sub _nullable ($value) {
    my $trimmed = _trim($value);

    return length $trimmed ? $trimmed : undef;
}

sub _column ( $row, $name ) {
    return GPForum::Infrastructure::Row->column( $row, $name );
}

sub _log ( $self, $level, $message ) {
    if ( $self->logger ) {
        $self->logger->$level($message);
    }

    return undef;
}

# The author as a reader (ADR 0102): a write needs a category or thread they
# can read. Controllers pass the request's viewer; without one, anonymous --
# which reads public content only, so a write never widens access.
sub _viewer ($input) {
    return $input->{viewer} || GPForum::Service::Forum::Viewer->anonymous;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::PostingWorkflow - Create, edit, move, delete and restore threads and posts, once per command id.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $workflow = GPForum::Service::Forum::PostingWorkflow->new(
        category_reader      => $category_reader,
        command_idempotency  => $command_idempotency,
        logger               => $app->log,
        mention_store        => $mention_store,
        post_composer        => $post_composer,
        post_reader          => $post_reader,
        post_store           => $post_store,
        thread_composer      => $thread_composer,
        thread_detail_reader => $thread_detail_reader,
        thread_store         => $thread_store,
    );

    my $result = $workflow->create_thread(
        {
            author_user_id => $user_id,
            body_source    => $markdown,
            category_id    => $category_id,
            command_id     => $command_id,
            title          => $title,
            viewer         => $viewer,
        }
    );
    if ( $result->{ok} ) {
        my $thread = $result->{stored}{thread};  # a Thread row
    }
    elsif ( $result->{status} eq 'invalid' ) {
        # $result->{prepared}{errors}, $result->{prepared}{values}
    }

    $workflow->create_reply(
        {
            author_user_id => $user_id,
            body_source    => $markdown,
            command_id     => $reply_command_id,
            thread_id      => $thread_id,
            viewer         => $viewer,
        }
    );

=head1 DESCRIPTION

The write side of the forum for its controllers: a new thread, a reply, and
an author's title edit, move, delete and restore of a thread, and edit,
delete and restore of a post. Each method checks the request, has a composer
validate it and build the command where there is something to validate,
hands the command to the store, and answers with one result shape.

The author acts as a reader (ADR 0102): the category and the thread are
read through the category reader and the thread detail reader as the
request's C<viewer>, or as an anonymous reader when there is none, so a
write never reaches what its author cannot read, and what they cannot read
is answered as not found. Only the author of a thread or a post may change
it, and not while it is hidden or its thread is locked: the rules of
L<GPForum::Domain::Thread> and L<GPForum::Domain::Post>, which the stores
ask again under their row locks. A new thread or reply
may not ask for a visibility broader than the effective visibility of the
category or thread it goes in, which the composer gets as its floor.

The store checks again, under its row locks, what the workflow checked
before the transaction, because a moderator may have locked or hidden the
thread or the post since, or the author deleted or restored one in another
tab. Its refusal is an answer, not a failure: the status
L<GPForum::Domain::Post/status_of> gives the same words, which is the status
the workflow's own check gives (C<thread not found> and C<post not found>
are C<not_found>, C<thread is locked> and C<post is hidden> C<forbidden>).

On PostgreSQL a reply is one call (ADR 0126): C<api.forum_create_reply_v1>
runs the command log's steps and the post store's write, under the same
locks in the same order, and records the same rows. The workflow keeps what
is not the database's: the request's fingerprint, the ids and the clock,
the check before the lock (the thread as the author reads it, through the
thread detail reader) and the composer, whose refusal is the response the
function records. A body that may mention someone (it holds an at sign)
has the function's call and the mention store's work in one transaction,
as the command's transaction held them; any other is one statement. The
answers, the log lines and the rows are the Perl path's, which in-memory
doubles keep.

Every method needs a command id. With a C<command_idempotency>
(L<GPForum::Service::Operations::CommandIdempotency>), a command runs once
per id: the request (the author and the trimmed fields each entry names,
the body as a SHA-256 hash of the trimmed source, but not the C<viewer> or
an C<edit_reason>) and the response are kept in the command log, a repeat of
the same request gets the response back without running anything, and a
different request under the same id is refused as a conflict. A C<failed>
result is not kept, so the same id can be tried again. Without a
C<command_idempotency>, every call runs.

After a new thread, a reply or a post edit is stored, the mentions in its
body are recorded through the mention store, at most ten; a failure there is
logged as a warning and does not fail the write.

=head1 SUBROUTINES/METHODS

Every method below takes one hash reference with C<command_id> (or
C<idempotency_key> when C<command_id> is empty; both are trimmed),
C<author_user_id>, the acting user (trimmed, as the requester the rules
check and the stores record), and an optional C<viewer>, a
L<GPForum::Service::Forum::Viewer> (anonymous when absent), plus the fields
named in its entry. It returns a hash reference:

    {
        ok       => 1 or 0,     # 1 only when status is 'ok'
        status   => $status,    # ok, invalid, not_found, forbidden,
                                # conflict or failed
        error    => $message,   # why, for every status but ok and invalid
        prepared => $prepared,  # the composer's answer, if one ran, on ok
                                # and invalid
        stored   => $stored,    # the store's answer, on ok
    }

A store's refusal or death is answered without C<prepared> or C<stored>;
only a C<failed> for a store answer that is neither a success nor a known
refusal carries that answer in C<stored>.

Every method also answers:

=over 4

=item * C<invalid>, with
C<< prepared => { ok => 0, errors => { command_id => 'command_id is required' }, values => { %input } } >>,
when the command id is empty;

=item * C<conflict>, with the command log's message, when the id was used
for another request or that command is still running;

=item * C<failed> with C<command log failed> when the command log fails, or
when anything the command runs dies (with a C<command_idempotency> only);

=item * C<failed> with C<thread store failed> or C<post store failed> when
the store dies or gives an answer that is neither a success nor one of the
refusals above;

=item * on a replay, the stored response as a result with C<< idempotent => 1 >>,
C<prepared> rebuilt for an C<invalid> answer, and C<stored> rebuilt from the
ids kept in the response, as each entry says.

=back

=head2 new

Constructor (L<GPForum::Base>). The collaborators are required, and a
missing or undefined one throws L<GPForum::X::Argument>
(C<GPForum::Service::Forum::PostingWorkflow requires NAME, ...>):
C<category_reader> (L<GPForum::Service::Forum::CategoryReader>),
C<thread_detail_reader> (L<GPForum::Service::Forum::ThreadDetailReader>),
C<post_reader> (L<GPForum::Service::Forum::PostReader>), C<thread_composer>
(L<GPForum::Service::Forum::ThreadComposer>), C<post_composer>
(L<GPForum::Service::Forum::PostComposer>), C<thread_store>
(L<GPForum::Service::Forum::ThreadStore>), C<post_store>
(L<GPForum::Service::Forum::PostStore>) and C<mention_store>
(L<GPForum::Service::Community::MentionStore>). C<command_idempotency> and
C<logger> (anything with C<error> and C<warn>, such as L<Mojo::Log>) are
optional. C<functions> defaults to the L<GPForum::Infrastructure::SqlFunction>
of the post store's schema when there is a command log and a
L<GPForum::Service::Forum::PostStore> on PostgreSQL, else undef; undef keeps
the Perl path for replies. C<codec> defaults to L<GPForum::Service::Forum::PostingCommand>,
which encodes the request, the response and the replay of each command type
for the command log.

=head2 create_thread

Takes C<category_id>, C<title>, C<body_source> and an optional
C<visibility>. Returns C<not_found> (C<category not found>) when a category
id is given that the viewer cannot read, and C<invalid> with the composer's
answer when L<GPForum::Service::Forum::ThreadComposer/prepare> rejects the
input (an empty category id among the reasons). Otherwise stores the thread
with L<GPForum::Service::Forum::ThreadStore/create_thread>, records the
mentions in the opening post, and returns C<ok> with C<prepared> (holding
the command) and C<stored>, the store's answer (C<thread>, C<post> and
C<skipped>). Command type C<thread.create>; a replay's C<stored> is
C<< { ok => 1, thread => { thread_id }, post => { post_id } } >>.

=head2 create_reply

Takes C<thread_id>, C<body_source> and an optional C<visibility>. Returns
C<not_found> (C<thread not found>) when the viewer cannot read the thread,
C<forbidden> (C<thread is locked>) when it is locked, and C<invalid> when
L<GPForum::Service::Forum::PostComposer/prepare> rejects the input.
Otherwise stores the post, at the thread's next position, with
L<GPForum::Service::Forum::PostStore/create_post>, records its mentions, and
returns C<ok> with C<prepared> and C<stored>, the post store's answer; a
refusal of the post store is answered as described above. Command type
C<reply.create>; a replay's C<stored> is
C<< { ok => 1, post => { post_id, thread_id } } >>.

=head2 edit_thread

Takes C<thread_id> and C<title>. Returns C<not_found> (C<thread not found>)
when the viewer cannot read the thread or it is deleted; C<forbidden> when
the requester is not its author (C<not the thread author>), its moderation
state is C<hidden> (C<thread is hidden>) or it is locked
(C<thread is locked>); and C<invalid> when
L<GPForum::Service::Forum::ThreadComposer/prepare_title> rejects the title.
Otherwise stores the new title and slug with
L<GPForum::Service::Forum::ThreadStore/edit_thread> and returns C<ok> with
C<prepared> and C<stored> (C<thread>, and C<skipped> when nothing changed);
a refusal of the thread store is answered as described above. Command type
C<thread.edit>; a replay's C<stored> is
C<< { ok => 1, thread => { thread_id, title, slug } } >>.

=head2 move_thread

Takes C<thread_id> and C<category_id>, the target. Gives the C<not_found>
and C<forbidden> answers of L</edit_thread>, so only the thread's author may
move it; then C<not_found> (C<category not found>) when a target id is given
that the viewer cannot read, and C<invalid> when
L<GPForum::Service::Forum::ThreadComposer/prepare_move> rejects the input
(an empty target among the reasons). Otherwise moves the thread with
L<GPForum::Service::Forum::ThreadStore/move_thread> and returns C<ok> with
C<prepared> and C<stored> (C<thread>, and C<skipped> when it was already
there); a refusal of the thread store is answered as described above.
Command type C<thread.move>; a replay's C<stored> is
C<< { ok => 1, thread => { thread_id, category_id } } >>.

=head2 delete_thread

Takes C<thread_id>. Gives the C<not_found> and C<forbidden> answers of
L</edit_thread>; there is nothing to validate, so no composer runs and
C<prepared> is undefined. Otherwise soft-deletes the thread with
L<GPForum::Service::Forum::ThreadStore/delete_thread>, the requester as
C<deleted_by>, and returns C<ok> with C<stored> (C<thread>); a refusal of
the thread store is answered as described above. Command type
C<thread.delete>; a replay's C<stored> is
C<< { ok => 1, thread => { thread_id } } >>.

=head2 restore_thread

Takes C<thread_id>. Returns C<not_found> (C<thread not found>) unless the
viewer can read the thread and it is deleted (the thread detail reader shows
a deleted thread to its author only), then the C<forbidden> answers of
L</edit_thread>. Otherwise restores the thread with
L<GPForum::Service::Forum::ThreadStore/restore_thread>, the requester as
C<restored_by>, and returns C<ok> with C<stored> (C<thread>); a refusal of
the thread store is answered as described above. Command type
C<thread.restore>; replayed as L</delete_thread> is.

=head2 edit_post

Takes C<post_id>, C<body_source> and an optional C<edit_reason>. Returns
C<not_found> with C<post not found> when the post is missing or deleted, and
with C<thread not found> when the viewer cannot read its thread; C<forbidden>
when the requester is not its author (C<not the post author>), the post is
hidden (C<post is hidden>: it has a C<hidden_at>, or its moderation state is
C<hidden>) or the thread is locked (C<thread is locked>); and C<invalid>
when L<GPForum::Service::Forum::PostComposer/prepare_revision> rejects the
input. Otherwise stores the new revision with
L<GPForum::Service::Forum::PostStore/edit_post>, records the mentions in the
new body, and returns C<ok> with C<prepared> and C<stored>, the post store's
answer. Command type C<post.edit>; a replay's C<stored> is
C<< { ok => 1, post => { post_id, thread_id } } >>.

=head2 delete_post

Takes C<post_id>. Gives the C<not_found> and C<forbidden> answers of
L</edit_post>; no composer runs. Otherwise soft-deletes the post with
L<GPForum::Service::Forum::PostStore/delete_post>, the requester as
C<deleted_by>, and returns C<ok> with C<stored>. Command type
C<post.delete>; replayed as L</edit_post> is.

=head2 restore_post

Takes C<post_id>. Returns C<not_found> with C<post not found> unless the
post is deleted, and with C<thread not found> when the viewer cannot read
its thread; then the C<forbidden> answers of L</edit_post>. Otherwise
restores the post with L<GPForum::Service::Forum::PostStore/restore_post>,
the requester as C<restored_by>, and returns C<ok> with C<stored>. Command
type C<post.restore>; replayed as L</edit_post> is.

=head1 DIAGNOSTICS

A store's or the command log's error is caught and logged through C<logger>
at error level (C<thread create failed>, C<reply create failed>,
C<thread edit failed>, C<thread move failed>, C<thread delete failed>,
C<thread restore failed>, C<post edit failed>, C<post delete failed>,
C<post restore failed> or C<command log failed>, followed by the error), and
the result is C<failed>. A mention store error is logged at warning level as
C<mention recording degraded>. Without a C<command_idempotency>, an error in
a reader or a composer dies out of the method; with one, it is caught as
C<command log failed>. Nothing is logged without a C<logger>. A missing
collaborator throws L<GPForum::X::Argument> from L</new>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Domain::Post>, L<GPForum::Domain::Thread>,
L<GPForum::Service::Forum::Viewer>, L<GPForum::Service::Forum::Visibility>,
L<GPForum::Service::Forum::PostingCommand>,
L<GPForum::Infrastructure::Row>, L<GPForum::Base>, L<Const::Fast>,
L<Mojo::Base>, and the collaborators listed under L</new>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A replay rebuilds C<stored> from the response kept in the command log, so it
holds only the ids (and, for a title edit or a move, the new title and slug
or category), not the rows a first run returns.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
