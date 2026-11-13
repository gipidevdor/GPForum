# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::Workflow;

use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Log;
use GPForum::Service::WorkflowResult
  qw(log_error missing_command_id workflow_result);

use Scalar::Util qw(blessed);

our $VERSION = '0.001';

__PACKAGE__->requires(qw(command_idempotency dispatcher preference_store));
has logger => undef;    # optional: errors are dropped without one

# The stores' call layer (Infrastructure::SqlFunction).
has functions => sub ($self) {
    my $store = $self->preference_store;
    return blessed $store && $store->can('functions')
      ? $store->functions
      : undef;
};

# Each command is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(mark_read mark_all_read set_preferences));
GPForum::Infrastructure::SqlFunction->blocking_parts(
    qw(command_idempotency dispatcher preference_store));

async sub mark_read_p ( $self, $input, $context = undef ) {
    return await $self->_run_store_p(
        'notification not found',
        sub {
            return $self->dispatcher->mark_read_p( $input->{notification_id},
                $input->{user_id}, $context );
        },
    );
}

async sub mark_all_read_p ( $self, $input, $context = undef ) {
    return await $self->_run_store_p(
        'notification inbox not found',
        sub {
            return $self->dispatcher->mark_all_read_p( $input->{user_id},
                $context );
        },
    );
}

# The command log's steps and the preference writes commit in one
# transaction.
async sub set_preferences_p ( $self, $input, $context = undef ) {
    my $invalid = missing_command_id($input);
    return $invalid if $invalid;

    my $run_p = async sub ( $scope = undef ) {
        return await $self->_run_store_p(
            'notification preferences not found',
            sub {
                return _preferences_written_p( $self->preference_store,
                    $input, $context, $scope );
            },
        );
    };

    my $log_context = GPForum::Log->request_context;
    my $result;
    try {
        $result = await $self->command_idempotency->result_of_p(
            {
                actor_id     => $input->{user_id},
                command_id   => $input->{command_id},
                command_type => 'notification.preferences',
                request      => _request($input),
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
                    "notification command log failed: $error" );
                return;
            }
        );
        return _failed_result();
    };

    return $result;
}

# ADR 0078: the choices by kind of notification, when the form sent them,
# are checked before the channels are written and stored after.
async sub _preferences_written_p ( $store, $input, $context, $scope ) {
    my $types   = $input->{type_preferences};
    my $refused = defined $types && $store->refused_type_preferences($types);
    return $refused if $refused;
    my $channels = await $store->set_preferences_p(
        {
            preferences => $input->{preferences},
            user_id     => $input->{user_id},
        },
        $context, $scope
    );
    return $channels
      if !defined $types
      || ( ref $channels eq 'HASH' && !$channels->{ok} );
    my $stored = await $store->set_type_preferences_p(
        { preferences => $types, user_id => $input->{user_id} },
        $context, $scope );

    return $stored->{ok} ? $channels : $stored;
}

# What the command log keys the write by: the choices as booleans.
sub _request ($input) {
    my @preferences = map {
        +{
            channel          => $_->{channel},
            digest_frequency => $_->{digest_frequency},
            enabled          => $_->{enabled} ? 1 : 0,
        }
    } @{ $input->{preferences} || [] };
    my $request = {
        preferences => \@preferences,
        user_id     => $input->{user_id},
    };
    if ( defined $input->{type_preferences} ) {
        $request->{type_preferences} = [
            map {
                +{
                    channel    => $_->{channel},
                    enabled    => $_->{enabled} ? 1 : 0,
                    event_type => $_->{event_type},
                }
            } @{ $input->{type_preferences} }
        ];
    }

    return $request;
}

# A store that dies fails the write and is logged; one that answers nothing,
# or ok => 0 with its reason, is not found. A store that refused the input
# (an unknown notification channel) is an invalid request, not a missing
# row: read as not_found, the refusal would answer the settings form with a
# 500 and log a degraded store.
async sub _run_store_p ( $self, $not_found, $code ) {
    my $value;
    try {
        $value = await $code->();
    }
    catch ($error) {
        log_error( $self->logger, "notification write failed: $error" );
        return _failed_result();
    };

    return _store_answer( $not_found, $value );
}

sub _failed_result {
    return workflow_result(
        error  => 'notification store failed',
        status => 'failed',
    );
}

sub _store_answer ( $not_found, $value ) {
    my $answer = ref $value eq 'HASH' ? $value : {};
    if ( !$value ) {
        return workflow_result(
            error  => $not_found,
            status => 'not_found',
        );
    }
    if ( ( $answer->{status} // q{} ) eq 'invalid' ) {
        return workflow_result(
            error  => $answer->{error},
            errors => $answer->{errors},
            status => 'invalid',
        );
    }
    if ( exists $answer->{ok} && !$answer->{ok} ) {
        return workflow_result(
            error  => $answer->{error} || $not_found,
            status => 'not_found',
        );
    }

    return workflow_result(
        status => 'ok',
        stored => $value,
    );
}

1;

__END__

=head1 NAME

GPForum::Service::Notification::Workflow - Notification inbox writes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = $workflow->mark_read(
        {
            notification_id => $notification_id,
            user_id         => $user_id,
        }
    );

=head1 DESCRIPTION

Application boundary for notification inbox and preference writes. Delegates
persistence to the dispatcher and the preference store and returns a
normalized result hash. Those services keep transaction and projection
ownership.

A preference change requires C<command_id>: it runs the preference store's
writes under the command log's promise
(L<GPForum::Service::Operations::CommandIdempotency/result_of_p>), in one
transaction; the same command again replays its answer, and another
request under the same id is a conflict. Each command is written once, as
its promise method; the blocking methods are its twins (ADR 0177), the
command log, the dispatcher and the preference store with it.

=head1 SUBROUTINES/METHODS

Every C<_p> method takes the input and an optional query context.

=head2 mark_read_p

Marks a recipient inbox row read or reports it missing.

=head2 mark_all_read_p

Marks every unread inbox row for the member. An empty inbox is success with
C<marked_count> 0.

=head2 set_preferences_p

Replaces the member notification channel preferences. Requires
C<command_id>. With C<type_preferences> (an array reference of
C<event_type>, C<channel> and C<enabled>, ADR 0078) it also stores the
member's choice for each kind of notification: those are checked first, so
a refused kind writes nothing, and written after the channels.

=head2 mark_read, mark_all_read, set_preferences

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), the command log, the dispatcher and the preference store with
it, answering the value instead of a promise.

=head1 DIAGNOSTICS

Returns C<invalid>, C<not_found>, C<conflict> or C<failed> statuses instead
of throwing for expected write outcomes: C<invalid> (with the store's
C<error> and C<errors>) when the preference store refused the input, such
as an unknown channel. Unexpected store and command log exceptions are
logged and mapped to C<failed>; without the PostgreSQL function layer the
stores raise L<GPForum::X::Unavailable>, answered so.

=head1 CONFIGURATION AND ENVIRONMENT

The command log, the notification dispatcher and the preference store,
required, supplied by the composition root.

=head1 DEPENDENCIES

L<GPForum::Base>, L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Service::Operations::CommandIdempotency>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Inbox and mention reads stay on HTTP controllers and the dispatcher/reader
helpers. Channel catalogs remain on the preference store.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
