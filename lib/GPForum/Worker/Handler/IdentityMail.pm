# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Worker::Handler::IdentityMail;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my $MAIL_REQUESTED => 'identity.mail.requested';
const my %SEND_METHOD => (
    email_change       => 'send_email_change',
    email_verification => 'send_email_verification',
    password_reset     => 'send_password_reset',
);

const my $SECURITY_PATH => '/settings/security';
const my $RESET_PATH    => '/password/reset';

# Notices that carry no token, in the member's language, each with the page
# it links to. ADR 0142: two-step sign-in was turned on or off, an
# administrator reset it, or ten wrong codes locked it for an hour. ADR
# 0143: an email change was asked for, told to the address it leaves, with
# the password reset that stops it.
const my @SECOND_FACTOR_NOTICES => qw(
  second_factor_enabled
  second_factor_disabled
  second_factor_reset
  second_factor_locked
);
const my %NOTICE => (
    ( map { $_ => $SECURITY_PATH } @SECOND_FACTOR_NOTICES ),
    email_change_notice => $RESET_PATH,
);

has mailer => undef;    # optional: task is only captured

# Opens the sealed token of a mail (Identity::MailToken); the configured
# signing secrets unless given.
has mail_token => sub {
    require GPForum::Service::Identity::MailToken;
    return GPForum::Service::Identity::MailToken->new;
};
has i18n => sub {
    require GPForum::Service::I18N;
    return GPForum::Service::I18N->new;
};
has sink => undef;    # optional: tests capture tasks

sub supports ( $, $event ) {
    return ( $event->{event_type} || q{} ) eq $MAIL_REQUESTED;
}

sub handle ( $self, $event ) {
    my $task = $self->_task($event);
    if ( $self->sink ) {
        $self->sink->capture($task);
    }

    return $self->_deliver( $event, $task );
}

sub _deliver ( $self, $event, $task ) {
    my $mail = $self->_mail($event);
    if ( !$mail ) {
        $task->{skipped} = 1;
        return $task;
    }

    return $self->_send( $mail, $task );
}

sub _mail ( $self, $event ) {
    my $mail = $event->{mail};
    if ( ref $mail ne 'HASH' ) {
        return undef;
    }

    return $self->_complete_mail($mail);
}

sub _complete_mail ( $self, $mail ) {
    if ( !_has_text( $mail->{kind} ) ) {
        return undef;
    }
    if ( !_has_text( $mail->{to} ) ) {
        return undef;
    }
    if ( exists $NOTICE{ $mail->{kind} } ) {
        return $mail;
    }

    # The token waits sealed to its id; one this worker cannot open --
    # sealed under a secret it no longer holds, for another token, or
    # altered -- is not mailed.
    my $token =
      $self->mail_token->unseal( $mail->{sealed_token}, $mail->{token_id} );
    if ( !_has_text($token) ) {
        return undef;
    }

    return { %{$mail}, token => $token };
}

sub _send ( $self, $mail, $task ) {
    return $self->_send_notice( $mail, $task )
      if exists $NOTICE{ $mail->{kind} };

    my $method = $self->_send_method( $mail->{kind} );
    if ( !$method ) {
        $task->{skipped} = 1;
        return $task;
    }
    if ( !$self->mailer ) {
        $task->{skipped} = 1;
        return $task;
    }

    $task->{delivered} = $self->mailer->$method(
        {
            to    => $mail->{to},
            token => $mail->{token},
        }
    );

    return $task;
}

sub _send_notice ( $self, $mail, $task ) {
    if ( !$self->mailer ) {
        $task->{skipped} = 1;
        return $task;
    }

    my $locale = $mail->{locale} || 'en';
    my $base   = $self->mailer->public_base_url;
    $base =~ s{ / \z}{}msx;
    my $kind = $mail->{kind};
    $task->{delivered} = $self->mailer->send_security_notice(
        {
            to      => $mail->{to},
            subject =>
              $self->i18n->translate( $locale, "auth.${kind}_mail_subject" ),
            body => $self->i18n->translate(
                $locale, "auth.${kind}_mail_body",
                { url => $base . $NOTICE{$kind} }
            ),
        }
    );

    return $task;
}

sub _send_method ( $, $kind ) {
    if ( !exists $SEND_METHOD{$kind} ) {
        return undef;
    }

    return $SEND_METHOD{$kind};
}

sub _task ( $, $event ) {
    my $mail = $event->{mail} || {};

    return {
        action   => 'identity.mail',
        event_id => $event->{event_id},
        kind     => $mail->{kind},
        to       => $mail->{to},
    };
}

sub _has_text ($value) {
    if ( !defined $value ) {
        return 0;
    }

    return length $value ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Worker::Handler::IdentityMail - Outbox identity mail delivery.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $handler = GPForum::Worker::Handler::IdentityMail->new(
        mailer => $mailer,
    );
    $handler->handle($event);

=head1 DESCRIPTION

Sends password-reset, email-change, and verification mail for
C<identity.mail.requested> outbox payloads, and the two-step sign-in
notices (ADR 0142) and the notice to the address an email change leaves
(C<email_change_notice>, ADR 0143) in the member's language. The token
waits on the outbox C<mail> hash sealed to its id
(L<GPForum::Service::Identity::MailToken>), never in clear and never on
EventLog; the handler opens it to send, and does not mail one it cannot
open. Delivery is at-least-once: an
outbox retry after send and before C<mark_done> resends from that
payload. Delivery exceptions propagate so the dispatcher can retry.

=head1 SUBROUTINES/METHODS

=head2 supports

True for C<identity.mail.requested>.

=head2 handle

Delivers through L<GPForum::Service::Identity::Mailer> when a complete
mail payload is present.

=head1 DIAGNOSTICS

Mailer transport exceptions propagate to the outbox dispatcher.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the injected identity mailer, which reads C<GPFORUM_MAIL_*>.

=head1 DEPENDENCIES

Uses L<Const::Fast> and L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Does not log the raw token. EventLog payloads must not include it.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
