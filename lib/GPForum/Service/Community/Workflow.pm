# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::Workflow;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Text qw(trimmed);
use GPForum::Log;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Service::WorkflowResult
  qw(log_error missing_command_id workflow_result);

use Scalar::Util qw(blessed);

our $VERSION = '0.001';

const my $REPORT_DETAILS_MAX => 2_000;
const my $REPORT_REASON_MAX  => 80;
const my %NATIVE_METHOD => map { $_ => 1 }
  qw(save_bookmark remove_bookmark like_post unlike_post react_post unreact_post
  save_subscription mute_subscription revoke_subscription);
const my %PUBLIC_FIELDS => (
    bookmark => [
        qw(bookmark_id created_at deleted_at note ok target_id target_type user_id)
    ],
    like     => [qw(like_count liked ok post_id thread_id user_id)],
    reaction =>
      [qw(ok post_id reacted reaction reaction_count thread_id user_id)],
    report => [
        qw(created_at details reason report_id reporter_user_id status target_id
          target_type)
    ],
    subscription => [
        qw(created_at muted_at ok preference revoked_at subscription_id target_id
          target_type user_id)
    ],
);

__PACKAGE__->requires(
    qw(bookmark_store like_store report_store subscription_store));
has command_idempotency => undef;    # optional: writes run unlogged without one
has reaction_store      => undef;    # optional: without it reactions throw
has logger              => undef;    # optional: errors are dropped without one

# The stores' call layer (Infrastructure::SqlFunction) on PostgreSQL, undef
# on a double: with it and a command log, a bookmark or a subscription is
# one call.
has functions => sub ($self) {
    my $store = $self->bookmark_store;
    return blessed $store && $store->can('functions')
      ? $store->functions
      : undef;
};

sub save_bookmark ( $self, $input ) {
    return $self->_commanded_op(
        {
            command_type => 'community.bookmark',
            function     => 'community_bookmark_command',
            input        => $input,
            kind         => 'bookmark',
            not_found    => 'bookmark not found',
            request      => {
                %{ _target_request($input) }, note => $input->{note} || q{},
            },
            row => sub {
                return $self->bookmark_store->new_bookmark_row(
                    _target_write($input) );
            },
            run => sub {
                return $self->bookmark_store->save_bookmark(
                    _target_write($input) );
            },
        }
    );
}

sub remove_bookmark ( $self, $input ) {
    return $self->_commanded_op(
        {
            command_type => 'community.bookmark_remove',
            function     => 'community_target_command',
            input        => $input,
            kind         => 'bookmark',
            not_found    => 'bookmark not found',
            request      => _target_request($input),
            row          => sub {
                return _target_command_row( $input, $self->bookmark_store );
            },
            run => sub {
                return $self->bookmark_store->remove_for_user_target(
                    _target_write($input) );
            },
        }
    );
}

# A like is one command around api.community_like_post_v1; taking it back,
# one around api.community_unlike_post_v1 (ADR 0129).
sub like_post ( $self, $input ) {
    return $self->_commanded_op(
        {
            command_type => 'community.like',
            function     => 'community_like_command',
            input        => $input,
            kind         => 'like',
            not_found    => 'post not found',
            request      => _like_request($input),
            row => sub { return $self->like_store->new_like_row($input); },
            run => sub { return $self->like_store->like($input); },
        }
    );
}

sub unlike_post ( $self, $input ) {
    return $self->_commanded_op(
        {
            command_type => 'community.unlike',
            function     => 'community_unlike_command',
            input        => $input,
            kind         => 'like',
            not_found    => 'post not found',
            request      => _like_request($input),
            row => sub { return $self->like_store->new_like_row($input); },
            run => sub { return $self->like_store->unlike($input); },
        }
    );
}

sub _like_request ($input) {
    return {
        post_id => $input->{post_id},
        user_id => $input->{user_id},
    };
}

# A reaction is one command around api.community_react_post_v1; taking it
# back, one around api.community_unreact_post_v1 (ADR 0145).
sub react_post ( $self, $input ) {
    return $self->_reaction_op( 'community.react', 'community_react_command',
        'react', $input );
}

sub unreact_post ( $self, $input ) {
    return $self->_reaction_op( 'community.unreact',
        'community_unreact_command', 'unreact', $input );
}

sub _reaction_op ( $self, $command_type, $function, $method, $input ) {
    my $store = $self->reaction_store // GPForum::X::Argument->throw(
        message => 'reactions need a reaction store' );
    return $self->_commanded_op(
        {
            command_type => $command_type,
            function     => $function,
            input        => $input,
            kind         => 'reaction',
            not_found    => 'post not found',
            request      => {
                %{ _like_request($input) }, reaction => $input->{reaction},
            },
            row => sub { return $store->new_reaction_row($input); },
            run => sub { return $store->$method($input); },
        }
    );
}

