# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::Audit;

use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Service::Clock;
use GPForum::Service::Identity::Event;
use GPForum::Service::Identity::MailToken;

our $VERSION = '0.001';

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
has recorder => sub {
    my ($self) = @_;

    return GPForum::Infrastructure::EventRecorder->new(
        id_service => $self->id_service,
        schema     => $self->schema,
    );
};
has schema => undef;          # optional: only the default recorder reads it
has events => sub ($self) {
    return GPForum::Service::Identity::Event->new( clock => $self->clock );
};

# Seals a mail's token for the outbox; the configured signing secrets unless
# given.
has mail_token => sub { return GPForum::Service::Identity::MailToken->new; };

sub record_registration ( $self, $user, $correlation_id ) {
    $self->recorder->record_event(
        %{ $self->events->registered_envelope( $user, $correlation_id ) } );
    $self->recorder->record_audit(
        %{ $self->events->registered_audit( $user, $correlation_id ) } );

    return;
}

# The calls record_registration makes, prepared and not sent, in its order:
# the event, then the audit. For api.identity_register_command, which
# records them in one call with the rest of the registration.
sub registration_calls ( $self, $user, $correlation_id ) {
    my $event = $self->recorder->event_call(
        %{ $self->events->registered_envelope( $user, $correlation_id ) } );
    my $audit = $self->recorder->audit_call(
        %{ $self->events->registered_audit( $user, $correlation_id ) } );
    return { audit => $audit, event => $event };
}

# The call record_action makes, prepared and not sent.
sub action_call ( $self, $input ) {
    return $self->recorder->audit_call( %{ $self->events->action($input) } );
}

# The call record_mail makes, prepared and not sent.
sub mail_call ( $self, $input ) {
    my $mail = $self->_sealed($input);

    return $self->recorder->event_call(
        %{ $self->events->mail_envelope($mail) },
        outbox_payload => $self->events->mail_outbox_payload($mail), );
}

sub record_action ( $self, $input ) {
    $self->recorder->record_audit( %{ $self->events->action($input) } );

    return;
}

sub record_mail ( $self, $input ) {
    my $mail = $self->_sealed($input);
    $self->recorder->record_event( %{ $self->events->mail_envelope($mail) },
        outbox_payload => $self->events->mail_outbox_payload($mail), );

    return;
}

# The mail with its raw token replaced by the token sealed to its id.
sub _sealed ( $self, $input ) {
    if ( !defined $input->{token} ) {
        return $input;
    }
    my %mail  = %{$input};
    my $token = delete $mail{token};
    $mail{sealed_token} = $self->mail_token->seal( $token, $mail{token_id} );

    return \%mail;
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::Audit - Identity domain event and audit writes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $audit = GPForum::Service::Identity::Audit->new( schema => $schema );
    $audit->record_registration( $user, $correlation_id );

=head1 DESCRIPTION

Records registration events/audits, typed identity audit actions, and
identity mail outbox jobs through the shared event recorder. Event and
audit hashes live in L<GPForum::Service::Identity::Event>.

=head1 SUBROUTINES/METHODS

=head2 record_registration

Writes the C<user.registered> event and audit pair.

=head2 registration_calls

Takes the user row and the correlation id L</record_registration> takes and
returns the calls it would make, prepared and not sent, as
L<GPForum::Infrastructure::EventRecorder/event_call> and
L<GPForum::Infrastructure::EventRecorder/audit_call> prepare them: C<event>
and C<audit>, the event drawn first.

=head2 action_call

Takes what L</record_action> takes and returns its audit call, prepared
and not sent.

=head2 mail_call

Takes what L</record_mail> takes and returns its event call with the
mail's outbox payload, prepared and not sent.

=head2 record_action

Writes a generic identity audit row.

=head2 record_mail

Writes C<identity.mail.requested> to EventLog and an outbox row whose
payload includes the raw token under C<mail>. EventLog payload is
C<kind> and C<token_id> only.

=head1 DIAGNOSTICS

Recorder failures propagate to the caller.

=head1 CONFIGURATION AND ENVIRONMENT

Requires a DBIx::Class schema accepted by L<GPForum::Infrastructure::EventRecorder>.

=head1 DEPENDENCIES

Uses L<GPForum::Infrastructure::EventRecorder> and
L<GPForum::Service::Identity::Event>. C<GPForum::Infrastructure::Id> is required
lazily unless an C<id_service> is injected.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

HTTP login/logout request persistence remains on
L<GPForum::Service::Identity::SecurityAudit>.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
