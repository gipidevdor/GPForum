# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::Mailer;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Service::Identity::LogTransport;

our $VERSION = '0.001';

const my $DEFAULT_FROM => 'noreply@localhost';
const my $DEFAULT_BASE => 'http://127.0.0.1:3000';
const my $DEFAULT_PORT => 587;

# What GPFORUM_SMTP_TLS names, as Email::Sender::Transport::SMTP's ssl
# argument says it: STARTTLS, or TLS from the first byte (SMTPS). off sends
# nothing for it, and the connection stays in the clear.
const my %SMTP_SECURITY => (
    starttls => 'starttls',
    implicit => 'ssl',
);
const my $IMPLICIT_TLS_PORT => 465;

has config => undef;    # optional: every setting falls back to a default

# The words of a mail with a link, in the member's language.
has i18n => sub {
    require GPForum::Service::I18N;
    return GPForum::Service::I18N->new;
};
has from_address => sub {
    my ($self) = @_;

    return $self->_config_value( 'mail_from', $DEFAULT_FROM );
};
has logger          => undef;    # optional: messages are dropped without one
has public_base_url => sub {
    my ($self) = @_;

    return $self->_config_value( 'public_base_url', $DEFAULT_BASE );
};

# Seconds Email::Sender's SMTP transport waits on each step; undef keeps its
# default of 120. A caller inside a web request needs far less
# (Admin::Diagnostics).
has smtp_timeout => undef;    # optional: Email::Sender keeps its own default
has transport    => sub {
    my ($self) = @_;

    return $self->_build_transport;
};

sub from_config ( $class, $config ) {
    return $class->new( config => $config );
}

sub send_password_reset ( $self, $input ) {
    return $self->_send_link_mail( 'password_reset',
        '/password/reset/' . $input->{token}, $input );
}

sub send_email_change ( $self, $input ) {
    return $self->_send_link_mail( 'email_change',
        '/email/confirm/' . $input->{token}, $input );
}

sub send_email_verification ( $self, $input ) {
    return $self->_send_link_mail( 'email_verification',
        '/email/verify/' . $input->{token}, $input );
}

# The console's test message (Admin::Diagnostics). It only has to arrive, so
# it carries no link and no token.
sub send_test_message ( $self, $input ) {
    return $self->_send_identity_mail(
        {
            body => join( "\n\n",
                'This message was sent from the GPForum admin console to'
                  . ' check that mail is delivered.',
                'No action is needed.' ),
            kind    => 'test_message',
            subject => 'GPForum test message',
            to      => $input->{to},
        }
    );
}

# ADR 0142: a notice about the account's security, in the member's
# language: transactional, so it carries no unsubscribe.
#
# MIME-Header folds a subject longer than a line, which Email::Simple warns
# of in a header value and will refuse; the encoded words read the same on
# one line, and Email::Simple folds the header itself.
sub send_security_notice ( $self, $input ) {
    require Encode;
    my $subject = Encode::encode( 'MIME-Header', $input->{subject} );
    $subject =~ s{ \r?\n [ \t]+ }{ }gmsx;

    return $self->_send_identity_mail(
        {
            body    => Encode::encode( 'UTF-8', $input->{body} ),
            kind    => 'security_notice',
            subject => $subject,
            to      => $input->{to},
            headers => [ 'Content-Transfer-Encoding' => '8bit' ],
        }
    );
}

