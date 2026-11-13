# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::Workflow;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use Mojo::Util qw(monkey_patch);

use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Text qw(trimmed);
use GPForum::Log;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Service::WorkflowResult
  qw(log_error missing_command_id workflow_result);
use GPForum::X::Argument;
use GPForum::X::Unavailable;

use Scalar::Util qw(blessed);

our $VERSION = '0.001';

const my $REPORT_DETAILS_MAX => 2_000;
const my $REPORT_REASON_MAX  => 80;
const my %PUBLIC_FIELDS => (
    report => [
        qw(created_at details reason report_id reporter_user_id status target_id
          target_type)
    ],
);

# ADR 0126, section 5: each command is one call, which opens the command
# log's row, writes the store's row and records the answer. A command names
# its type, its function, the request its fingerprint hashes, and the row
# the function writes, which its store draws.
my %COMMAND = (
    save_bookmark => {
        type     => 'community.bookmark',
        function => 'community_bookmark_command',
        request  => sub ($input) {
            return { %{ _target_request($input) },
                note => $input->{note} || q{} };
        },
        row => sub ( $self, $input ) {
            return $self->bookmark_store->new_bookmark_row(
                _target_write($input) );
        },
    },
    remove_bookmark => {
        type     => 'community.bookmark_remove',
        function => 'community_target_command',
        request  => \&_target_request,
        row      => sub ( $self, $input ) {
            return _target_command_row( $input, $self->bookmark_store );
        },
    },

    # A like is one command around api.community_like_post; taking it back,
    # one around api.community_unlike_post (ADR 0129).
    like_post => {
        type     => 'community.like',
        function => 'community_like_command',
        request  => \&_like_request,
        row      => sub ( $self, $input ) {
            return $self->like_store->new_like_row($input);
        },
    },
    unlike_post => {
        type     => 'community.unlike',
        function => 'community_unlike_command',
        request  => \&_like_request,
        row      => sub ( $self, $input ) {
            return $self->like_store->new_like_row($input);
        },
    },

    # A reaction is one command around api.community_react_post; taking it
    # back, one around api.community_unreact_post (ADR 0145).
    react_post => {
        needs    => 'reaction_store',
        type     => 'community.react',
        function => 'community_react_command',
        request  => \&_reaction_request,
        row      => sub ( $self, $input ) {
            return $self->reaction_store->new_reaction_row($input);
        },
    },
    unreact_post => {
        needs    => 'reaction_store',
        type     => 'community.unreact',
        function => 'community_unreact_command',
        request  => \&_reaction_request,
        row      => sub ( $self, $input ) {
            return $self->reaction_store->new_reaction_row($input);
        },
    },
    save_subscription => {
        type     => 'community.subscribe',
        function => 'community_subscribe_command',
        request  => sub ($input) {
            return {
                %{ _target_request($input) },
                preference => $input->{preference} || 'all',
            };
        },
        row => sub ( $self, $input ) {
            return $self->subscription_store->new_subscription_row(
                {
                    preference  => $input->{preference},
                    target_id   => $input->{target_id},
                    target_type => $input->{target_type},
                    user_id     => $input->{user_id},
                }
            );
        },
    },
    mute_subscription => {
        type     => 'community.subscription_mute',
        function => 'community_target_command',
        request  => \&_target_request,
        row      => sub ( $self, $input ) {
            return _target_command_row( $input, $self->subscription_store );
        },
    },
    revoke_subscription => {
        type     => 'community.unsubscribe',
        function => 'community_target_command',
        request  => \&_target_request,
        row      => sub ( $self, $input ) {
            return _target_command_row( $input, $self->subscription_store );
        },
    },
);

__PACKAGE__->requires(
    qw(bookmark_store command_idempotency like_store report_store
      subscription_store)
);
has reaction_store => undef;    # optional: without it reactions throw
has logger         => undef;    # optional: errors are dropped without one

# The stores' call layer (Infrastructure::SqlFunction).
has functions => sub ($self) {
    my $store = $self->bookmark_store;
    return blessed $store && $store->can('functions')
      ? $store->functions
      : undef;
};

# Each command is written once, as its promise method (ADR 0177).
monkey_patch __PACKAGE__,
  map { ( "${_}_p" => _commanded( $COMMAND{$_} ) ) } keys %COMMAND;
GPForum::Infrastructure::SqlFunction->blocking_twins( keys %COMMAND,
    'create_report' );
GPForum::Infrastructure::SqlFunction->blocking_parts(
    qw(command_idempotency report_store));

sub _commanded ($command) {
    return sub ( $self, $input, $context = undef ) {
        return $self->_command_p( $command, $input, $context );
    };
}

