# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::MessageMailer;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# ADR 0139: the mailer and the unsubscribe tokens a notification mail is
# sent with, keeping the last message in `sent`.
has sent => sub { return {}; };

sub public_base_url ($self) { return 'https://forum.test'; }

sub send_notification_mail ( $self, $message ) {
    %{ $self->sent } = %{$message};

    return 1;
}

sub issue ( $self, @ ) { return 'token'; }

1;
