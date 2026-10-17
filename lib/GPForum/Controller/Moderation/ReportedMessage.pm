# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Moderation::ReportedMessage;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Moderation::Base', -signatures;
use v5.40;

use GPForum::Web::Guard;
use GPForum::Web::SecurityEvent;

our $VERSION = '0.001';

const my $HTTP_OK        => 200;
const my $HTTP_FORBIDDEN => 403;
const my $HTTP_GONE      => 410;

# ADR 0139: staff who read the report queue read the message a report
# names, and nothing else of the conversation. The request is a form, so the
# reading needs a CSRF token and stays under the moderation write limit, and
# it is audited in the same call that reads the message. A suspended staff
# member reads none.
sub show ($self) {
    my $user_id = $self->authorized_write_user_id(
        $self->moderation_access->view_queue_action );
    return if !$user_id;

    my $decision = $self->gp_suspension_store->can_participate($user_id);
    if ( !$decision->{ok} ) {
        GPForum::Web::SecurityEvent->new->record_event(
            $self,
            'suspended_user_block',
            {
                action => 'direct_message.report_read',
                status => $HTTP_FORBIDDEN,
            }
        );
        return GPForum::Web::Guard->new->forbidden( $self,
            { error => 'user is suspended' } );
    }

    my $read =
      $self->gp_message_store->read_reported( $self->stash('report_id'),
        $user_id );
    return $self->_not_found('reported message not found')
      if $read->{status} ne 'ok' && $read->{status} ne 'gone';
    $self->res->headers->cache_control('private, no-store');

    return $self->render_payload(
        {
            payload => {
                report_id => $self->stash('report_id'),
                gone      => $read->{status} eq 'gone' ? 1 : 0,
                message   => $read->{message},
            },
            status   => $read->{status} eq 'ok' ? $HTTP_OK : $HTTP_GONE,
            template => 'moderation/reported_message',
        }
    );
}

1;

__END__

=head1 NAME

GPForum::Controller::Moderation::ReportedMessage - Staff read a reported direct message.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->post('/moderation/reports/:report_id/message')
      ->to('Moderation::ReportedMessage#show');

=head1 DESCRIPTION

ADR 0139: the only way staff read a member's direct message. A staff member
holding the report queue's C<report.view_queue> binding posts the form
beside a report about a message; the message (its author, time and text)
is read and the reading audited as C<direct_message.report_read> in one
call. Nothing else of the conversation is shown, and a report about
anything else reads nothing.

=head1 SUBROUTINES/METHODS

=head2 show

Answers the reported message's page (or JSON), never cached.

=head1 DIAGNOSTICS

403 for a bad CSRF token, a member without the binding or a suspended
staff member; 404 for a report that is not about a message; 410 when the
message was erased.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Community::MessageStore>, through C<gp_message_store>.

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