# ADR 0078: a notification mail, which a member may stop. It carries the
# one-click unsubscribe of RFC 8058 (List-Unsubscribe with an https or http
# URL, and List-Unsubscribe-Post), which identity mail never does: that is
# transactional.
#
# Its words are the member's language, so the subject is MIME-encoded and
# the body sent as UTF-8 octets.
sub send_notification_mail ( $self, $input ) {
    require Encode;
    return $self->_send_identity_mail(
        {
            body => Encode::encode(
                'UTF-8',
                (
                    length( $input->{reply_body} // q{} )
                    ? "$input->{reply_body}\n\n"
                    : q{}
                  )
                  . $input->{body}
            ),
            kind    => 'notification',
            subject => Encode::encode( 'MIME-Header', $input->{subject} ),
            to      => $input->{to},
            headers => [
                'Content-Transfer-Encoding' => '8bit',
                'List-Unsubscribe'          => "<$input->{unsubscribe_url}>",
                'List-Unsubscribe-Post'     => 'List-Unsubscribe=One-Click',
                (
                    defined $input->{reply_message_id}
                      && length( $input->{reply_to} // q{} )
                    ? (
                        'Message-ID' => $input->{reply_message_id},
                        'Reply-To'   => $input->{reply_to}
                      )
                    : ()
                ),
            ],
        }
    );
}

# ADR 0078: the daily or weekly digest, in the member's language, as a
# plain-text and an HTML part of one multipart/alternative message, each
# UTF-8 in quoted-printable (an HTML line may be longer than SMTP allows).
# It carries the one-click unsubscribe of notification mail. The boundary
# is named by the content, so it cannot occur in it.
sub send_digest_mail ( $self, $input ) {
    require Digest::SHA;
    require Encode;
    require MIME::QuotedPrint;
    my %part = map {
        $_ =>
          MIME::QuotedPrint::encode_qp( Encode::encode( 'UTF-8', $input->{$_} ),
            "\r\n" )
    } qw(text html);
    my $boundary =
      'gpforum-digest-' . Digest::SHA::sha1_hex( $part{text} . $part{html} );
    my $body = join "\r\n",
      "--$boundary",
      'Content-Type: text/plain; charset=UTF-8',
      'Content-Transfer-Encoding: quoted-printable',
      q{}, $part{text},
      "--$boundary",
      'Content-Type: text/html; charset=UTF-8',
      'Content-Transfer-Encoding: quoted-printable',
      q{},             $part{html},
      "--$boundary--", q{};

    return $self->_send_identity_mail(
        {
            body         => $body,
            content_type => qq{multipart/alternative; boundary="$boundary"},
            kind         => 'digest',
            subject      => Encode::encode( 'MIME-Header', $input->{subject} ),
            to           => $input->{to},
            headers      => [
                'MIME-Version'          => '1.0',
                'List-Unsubscribe'      => "<$input->{unsubscribe_url}>",
                'List-Unsubscribe-Post' => 'List-Unsubscribe=One-Click',
                $self->_message_id( 'digest', $input->{message_key} ),
            ],
        }
    );
}

# A Message-ID named by what the mail is (the digest's event id) rather
# than by when it went out, so a mail sent again is the same message to a
# mailbox that folds duplicates. Nothing without a key.
sub _message_id ( $self, $kind, $key ) {
    return () if !length( $key // q{} ) || $key =~ /[^[:alnum:]-]/msx;
    my ($domain) = $self->from_address =~ /@ ([[:alnum:].-]+)/msx;

    return (
        'Message-ID' => sprintf '<gpforum-%s.%s@%s>',
        $kind, $key, $domain // 'localhost'
    );
}

# A plain-text message through the transport, or the content type the
# caller names; a delivery is logged when there is a logger to log it.
sub _send_identity_mail ( $self, $input ) {
    require Email::Simple;
    my $email = Email::Simple->create(
        body   => $input->{body},
        header => [
            'Content-Type' => $input->{content_type}
              // 'text/plain; charset=UTF-8',
            From    => $self->from_address,
            Subject => $input->{subject},
            To      => $input->{to},
            @{ $input->{headers} || [] },
        ],
    );
    if ( $self->config && length( $self->config->dkim_key_file ) ) {
        require GPForum::Service::Identity::Dkim;
        $email =
          GPForum::Service::Identity::Dkim->new( config => $self->config )
          ->sign($email);
    }
    $self->transport->send(
        $email,
        {
            from => $self->from_address,
            to   => [ $input->{to} ],
        }
    );
    my $logger = $self->logger;
    if ($logger) {
        $logger->info("identity mail delivered: $input->{kind}");
    }

    return { ok => 1 };
}

# A mail whose link carries a token, in the language its input names
# (English without one): the subject and the words around the link are the
# locale catalogue's auth.<kind>_mail_subject and auth.<kind>_mail_body.
sub _send_link_mail ( $self, $kind, $path, $input ) {
    require Encode;
    my $locale = $input->{locale} || 'en';
    my $base   = $self->public_base_url;
    $base =~ s{ / \z}{}msx;
    my $subject =
      $self->i18n->translate( $locale, "auth.${kind}_mail_subject" );
    if ( $subject =~ /[^[:ascii:]]/msx ) {
        $subject = Encode::encode( 'MIME-Header', $subject );
        $subject =~ s{ \r?\n [ \t]+ }{ }gmsx;
    }

    return $self->_send_identity_mail(
        {
            body => Encode::encode(
                'UTF-8',
                $self->i18n->translate(
                    $locale, "auth.${kind}_mail_body",
                    { url => $base . $path }
                )
            ),
            headers => [ 'Content-Transfer-Encoding' => '8bit' ],
            kind    => $kind,
            subject => $subject,
            to      => $input->{to},
        }
    );
}

# mail_transport names smtp, sendmail or log; anything else is
# Email::Sender's test transport, which keeps what it is sent.
sub _build_transport ($self) {
    my $name = $self->_config_value( 'mail_transport', 'test' );
    if ( $name eq 'sendmail' ) {
        require Email::Sender::Transport::Sendmail;
        return Email::Sender::Transport::Sendmail->new;
    }
    if ( $name eq 'log' ) {
        return GPForum::Service::Identity::LogTransport->new(
            logger => $self->_logger_at_info );
    }
    if ( $name ne 'smtp' ) {
        require Email::Sender::Transport::Test;
        return Email::Sender::Transport::Test->new;
    }

    my $port = int $self->_config_value( 'smtp_port', $DEFAULT_PORT );
    my $args = {
        host => $self->_config_value( 'smtp_host', 'localhost' ),
        port => $port,
    };
    my $tls = $self->_config_value( 'smtp_tls',
        $port == $IMPLICIT_TLS_PORT ? 'implicit' : 'starttls' );
    if ( exists $SMTP_SECURITY{$tls} ) {
        $args->{ssl} = $SMTP_SECURITY{$tls};
    }
    my $user = $self->_config_value( 'smtp_username', q{} );
    if ($user) {
        $args->{sasl_username} = $user;
        $args->{sasl_password} = $self->_config_value( 'smtp_password', q{} );
    }
    if ( defined $self->smtp_timeout ) {
        $args->{timeout} = $self->smtp_timeout;
    }

    require Email::Sender::Transport::SMTP;
    return Email::Sender::Transport::SMTP->new($args);
}

# The logger the log transport writes a message to, or undef for standard
# error. The transport writes at info, so a log set to warn or above would
# keep the link a developer is waiting for out of sight: then it goes to
# standard error, which the supervisor keeps, whatever the level.
sub _logger_at_info ($self) {
    my $logger = $self->logger;
    return $logger if !$logger || !$logger->can('is_level');

    return $logger->is_level('info') ? $logger : undef;
}

# Without a configuration, or with the setting left empty, the default
# applies.
sub _config_value ( $self, $name, $default ) {
    my $config = $self->config;
    if ( !$config ) {
        return $default;
    }

    my $value = $config->$name;
    return defined $value && length $value ? $value : $default;
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::Mailer - Identity transactional mail delivery.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $mailer = GPForum::Service::Identity::Mailer->from_config($config);
    $mailer->send_password_reset(
        {
            to    => $email,
            token => $raw_token,
        }
    );

=head1 DESCRIPTION

Sends password-reset, email-change, and registration-verification messages
through L<Email::Sender> transports. The transport is injectable so tests
can use L<Email::Sender::Transport::Test>. Configuration comes from
L<GPForum::Config>: C<sendmail>, C<smtp>, C<log> or C<test>. Raw tokens are
placed only in the message body and are never written to logs, with one
exception: the C<log> transport (L<GPForum::Service::Identity::LogTransport>),
development's default, writes the whole message, link included, to the
logger -- or to standard error when there is none, or when its level would
hide an info line -- and staging and production refuse it. Delivery
uses the transport C<send> method so C<Email::Sender::Simple> is not required
at runtime.

=head1 SUBROUTINES/METHODS

=head2 from_config

Builds a mailer from a L<GPForum::Config> object.

=head2 send_password_reset

Takes C<to>, the raw C<token> and the member's C<locale> (English without
one) and sends the reset link in that language.

=head2 send_email_change

Sends an email-change confirmation link, as L</send_password_reset> does.

=head2 send_email_verification

Sends a registration verification link, as L</send_password_reset> does.

=head2 send_test_message

Sends the admin console's test message, which carries no link.

=head2 send_security_notice

Takes C<to>, C<subject> and C<body>, in the member's language, and sends a
notice about the account's security (ADR 0142), with no unsubscribe.

=head2 send_notification_mail

Takes C<to>, C<subject>, C<body> (text, encoded here) and
C<unsubscribe_url>, and sends a notification mail with the RFC 8058
C<List-Unsubscribe> and C<List-Unsubscribe-Post> headers. Logged as
C<identity mail delivered: notification>. The headers are only one-click
to a receiver that sees them under a DKIM signature, which GPForum adds when DKIM is configured.

=head2 send_digest_mail

Takes C<to>, C<subject>, C<text>, C<html> (both text, encoded here) and
C<unsubscribe_url>, and sends the email digest (ADR 0078) as one
C<multipart/alternative> message, its plain-text and HTML parts in UTF-8
quoted-printable, with the RFC 8058 C<List-Unsubscribe> and
C<List-Unsubscribe-Post> headers. An optional C<message_key> (the
digest's event id) names its C<Message-ID>, the same each time it is
sent. Logged as C<identity mail delivered: digest>.

=head1 DIAGNOSTICS

Transport send exceptions propagate to the caller. Delivery success is
logged as C<identity mail delivered: $kind> without the token.

=head1 CONFIGURATION AND ENVIRONMENT

Reads C<mail_transport>, C<mail_from>, C<public_base_url>, and optional
SMTP fields from the injected L<GPForum::Config>: C<smtp_tls> is
C<starttls> (STARTTLS), C<implicit> (TLS from the first byte, SMTPS) or
C<off>, and without a configuration follows the port, implicit on 465. C<smtp_timeout> bounds each
SMTP step for callers that cannot wait Email::Sender's 120 seconds.

=head1 DEPENDENCIES

Uses L<Email::Simple>, L<Email::Sender> transports and
L<GPForum::Service::Identity::LogTransport>. The Email::Sender transports are
loaded when they are built.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Does not queue mail through the outbox. The identity worker handler
sends after the token transaction commits an outbox row.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