sub save_subscription ( $self, $input ) {
    return $self->_commanded_op(
        {
            command_type => 'community.subscribe',
            function     => 'community_subscribe_command',
            input        => $input,
            kind         => 'subscription',
            not_found    => 'subscription not found',
            request      => {
                %{ _target_request($input) },
                preference => $input->{preference} || 'all',
            },
            row => sub {
                return $self->subscription_store->new_subscription_row(
                    _subscription_write($input) );
            },
            run => sub {
                return $self->subscription_store->save_subscription(
                    _subscription_write($input) );
            },
        }
    );
}

sub mute_subscription ( $self, $input ) {
    return $self->_commanded_op(
        {
            command_type => 'community.subscription_mute',
            function     => 'community_target_command',
            input        => $input,
            kind         => 'subscription',
            not_found    => 'subscription not found',
            request      => _target_request($input),
            row          => sub {
                return _target_command_row( $input, $self->subscription_store );
            },
            run => sub {
                return $self->subscription_store->mute_for_user_target(
                    _target_write($input) );
            },
        }
    );
}

sub revoke_subscription ( $self, $input ) {
    return $self->_commanded_op(
        {
            command_type => 'community.unsubscribe',
            function     => 'community_target_command',
            input        => $input,
            kind         => 'subscription',
            not_found    => 'subscription not found',
            request      => _target_request($input),
            row          => sub {
                return _target_command_row( $input, $self->subscription_store );
            },
            run => sub {
                return $self->subscription_store->revoke_for_user_target(
                    _target_write($input) );
            },
        }
    );
}

# A report needs a reason, and both its reason and its details have a
# length limit.
sub create_report ( $self, $input ) {
    my $refused = _report_refusal($input);
    return $refused if $refused;

    return $self->_commanded_op(
        {
            %{ _report_job($input) },
            run => sub {
                return $self->report_store->create_report(
                    _report_request($input) );
            },
        }
    );
}

# The report on the worker's pooled asynchronous connections: the command
# log's steps and the store's writes commit in one transaction.
async sub create_report_p ( $self, $input, $context = undef ) {
    my $refused = _report_refusal($input);
    return $refused if $refused;
    my $store = $self->report_store;
    my $log   = $self->command_idempotency;
    return $self->create_report($input)
      if !$store->can('create_report_p')
      || !_call_layer($store)
      || ( $log && !_call_layer($log) );

    my $job   = _report_job($input);
    my $run_p = async sub ( $scope = undef ) {
        my ( $value, $failure );
        try {
            $value =
              await $store->create_report_p( _report_request($input), $context,
                $scope );
        }
        catch ($error) { $failure = $error; };
        return $self->_stored_answer( $job, $value, $failure );
    };
    return await $run_p->() if !$log;

    my $log_context = GPForum::Log->request_context;
    my $result;
    try {
        $result = await $log->result_of_p(
            {
                actor_id     => $job->{input}{user_id},
                command_id   => $job->{input}{command_id},
                command_type => $job->{command_type},
                request      => $job->{request},
                run_p        => $run_p,
            },
            $context
        );
    }
    catch ($error) {
        GPForum::Log->in_context(
            $log_context,
            sub {
                log_error( $self->logger,
                    "community command log failed: $error" );
                return;
            }
        );
        return _failed_result();
    };
    return $result;
}

sub _report_refusal ($input) {
    my $invalid = missing_command_id($input);
    return $invalid if $invalid;

    my %errors;
    my $reason = trimmed( $input->{reason} );
    if ( !length $reason ) {
        $errors{reason} = 'reason is required';
    }
    if ( length $reason > $REPORT_REASON_MAX ) {
        $errors{reason} = 'reason is too long';
    }
    if ( length( trimmed( $input->{details} ) ) > $REPORT_DETAILS_MAX ) {
        $errors{details} = 'details are too long';
    }
    return undef if !%errors;
    return workflow_result(
        error  => 'invalid report',
        errors => \%errors,
        status => 'invalid',
    );
}

sub _report_job ($input) {
    return {
        command_type => 'community.report',
        input        => {
            %{$input}, user_id => $input->{reporter_user_id},
        },
        kind      => 'report',
        not_found => 'report not found',
        request   => _report_request($input),
    };
}

