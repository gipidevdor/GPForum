# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::Event;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Infrastructure::Row qw(column_of);

our $VERSION = '0.001';

const my $SCHEMA_VERSION   => 1;
const my $TARGET_ACTION    => 'moderation_action';
const my $REVERSED         => 'moderation_action.reversed';
const my $REPORT_AGGREGATE => 'report';
const my $REPORT_CREATED   => 'report.created';
const my $REPORT_DUPLICATE => 'report.duplicate_blocked';
const my $USER_AGGREGATE   => 'user';

sub action_payload ( $, $action ) {
    return {
        metadata             => column_of( $action, 'metadata' ),
        moderation_action_id => column_of( $action, 'moderation_action_id' ),
        reason               => column_of( $action, 'reason' ),
        target_id            => column_of( $action, 'target_id' ),
        target_type          => column_of( $action, 'target_type' ),
    };
}

sub action_envelope ( $self, $input ) {
    my $action      = $input->{action};
    my $action_type = column_of( $action, 'action_type' );
    my $target_type = column_of( $action, 'target_type' );
    my $target_id   = column_of( $action, 'target_id' );
    my $action_id   = column_of( $action, 'moderation_action_id' );

    return {
        actor_id          => column_of( $action, 'actor_user_id' ),
        aggregate_id      => $target_id,
        aggregate_type    => $target_type,
        aggregate_version => $SCHEMA_VERSION,
        causation_id      => undef,
        correlation_id    => $input->{correlation_id},
        event_type        => $action_type,
        idempotency_key   =>
          join( q{:}, $action_type, $target_type, $target_id, $action_id ),
        payload   => $self->action_payload($action),
        timestamp => column_of( $action, 'created_at' ),
    };
}

sub action_audit ( $, $input ) {
    my $action = $input->{action};

    return {
        action         => column_of( $action, 'action_type' ),
        actor_id       => column_of( $action, 'actor_user_id' ),
        correlation_id => $input->{correlation_id},
        created_at     => column_of( $action, 'created_at' ),
        metadata       => {
            moderation_action_id =>
              column_of( $action, 'moderation_action_id' ),
            reason => column_of( $action, 'reason' ),
        },
        schema_version => $SCHEMA_VERSION,
        target_id      => column_of( $action, 'target_id' ),
        target_type    => column_of( $action, 'target_type' ),
    };
}

sub reversal_payload ( $, $input ) {
    my $action = $input->{action};

    return {
        moderation_action_id => $input->{action_id},
        original_action_type => column_of( $action, 'action_type' ),
        reason               => $input->{reason},
        reversed_at          => $input->{reversed_at},
        reversed_by_user_id  => $input->{reversed_by_user_id},
        target_id            => column_of( $action, 'target_id' ),
        target_type          => column_of( $action, 'target_type' ),
    };
}

sub reversal_envelope ( $self, $input ) {
    return {
        actor_id          => $input->{reversed_by_user_id},
        aggregate_id      => $input->{action_id},
        aggregate_type    => $TARGET_ACTION,
        aggregate_version => $SCHEMA_VERSION,
        causation_id      => undef,
        correlation_id    => $input->{correlation_id},
        event_type        => $REVERSED,
        idempotency_key   => join( q{:}, $REVERSED, $input->{action_id} ),
        payload           => $self->reversal_payload($input),
        timestamp         => $input->{reversed_at},
    };
}

sub reversal_audit ( $, $input ) {
    my $action = $input->{action};

    return {
        action         => $REVERSED,
        actor_id       => $input->{reversed_by},
        correlation_id => $input->{correlation_id},
        created_at     => $input->{reversed_at},
        metadata       => {
            moderation_action_id =>
              column_of( $action, 'moderation_action_id' ),
            original_action_type => column_of( $action, 'action_type' ),
            reason               => $input->{reason},
        },
        schema_version => $SCHEMA_VERSION,
        target_id      => column_of( $action, 'target_id' ),
        target_type    => column_of( $action, 'target_type' ),
    };
}

sub report_created_payload ( $, $report ) {
    return {
        reason      => column_of( $report, 'reason' ),
        report_id   => column_of( $report, 'report_id' ),
        target_id   => column_of( $report, 'target_id' ),
        target_type => column_of( $report, 'target_type' ),
    };
}

sub report_created_envelope ( $self, $input ) {
    my $report    = $input->{report};
    my $report_id = column_of( $report, 'report_id' );

    return {
        actor_id          => column_of( $report, 'reporter_user_id' ),
        aggregate_id      => $report_id,
        aggregate_type    => $REPORT_AGGREGATE,
        aggregate_version => $SCHEMA_VERSION,
        causation_id      => undef,
        correlation_id    => $input->{correlation_id},
        event_type        => $REPORT_CREATED,
        idempotency_key   => join( q{:}, $REPORT_CREATED, $report_id ),
        payload           => $self->report_created_payload($report),
        timestamp         => column_of( $report, 'created_at' ),
    };
}

