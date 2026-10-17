# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Admin::SecondFactor;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Admin::Base', -signatures;
use v5.40;

our $VERSION = '0.001';

const my $HTTP_OK          => 200;
const my $HTTP_BAD_REQUEST => 400;
const my $HTTP_CONFLICT    => 409;
const my $PAGE             => 'admin_second_factor';

# ADR 0142: what each answer says, and with which status.
const my %STATUS => (
    not_found  => $HTTP_CONFLICT,
    self       => $HTTP_CONFLICT,
    unenrolled => $HTTP_CONFLICT,
);
const my %FLASH => (
    policy_set => 'admin.second_factor_policy_set',
    reset      => 'admin.second_factor_reset_done',
    unchanged  => 'admin.second_factor_unchanged',
    not_found  => 'admin.second_factor_reset_none',
    self       => 'admin.second_factor_reset_self',
    unenrolled => 'admin.second_factor_policy_unenrolled',
);

# Whether staff must use two-step sign-in, and the staff, those without it
# first: never anyone's secret.
sub show ($self) {
    my $user_id = $self->authorized_user_id( $self->admin_access->view_action );
    return if !$user_id;

    my ( $policy, $staff );
    try {
        my $two_step = $self->gp_second_factor;
        $policy = $two_step->policy;
        $staff  = $two_step->staff;
    }
    catch ($error) {
        $self->app->log->error("admin second factor failed: $error");
        return $self->system_failure;
    };
    my %page = (
        staff_required      => $policy->{staff_required},
        updated_at          => $policy->{updated_at},
        updated_by_username => $policy->{updated_by_username},
        staff               => [
            map {
                {
                    user_id      => $_->{user_id},
                    username     => $_->{username},
                    display_name => $_->{display_name},
                    enabled      => $_->{enabled} ? 1 : 0,
                    confirmed_at => $_->{confirmed_at},
                }
            } @{$staff}
        ],
    );
    $self->res->headers->cache_control('private, no-store');
    return $self->render( json => \%page, status => $HTTP_OK )
      if $self->_wants_json;

    return $self->render(
        template => 'admin/second_factor',
        status   => $HTTP_OK,
        %page
    );
}

sub set_policy ($self) {
    my $user_id = $self->authorized_write_user_id;
    return if !$user_id;

    my $required = $self->param('staff_required') ? 1 : 0;

    return $self->_answer(
        'policy_set',
        $PAGE,
        {},
        $self->_stored(
            sub {
                return $self->gp_second_factor->set_policy( $required,
                    $user_id );
            }
        )
    );
}

# A member who lost their app and their recovery codes: an administrator
# turns their two-step sign-in off, and the member is mailed.
sub reset_member ($self) {
    my $user_id = $self->authorized_write_user_id;
    return if !$user_id;

    my $member = $self->param('user_id');

    return $self->_answer(
        'reset',
        'admin_user_roles',
        { user_id => $member },
        $self->_stored(
            sub {
                return $self->gp_second_factor->reset_member( $member,
                    $user_id );
            }
        )
    );
}

# The service's answer, or undef when it failed (logged).
sub _stored ( $self, $call ) {
    my $result;
    try {
        $result = $call->();
    }
    catch ($error) {
        $self->app->log->error("admin second factor write failed: $error");
        return undef;
    };

    return $result;
}

sub _answer ( $self, $done, $page, $captures, $result ) {
    return $self->system_failure
      if !$result || ( $result->{status} // q{} ) eq 'failed';

    my $status = $result->{status} // 'invalid';
    my $code =
        $result->{ok}           ? $HTTP_OK
      : exists $STATUS{$status} ? $STATUS{$status}
      :                           $HTTP_BAD_REQUEST;
    return $self->render(
        json   => { ok => $result->{ok}, status => $status },
        status => $code
    ) if $self->_wants_json;

    if ( $result->{ok} ) {
        my $key = $status eq 'unchanged' ? $FLASH{unchanged} : $FLASH{$done};
        $self->flash( success => $self->i18n($key) );
    }
    else {
        $self->flash( error =>
              $self->i18n( $FLASH{$status} // 'admin.second_factor_failed' ) );
    }

    return $self->redirect_to( $page, %{$captures} );
}

1;

__END__

=head1 NAME

GPForum::Controller::Admin::SecondFactor - Two-step sign-in in the admin console.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/admin/security')->to('Admin::SecondFactor#show');

=head1 DESCRIPTION

ADR 0142. Administrators see which staff members have two-step sign-in on,
require it of staff (only once they have it on themselves), and turn it off
for a member who lost their authenticator app and their recovery codes.
Nobody is ever shown a secret. Every write takes the CSRF token, the admin
write permission and its rate limit, and is audited.

=head1 SUBROUTINES/METHODS

=head2 show

Renders the policy and the staff list; JSON gives C<staff_required>,
C<updated_at>, C<updated_by_username> and C<staff>.

=head2 set_policy

Takes C<staff_required> (1 or absent) and sets the policy.

=head2 reset_member

Turns the member's two-step sign-in off and returns to their admin page.

=head1 DIAGNOSTICS

A refusal flashes its reason; JSON clients get C<409> for C<self>,
C<not_found> and C<unenrolled>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Identity::SecondFactor>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The staff list shows at most 200 members.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