# The store's answer under the command id: a store that dies fails the
# command and is logged; one that answers nothing, or ok => 0 with its
# reason, is not found; any other answer is reduced to the public fields of
# its kind. Without a command log the write just runs.
sub _commanded_op ( $self, $job ) {
    return $job if $self->{native_plan};
    my $invalid = missing_command_id( $job->{input} );
    if ($invalid) {
        return $invalid;
    }
    return $self->_commanded_by_function($job)
      if $job->{function}
      && $self->functions
      && _call_layer( $self->command_idempotency );

    my $run = sub {
        my ( $value, $failure );
        try {
            $value = $job->{run}->();
        }
        catch ($error) { $failure = $error; };
        return $self->_stored_answer( $job, $value, $failure );
    };
    if ( !$self->command_idempotency ) {
        return $run->();
    }

    my $result;
    try {
        $result = $self->command_idempotency->result_of(
            {
                actor_id     => $job->{input}{user_id},
                command_id   => $job->{input}{command_id},
                command_type => $job->{command_type},
                request      => $job->{request},
                run          => $run,
            }
        );
    }
    catch ($error) {
        log_error( $self->logger, "community command log failed: $error" );
        return _failed_result();
    };

    return $result;
}

# The store's answer as the command records it: a store that died failed
# and is logged; no answer, or ok => 0, is not found.
sub _stored_answer ( $self, $job, $value, $failure ) {
    if ( defined $failure ) {
        log_error( $self->logger, "community write failed: $failure" );
        return _failed_result();
    }
    my $answer = ref $value eq 'HASH' ? $value : {};
    if ( !$value || ( exists $answer->{ok} && !$answer->{ok} ) ) {
        return workflow_result(
            error  => $answer->{error} || $job->{not_found},
            status => 'not_found',
        );
    }

    return workflow_result(
        status => 'ok',
        stored => _public_stored( $job->{kind}, $value ),
    );
}

# The command as one call (ADR 0126, section 5): the command log's steps and
# the store's write run in the job's function, which records the answer the
# Perl path records -- the row's public fields under the command id.
sub _commanded_by_function ( $self, $job ) {
    my $row;
    try {
        $row = $self->functions->row(
            $job->{function},
            {
                log    => $self->_command_log($job),
                answer => undef,
                row    => $job->{row}->(),
            }
        );
    }
    catch ($error) {
        log_error( $self->logger, "community command failed: $error" );
        return _failed_result();
    };
    return _commanded_result($row);
}

async sub async_call_p (
    $self, $method, $arguments,
    $context = undef,
    $cancelled = undef
  )
{
    return await $self->create_report_p( @{$arguments}, $context )
      if $method eq 'create_report';

    # The in-memory doubles hold no connection: they answer in the worker.
    return $self->$method( @{$arguments} )
      if !exists $NATIVE_METHOD{$method}
      || @{$arguments} != 1
      || !$self->functions
      || !_call_layer( $self->command_idempotency );
    my $job;
    {
        # Capture the existing pure-data command description. This scope ends
        # before any asynchronous I/O; concurrent requests never share a mode.
        local $self->{native_plan} = 1;    ## no critic (Variables::ProhibitLocalVars) -- synchronous command description only
        $job = $self->$method( @{$arguments} );
    }
    my $invalid = missing_command_id( $job->{input} );
    return $invalid if $invalid;
    my $log_context = GPForum::Log->request_context;
    my $row;
    try {
        $row = await $self->functions->row_p(
            $job->{function},
            {
                log    => $self->_command_log($job),
                answer => undef,
                row    => $job->{row}->(),
            },
            $context
        );
    }
    catch ($error) {
        GPForum::Log->in_context(
            $log_context,
            sub {
                log_error( $self->logger, "community command failed: $error" );
                return;
            }
        );
        return _failed_result();
    };
    return _commanded_result($row);
}

sub _commanded_result ($row) {
    my $outcome = $row->{outcome} // q{};
    return $row->{response}
      if $outcome eq 'recorded' || $outcome eq 'replayed';
    return workflow_result(
        error =>
          GPForum::Service::Operations::CommandIdempotency->refusal_error(
            $outcome),
        status => 'conflict',
    );
}

# The command log's row as CommandIdempotency writes it, with the ids and
# the time drawn in its order: the command's id, its correlation id, its
# time, and then the store's.
sub _command_log ( $self, $job ) {
    my $log = $self->command_idempotency;
    return {
        actor_id               => _nullable( $job->{input}{user_id} ),
        command_id             => $log->id_service->uuid,
        command_correlation_id => $log->id_service->uuid,
        command_at             => $log->clock->now_iso8601,
        command_type           => $job->{command_type},
        idempotency_key        => trimmed( $job->{input}{command_id} ),
        request_hash           => $log->request_hash( $job->{request} ),
    };
}

sub _nullable ($value) {
    return defined $value && length $value ? $value : undef;
}

# A command log that runs on the call layer; a double of it keeps the Perl
# path (ADR 0126, section 10).
sub _call_layer ($service) {
    return blessed $service && $service->can('functions')
      ? $service->functions
      : undef;
}