sub report_created_audit ( $, $input ) {
    my $report = $input->{report};

    return {
        action         => $REPORT_CREATED,
        actor_id       => column_of( $report, 'reporter_user_id' ),
        correlation_id => $input->{correlation_id},
        created_at     => column_of( $report, 'created_at' ),
        metadata       => {
            reason    => column_of( $report, 'reason' ),
            report_id => column_of( $report, 'report_id' ),
        },
        schema_version => $SCHEMA_VERSION,
        target_id      => column_of( $report, 'target_id' ),
        target_type    => column_of( $report, 'target_type' ),
    };
}

sub report_duplicate_audit ( $, $input ) {
    return {
        action     => $REPORT_DUPLICATE,
        actor_id   => $input->{reporter_user_id},
        created_at => $input->{created_at},
        metadata   => {
            existing_report_id => column_of( $input->{duplicate}, 'report_id' ),
            reason             => $input->{reason},
        },
        schema_version => $SCHEMA_VERSION,
        target_id      => $input->{target_id},
        target_type    => $input->{target_type},
    };
}

sub report_transition_envelope ( $, $input ) {
    my $report    = $input->{report};
    my $report_id = column_of( $report, 'report_id' );

    return {
        actor_id          => $input->{actor_id},
        aggregate_id      => $report_id,
        aggregate_type    => $REPORT_AGGREGATE,
        aggregate_version => $SCHEMA_VERSION,
        causation_id      => undef,
        correlation_id    => $input->{correlation_id},
        event_id          => $input->{event_id},
        event_type        => $input->{event_type},
        idempotency_key   =>
          join( q{:}, $input->{event_type}, $report_id, $input->{event_id} ),
        payload => {
            report_id   => $report_id,
            target_id   => column_of( $report, 'target_id' ),
            target_type => column_of( $report, 'target_type' ),
            %{ $input->{payload} },
        },
        timestamp => $input->{created_at},
    };
}

sub report_transition_audit ( $, $input ) {
    my $report = $input->{report};

    return {
        action         => $input->{action},
        actor_id       => $input->{actor_id},
        correlation_id => $input->{correlation_id},
        created_at     => $input->{created_at},
        metadata       => {
            report_id => column_of( $report, 'report_id' ),
            %{ $input->{metadata} },
        },
        schema_version => $SCHEMA_VERSION,
        target_id      => column_of( $report, 'target_id' ),
        target_type    => column_of( $report, 'target_type' ),
    };
}

sub suspension_envelope ( $, $input ) {
    return {
        actor_id          => $input->{actor_id},
        aggregate_id      => $input->{user_id},
        aggregate_type    => $USER_AGGREGATE,
        aggregate_version => $SCHEMA_VERSION,
        causation_id      => undef,
        correlation_id    => $input->{correlation_id},
        event_type        => $input->{action},
        idempotency_key   => join( q{:},
            $input->{action}, $input->{user_id}, $input->{created_at} ),
        payload   => $input->{payload},
        timestamp => $input->{created_at},
    };
}

sub suspension_audit ( $, $input ) {
    return {
        action         => $input->{action},
        actor_id       => $input->{actor_id},
        correlation_id => $input->{correlation_id},
        created_at     => $input->{created_at},
        metadata       => $input->{metadata},
        schema_version => $SCHEMA_VERSION,
        target_id      => $input->{user_id},
        target_type    => $USER_AGGREGATE,
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Moderation::Event - Moderation event and audit hashes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $event = $events->action_envelope(
        {
            action         => $action,
            correlation_id => $correlation_id,
        }
    );

=head1 DESCRIPTION

Owns moderation-action, report, and suspension EventLog envelopes, payloads,
and AuditLog hashes. It does not persist rows.
L<GPForum::Service::Moderation::ActionStore>,
L<GPForum::Service::Moderation::ReportStore>, and
L<GPForum::Service::Moderation::SuspensionStore> still write EventLog,
OutboxMessage, and AuditLog.

=head1 SUBROUTINES/METHODS

=head2 action_payload

Returns the created-action EventLog payload.

=head2 action_envelope

Returns EventLog arguments for a created moderation action.

=head2 action_audit

Returns AuditLog arguments for a created moderation action.

=head2 reversal_payload

Returns the reversal EventLog payload.

=head2 reversal_envelope

Returns EventLog arguments for a reversed moderation action.

=head2 reversal_audit

Returns AuditLog arguments for a reversed moderation action.

=head2 report_created_payload

Returns the created-report EventLog payload.

=head2 report_created_envelope

Returns EventLog arguments for a created report.

=head2 report_created_audit

Returns AuditLog arguments for a created report.

=head2 report_duplicate_audit

Returns AuditLog arguments for a blocked duplicate report.

=head2 report_transition_envelope

Returns EventLog arguments for assign, release, or resolve.

=head2 report_transition_audit

Returns AuditLog arguments for assign, release, or resolve.

=head2 suspension_envelope

Returns EventLog arguments for suspend or revoke.

=head2 suspension_audit

Returns AuditLog arguments for suspend or revoke.

=head1 DIAGNOSTICS

None. Persistence errors stay in the stores.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Uses L<Const::Fast> and L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None. Store writes remain on the moderation stores.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
