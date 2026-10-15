# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::NotificationPreferenceCalls;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# ADR 0078: one stand-in for the collaborators of notification preferences
# -- the function layer, the event recorder, the preference store and the
# mailer. Every call is recorded; each answers what `answers` holds under
# its name (a function under its function's name; a code reference is
# called with the arguments), or a plain ok.
has answers         => sub { return {}; };
has calls           => sub { return []; };
has public_base_url => 'https://forum.example.test/';

sub row ( $self, $name, $parameters ) {
    return $self->_called( $name => $parameters );
}

sub rows ( $self, $name, $parameters ) {
    return $self->_called( $name => $parameters ) // [];
}

sub record_event ( $self, %event ) {
    return $self->_called( record_event => \%event );
}

sub audit_call ( $self, %audit ) {
    return { audit => \%audit, explicit => 0 };
}

sub delivery_plan ( $self, @arguments ) {
    return $self->_called( delivery_plan => @arguments );
}

sub send_notification_mail ( $self, @arguments ) {
    return $self->_called( send_notification_mail => @arguments );
}

# The arguments of each call to $name, in order.
sub calls_to ( $self, $name ) {
    return [ map { $_->[1] } grep { $_->[0] eq $name } @{ $self->calls } ];
}

sub _called ( $self, $name, @arguments ) {
    push @{ $self->calls }, [ $name, @arguments ];
    my $answer = $self->answers->{$name};
    return $answer->(@arguments) if ref $answer eq 'CODE';
    return $answer               if exists $self->answers->{$name};

    return { ok => 1 };
}

1;

__END__

=head1 NAME

GPForum::Test::NotificationPreferenceCalls - A recording stand-in for notification preferences' collaborators.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $calls = GPForum::Test::NotificationPreferenceCalls->new(
        answers => { notification_delivery_plan => { email => 1 } } );
    my $store = GPForum::Service::Notification::PreferenceStore->new(
        schema => $schema, functions => $calls );

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::SqlFunction> (C<row>, C<rows>),
L<GPForum::Infrastructure::EventRecorder> (C<record_event>, C<audit_call>),
the preference store's C<delivery_plan> and the mailer's
C<send_notification_mail> and C<public_base_url>.

=head1 SUBROUTINES/METHODS

=head2 row

Records a function call and answers as C<answers> says under its name.

=head2 rows

As L</row>, answering an empty list by default.

=head2 record_event

Records the event's fields.

=head2 audit_call

Answers the audit call prepared from the fields given.

=head2 delivery_plan

Records the plan asked for.

=head2 send_notification_mail

Records the mail sent.

=head2 calls_to

The first argument of every call to a name, in order.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