sub _subscription_write ($input) {
    return {
        preference  => $input->{preference},
        target_id   => $input->{target_id},
        target_type => $input->{target_type},
        user_id     => $input->{user_id},
    };
}

# The fields of a stored row that the answer, and the command log, carry. A
# report store may answer with its row rather than a hash.
sub _public_stored ( $kind, $stored ) {
    my @fields = @{ $PUBLIC_FIELDS{$kind} };
    if ( $kind ne 'report' ) {
        return { map { $_ => $stored->{$_} } @fields };
    }

    $stored ||= {};
    return { map { $_ => scalar _report_value( $stored, $_ ) } @fields };
}

sub _report_value ( $stored, $name ) {
    if ( ref $stored eq 'HASH' ) {
        return $stored->{$name};
    }
    if ( $stored && $stored->can('get_column') ) {
        return $stored->get_column($name);
    }

    return undef;
}

sub _target_request ($input) {
    return {
        target_id   => $input->{target_id},
        target_type => $input->{target_type},
        user_id     => $input->{user_id},
    };
}

sub _target_write ($input) {
    return {
        note        => $input->{note},
        target_id   => $input->{target_id},
        target_type => $input->{target_type},
        user_id     => $input->{user_id},
    };
}

sub _target_command_row ( $input, $store ) {
    return {
        user_id     => _nullable( $input->{user_id} ),
        target_type => $input->{target_type},
        target_id   => _nullable( $input->{target_id} ),
        stamped_at  => $store->clock->now_iso8601,
    };
}

sub _report_request ($input) {
    return {
        details          => trimmed( $input->{details} ),
        reason           => trimmed( $input->{reason} ),
        reporter_user_id => $input->{reporter_user_id},
        target_id        => $input->{target_id},
        target_type      => $input->{target_type},
    };
}

sub _failed_result {
    return workflow_result(
        error  => 'community store failed',
        status => 'failed',
    );
}

1;

__END__

=head1 NAME

GPForum::Service::Community::Workflow - Bookmark, subscription, and report writes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = $workflow->save_bookmark(
        {
            command_id  => $command_id,
            target_id   => $thread_id,
            target_type => 'thread',
            user_id     => $user_id,
        }
    );

=head1 DESCRIPTION

On PostgreSQL, with a command log, a bookmark and a subscription are one
call each: C<api.community_bookmark_command> and
C<api.community_subscribe_command> open the command log's row, write the
store's row and record the answer (ADR 0126, section 5). The call layer is
the stores'; stores that have none, test doubles, write through
C<command_idempotency> as before.

Application boundary for thread bookmark, subscription, and member report
writes from HTTP controllers. Requires C<command_id> and replays from
C<command_log> when the helper is present. Command hashes include actor,
target, and preference, note, or report reason fields only. Stores keep
unique-restore and persistence ownership.

=head1 SUBROUTINES/METHODS

=head2 async_call_p

Dispatch atomic bookmark, like, reaction and subscription commands through native
PostgreSQL promises, preserving their command log and replay responses. A
report goes to L</create_report_p>; the in-memory doubles answer in the
worker, which holds no connection for them.

=head2 save_bookmark

Saves or restores a thread bookmark for the member.

=head2 remove_bookmark

Soft-deletes the member bookmark for a target.

=head2 like_post

Likes a post for a member: C<post_id>, C<user_id>, C<command_id>. Answers
with C<stored> (C<like_count>, C<liked>, C<post_id>, C<thread_id>,
C<user_id>), or C<not_found> for a post that cannot be liked and C<invalid>
for the member's own post.

=head2 unlike_post

Takes a like back; the same answer, with C<liked> 0.


=head2 react_post

Gives one of the four reactions to a post, as one command (ADR 0145).

=head2 unreact_post

Takes a reaction back, as one command.
=head2 save_subscription

Saves or restores a thread subscription for the member.

=head2 mute_subscription

Mutes an existing thread subscription.

=head2 revoke_subscription

Revokes an existing thread subscription.

=head2 create_report

Creates a member report for a thread, post, or profile.

=head2 create_report_p

L</create_report> as a promise, with an optional query context last: the
command log's steps and the report store's writes commit in one transaction
on the worker's pooled asynchronous connections.

=head1 DIAGNOSTICS

Returns C<invalid>, C<not_found>, C<conflict>, or C<failed> statuses instead
of throwing for expected outcomes.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the bookmark store, subscription store, report store, and
command-idempotency helper supplied by the composition root.

=head1 DEPENDENCIES

Uses L<GPForum::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Feed and bookmark listing stay HTTP reads against the existing stores.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