# The command's one call; a failure of it is logged and answered failed.
async sub _command_p ( $self, $command, $input, $context ) {
    if ( my $part = $command->{needs} ) {
        my $words = $part =~ tr/_/ /r;
        $self->$part // GPForum::X::Argument->throw(
            message => "the command needs a $words" );
    }
    my $invalid = missing_command_id($input);
    return $invalid if $invalid;
    my $log_context = GPForum::Log->request_context;
    my $row;
    try {
        $row = await $self->_functions->row_p(
            $command->{function},
            {
                log => $self->_command_log(
                    $command->{type}, $input, $command->{request}->($input)
                ),
                answer => undef,
                row    => $command->{row}->( $self, $input ),
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

# A report needs a reason, and both its reason and its details have a
# length limit. The command log's steps and the store's writes commit in
# one transaction.
async sub create_report_p ( $self, $input, $context = undef ) {
    my $refused = _report_refusal($input);
    return $refused if $refused;
    my $store   = $self->report_store;
    my $request = _report_request($input);
    my $run_p   = async sub ( $scope = undef ) {
        my ( $value, $failure );
        try {
            $value =
              await $store->create_report_p( $request, $context, $scope );
        }
        catch ($error) { $failure = $error; };
        return $self->_stored_report( $value, $failure );
    };

    my $log_context = GPForum::Log->request_context;
    my $result;
    try {
        $result = await $self->command_idempotency->result_of_p(
            {
                actor_id     => $input->{reporter_user_id},
                command_id   => $input->{command_id},
                command_type => 'community.report',
                request      => $request,
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

# The report store's answer as the command records it: a store that died
# failed and is logged; no answer, or ok => 0, is not found; any other
# answer is reduced to a report's public fields.
sub _stored_report ( $self, $value, $failure ) {
    if ( defined $failure ) {
        log_error( $self->logger, "community write failed: $failure" );
        return _failed_result();
    }
    my $answer = ref $value eq 'HASH' ? $value : {};
    if ( !$value || ( exists $answer->{ok} && !$answer->{ok} ) ) {
        return workflow_result(
            error  => $answer->{error} || 'report not found',
            status => 'not_found',
        );
    }

    return workflow_result(
        status => 'ok',
        stored => {
            map { $_ => scalar column_of( $value, $_ ) }
              @{ $PUBLIC_FIELDS{report} }
        },
    );
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
sub _command_log ( $self, $type, $input, $request ) {
    my $log = $self->command_idempotency;
    return {
        actor_id               => _nullable( $input->{user_id} ),
        command_id             => $log->id_service->uuid,
        command_correlation_id => $log->id_service->uuid,
        command_at             => $log->clock->now_iso8601,
        command_type           => $type,
        idempotency_key        => trimmed( $input->{command_id} ),
        request_hash           => $log->request_hash($request),
    };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'community commands need the PostgreSQL function layer' );
}

sub _nullable ($value) {
    return defined $value && length $value ? $value : undef;
}

sub _like_request ($input) {
    return {
        post_id => $input->{post_id},
        user_id => $input->{user_id},
    };
}

sub _reaction_request ($input) {
    return { %{ _like_request($input) }, reaction => $input->{reaction} };
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

The members' community commands from the HTTP controllers: bookmarks,
likes, reactions, subscriptions and reports. Each requires C<command_id>;
the same command again replays its answer, and another request under the
same id is a conflict. A command's fingerprint hashes the actor, the target
and its preference, note, reaction or report reason only.

A bookmark, a like, a reaction or a subscription is one call
(ADR 0126, section 5): C<api.community_bookmark_command>,
C<api.community_like_command>, C<api.community_subscribe_command> and their
kin open the command log's row, write the store's row -- which the store
draws, C<new_bookmark_row> and the like -- and record the answer. A report
runs the report store's write under the command log's promise
(L<GPForum::Service::Operations::CommandIdempotency/result_of_p>), in one
transaction. Each command is written once, as its promise method; the
blocking methods are its twins (ADR 0177).

=head1 SUBROUTINES/METHODS

=head2 save_bookmark_p

Saves or restores a thread bookmark for the member.

=head2 remove_bookmark_p

Soft-deletes the member's bookmark on a target.

=head2 like_post_p

Likes a post for a member: C<post_id>, C<user_id>, C<command_id>. Answers
with C<stored> (C<like_count>, C<liked>, C<post_id>, C<thread_id>,
C<user_id>), or C<not_found> for a post that cannot be liked and C<invalid>
for the member's own post.

=head2 unlike_post_p

Takes a like back; the same answer, with C<liked> 0.

=head2 react_post_p

Gives one of the four reactions to a post (ADR 0145). Without a
C<reaction_store> it throws L<GPForum::X::Argument>.

=head2 unreact_post_p

Takes a reaction back.

=head2 save_subscription_p

Saves or restores a thread subscription for the member.

=head2 mute_subscription_p

Mutes an existing thread subscription.

=head2 revoke_subscription_p

Revokes an existing thread subscription.

=head2 create_report_p

Creates a member report for a thread, post, or profile: a reason is
required, and the reason and the details have length limits.

=head2 save_bookmark, remove_bookmark, like_post, unlike_post, react_post, unreact_post, save_subscription, mute_subscription, revoke_subscription, create_report

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), the command log and the report store with it, answering the
value instead of a promise. Every C<_p> method takes the input and an
optional query context.

=head1 DIAGNOSTICS

Returns C<invalid>, C<not_found>, C<conflict>, or C<failed> statuses instead
of throwing for expected outcomes. Without the PostgreSQL function layer a
command raises L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

The bookmark, like, subscription and report stores and the command log,
required, and the reaction store, supplied by the composition root.

=head1 DEPENDENCIES

L<GPForum::Base>, L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Service::Operations::CommandIdempotency>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
