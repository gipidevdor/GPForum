# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Identity::Unsubscribe;

use Const::Fast;
use GPForum::Web::Access;
use Mojo::Base 'GPForum::Controller::Identity::Base', -signatures;
use v5.40;

our $VERSION = '0.001';

const my $HTTP_OK      => 200;
const my $HTTP_MISSING => 404;

# RFC 8058: the body a mail client posts to the List-Unsubscribe URL.
const my $ONE_CLICK_FIELD => 'List-Unsubscribe';
const my $ONE_CLICK_VALUE => 'One-Click';

# ADR 0078. Opening the link changes nothing (a mail scanner follows links):
# it shows what the link stops, and a button.
sub form ($self) {
    my $claim = $self->gp_unsubscribe_tokens->verify( $self->param('token') );
    return $self->_invalid_link if !$claim;

    return $self->render(
        template  => 'identity/unsubscribe',
        scope     => $claim->{scope},
        scope_key => "notifications.unsubscribe.scope.$claim->{scope}",
        status    => $HTTP_OK,
        token     => $self->param('token'),
        ui        => { heading_id => 'unsubscribe-heading' },
    );
}

# The button, or the mail client's one-click POST. The signed token is the
# credential: the mail client posts without a session and so without a
# CSRF token, which the form, posted from a browser, carries and has
# checked. The form may widen the scope to all notification email.
sub unsubscribe ($self) {
    my $one_click =
      ( $self->param($ONE_CLICK_FIELD) // q{} ) eq $ONE_CLICK_VALUE;
    if ( !$one_click && GPForum::Web::Access->new->csrf_invalid($self) ) {
        return $self->_csrf_failure;
    }
    if ( !$self->_identity_allowed('identity.unsubscribe') ) {
        return $self->_rate_limited;
    }
    my $claim = $self->gp_unsubscribe_tokens->verify( $self->param('token') );
    return $self->_invalid_link if !$claim;

    my $scope =
      !$one_click && ( $self->param('scope') // q{} ) eq 'all'
      ? 'all'
      : $claim->{scope};
    my $result;
    try {
        $result = $self->gp_notification_preference_store->unsubscribe(
            {
                user_id => $claim->{user_id},
                scope   => $scope,
                via     => $one_click ? 'one_click' : 'link',
            }
        );
    }
    catch ($error) {
        $self->app->log->warn("unsubscribe failed: $error");
        return $self->identity_unavailable;
    };
    return $self->_invalid_link if !$result->{ok};
    if ($one_click) {
        return $self->render(
            text   => $self->t('notifications.unsubscribe.done_title'),
            status => $HTTP_OK
        );
    }

    return $self->render(
        template    => 'identity/unsubscribed',
        message_key => "notifications.unsubscribe.done_scope.$scope",
        status      => $HTTP_OK,
        ui          => { heading_id => 'unsubscribed-heading' },
    );
}

sub _invalid_link ($self) {
    return $self->render(
        template => 'identity/unsubscribe_invalid',
        status   => $HTTP_MISSING,
        ui       => { heading_id => 'unsubscribe-invalid-heading' },
    );
}

1;

__END__

=head1 NAME

GPForum::Controller::Identity::Unsubscribe - The one-click unsubscribe link of a notification mail.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GET  /unsubscribe/:token    # what the link stops, and a button
    POST /unsubscribe/:token    # the button, or RFC 8058's one-click POST

=head1 DESCRIPTION

ADR 0078. The link in every notification mail, and its
C<List-Unsubscribe> header. Opening it changes nothing: it shows which
email it stops (one kind of notification) with a button, and the choice of
stopping all notification email instead. The button posts with the page's
CSRF token; a mail client's one-click POST (body
C<List-Unsubscribe=One-Click>) needs none, since it has no session and the
signed token is the credential, and stops the kind the link names. Both are
rate limited by address and need no sign-in. A link that does not verify,
or names an account that is gone, answers 404 with nothing changed. The
change and how it was made are audited.

=head1 SUBROUTINES/METHODS

=head2 form

Renders F<identity/unsubscribe> for a valid token, or
F<identity/unsubscribe_invalid> with 404.

=head2 unsubscribe

Turns the email off through
L<GPForum::Service::Notification::PreferenceStore/unsubscribe>. Answers the
one-click POST with 200 and a line of text, the form with
F<identity/unsubscribed>; 403 for a form without a valid CSRF token, 429
past the rate limit, 404 for a link that does not verify and 503 when the
store fails.

=head1 DIAGNOSTICS

A store failure is logged at warn and answered 503.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the C<gp_unsubscribe_tokens> and C<gp_notification_preference_store>
helpers.

=head1 DEPENDENCIES

L<GPForum::Controller::Identity::Base>.

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
