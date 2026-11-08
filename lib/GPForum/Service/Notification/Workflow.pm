# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::Workflow;

use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::Text    qw(trimmed);
use GPForum::Service::WorkflowResult qw(log_error workflow_result);
our $VERSION = '0.001';

has command_idempotency => undef;    # optional: writes run unlogged without one
__PACKAGE__->requires(qw(dispatcher preference_store));
has logger => undef;                 # optional: errors are dropped without one

sub mark_read ( $self, $input ) {
    return $self->_run_store(
        'notification not found',
        sub {
            return $self->dispatcher->mark_read( $input->{notification_id},
                $input->{user_id} );
        },
    );
}

sub mark_all_read ( $self, $input ) {
    return $self->_run_store(
        'notification inbox not found',
        sub {
            return $self->dispatcher->mark_all_read( $input->{user_id} );
        },
    );
}

async sub mark_read_p ( $self, $input, $context = undef ) {
    return await $self->_run_store_p(
        'notification not found',
        sub {
            return $self->_dispatched_p( 'mark_read', $context,
                $input->{notification_id},
                $input->{user_id} );
        },
    );
}

async sub mark_all_read_p ( $self, $input, $context = undef ) {
    return await $self->_run_store_p(
        'notification inbox not found',
        sub {
            return $self->_dispatched_p( 'mark_all_read', $context,
                $input->{user_id} );
        },
    );
}

# The dispatcher's own promise when it has one; a double answers here.
async sub _dispatched_p ( $self, $method, $context, @arguments ) {
    my $dispatcher = $self->dispatcher;
    my $async      = "${method}_p";
    return await $dispatcher->$async( @arguments, $context )
      if $dispatcher->can($async);
    return $dispatcher->$method(@arguments);
}

sub set_preferences ( $self, $input ) {
    if ( !length trimmed( $input->{command_id} ) ) {
        return workflow_result(
            errors => { command_id => 'command_id is required' },
            status => 'invalid',
        );
    }

    my $run = sub { return $self->_store_preferences($input); };
    if ( !$self->command_idempotency ) {
        return $run->();
    }

    my $result;
    try {
        $result = $self->command_idempotency->result_of(
            {
                actor_id     => $input->{user_id},
                command_id   => $input->{command_id},
                command_type => 'notification.preferences',
                request      => _request($input),
                run          => $run,
            }
        );
    }
    catch ($error) {
        log_error( $self->logger, "notification command log failed: $error" );
        return workflow_result(
            error  => 'notification store failed',
            status => 'failed',
        );
    };

    return $result;
}

# set_preferences on the worker's pooled asynchronous connections: the
# command log's steps and the writes commit in one transaction.
async sub set_preferences_p ( $self, $input, $context = undef ) {
    my $functions = $self->preference_store->can('functions')
      && $self->preference_store->functions;
    return $self->set_preferences($input) if !$functions;
    return workflow_result(
        errors => { command_id => 'command_id is required' },
        status => 'invalid',
    ) if !length trimmed( $input->{command_id} );

    my $run_p = async sub ($scope) {
        return await $self->_store_preferences_p( $input, $context, $scope );
    };
    return await $run_p->($functions) if !$self->command_idempotency;

    my $result;
    try {
        $result = await $self->command_idempotency->result_of_p(
            {
                actor_id     => $input->{user_id},
                command_id   => $input->{command_id},
                command_type => 'notification.preferences',
                request      => _request($input),
                run   => sub { return $self->_store_preferences($input) },
                run_p => $run_p,
            },
            $context
        );
    }
    catch ($error) {
        log_error( $self->logger, "notification command log failed: $error" );
        return workflow_result(
            error  => 'notification store failed',
            status => 'failed',
        );
    };

    return $result;
}

async sub _store_preferences_p ( $self, $input, $context, $scope ) {
    my $value;
    try {
        $value = await _preferences_written_p( $self->preference_store,
            $input, $context, $scope );
    }
    catch ($error) {
        log_error( $self->logger, "notification write failed: $error" );
        return workflow_result(
            error  => 'notification store failed',
            status => 'failed',
        );
    };

    return _store_answer( 'notification preferences not found', $value );
}

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

# ADR 0078: the choices by kind of notification, when the form sent them,
# are checked before the channels are written and stored after.
sub _store_preferences ( $self, $input ) {
    my $types = $input->{type_preferences};
    my $store = $self->preference_store;

    return $self->_run_store(
        'notification preferences not found',
        sub {
            my $refused =
              defined $types && $store->refused_type_preferences($types);
            return $refused if $refused;
            my $channels = $store->set_preferences(
                {
                    preferences => $input->{preferences},
                    user_id     => $input->{user_id},
                }
            );
            return $channels
              if !defined $types
              || ( ref $channels eq 'HASH' && !$channels->{ok} );
            my $stored = $store->set_type_preferences(
                { preferences => $types, user_id => $input->{user_id} } );

            return $stored->{ok} ? $channels : $stored;
        },
    );
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
sub _run_store ( $self, $not_found, $code ) {
    my $value;
    try {
        $value = $code->();
    }
    catch ($error) {
        log_error( $self->logger, "notification write failed: $error" );
        return workflow_result(
            error  => 'notification store failed',
            status => 'failed',
        );
    };

    return _store_answer( $not_found, $value );
}

async sub _run_store_p ( $self, $not_found, $code ) {
    my $value;
    try {
        $value = await $code->();
    }
    catch ($error) {
        log_error( $self->logger, "notification write failed: $error" );
        return workflow_result(
            error  => 'notification store failed',
            status => 'failed',
        );
    };

    return _store_answer( $not_found, $value );
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
persistence to the existing dispatcher and preference store and returns a
normalized result hash. Those services keep transaction and projection
ownership.

=head1 SUBROUTINES/METHODS

=head2 mark_read

Marks a recipient inbox row read or reports it missing.

=head2 mark_all_read

Marks every unread inbox row for the member. An empty inbox is success with
C<marked_count> 0.

=head2 mark_read_p

L</mark_read> as a promise, with an optional query context last, run on the
worker's pooled asynchronous connections.

=head2 mark_all_read_p

L</mark_all_read> as a promise, with an optional query context last, run on
the worker's pooled asynchronous connections.

=head2 set_preferences_p

L</set_preferences> as a promise, with an optional query context last: the
command log's steps and the preference writes commit in one transaction on
the worker's pooled asynchronous connections, no child process.

=head2 set_preferences

Replaces the member notification channel preferences. Requires
C<command_id> and replays from C<command_log> when the helper is present.
With C<type_preferences> (an array reference of C<event_type>, C<channel>
and C<enabled>, ADR 0078) it also stores the member's choice for each kind
of notification: those are checked first, so a refused kind writes
nothing, and written after the channels.

=head1 DIAGNOSTICS

Returns C<invalid>, C<not_found> or C<failed> statuses instead of throwing
for expected write outcomes: C<invalid> (with the store's C<error> and
C<errors>) when the preference store refused the input, such as an unknown
channel. Unexpected store exceptions are logged and mapped to C<failed>.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the notification dispatcher and preference store supplied by the
composition root.

=head1 DEPENDENCIES

Uses L<GPForum::Base>.

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
