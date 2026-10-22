# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Identity::Relations;

use Const::Fast;
use GPForum::Web::ErrorPayload;
use Mojo::Base 'GPForum::Controller::Identity::Base', -signatures;
use v5.40;

our $VERSION = '0.001';

const my $ACTION           => 'identity.member_relation';
const my $HTTP_OK          => 200;
const my $HTTP_BAD_REQUEST => 400;
const my $HTTP_FORBIDDEN   => 403;
const my $HTTP_NOT_FOUND   => 404;
const my $HTTP_CONFLICT    => 409;

# ADR 0130: what each refusal of the store answers.
const my %REFUSAL_STATUS => (
    forbidden => $HTTP_FORBIDDEN,
    invalid   => $HTTP_BAD_REQUEST,
    limit     => $HTTP_CONFLICT,
    not_found => $HTTP_NOT_FOUND,
    self      => $HTTP_BAD_REQUEST,
);
const my %FLASH_FOR => (
    block  => 'community.relation_blocked',
    ignore => 'community.relation_ignored',
    remove => 'community.relation_removed',
);

# The settings page of the list: who the member ignores or blocks, each
# with the way to take them off.
sub list ($self) {
    my $user_id = $self->current_user_id;
    return $self->settings_unauthorized if !$user_id;

    my $store     = $self->gp_relation_store;
    my $relations = $store->list_for_user($user_id);
    $self->res->headers->cache_control('private, no-store');
    if ( $self->_wants_json ) {
        return $self->render(
            json => {
                relations         => $relations,
                maximum_relations => $store->maximum_relations,
            },
            status => $HTTP_OK,
        );
    }

    return $self->render(
        template          => 'identity/relations',
        relations         => $relations,
        maximum_relations => $store->maximum_relations,
        status            => $HTTP_OK,
    );
}

sub ignore ($self) { return $self->_set('ignore'); }

sub block ($self) { return $self->_set('block'); }

sub remove ($self) {
    my $user_id = $self->_writer or return;
    my $result  = $self->gp_relation_store->remove_relation(
        { owner_user_id => $user_id, username => $self->param('username') } );

    return $self->_answer( 'remove', $result );
}

sub _set ( $self, $kind ) {
    my $user_id = $self->_writer or return;
    my $result  = $self->gp_relation_store->set_relation(
        {
            owner_user_id => $user_id,
            username      => $self->param('username'),
            kind          => $kind,
        }
    );

    return $self->_answer( $kind, $result );
}

# CSRF, then a signed-in member, then the rate limit: undef once a refusal
# is rendered.
sub _writer ($self) {
    my $refused = $self->identity_post_guard($ACTION);
    return undef if $refused;

    my $user_id = $self->current_user_id;
    if ( !$user_id ) {
        $self->settings_unauthorized;
        return undef;
    }

    return $user_id;
}

sub _answer ( $self, $change, $result ) {
    my $username = $self->param('username') // q{};
    if ( !$result->{ok} ) {
        return $self->_refusal( $result, $username );
    }
    if ( $self->_wants_json ) {
        return $self->render( json => $result, status => $HTTP_OK );
    }

    $self->flash(
        success => $self->t( $FLASH_FOR{$change}, { username => $username } ) );
    my $return_to = $self->param('return_to');
    return $self->redirect_to(
        defined $return_to && length $return_to
        ? $self->safe_return_to($return_to)
        : $self->url_for( 'profile', username => $username )
    );
}

sub _refusal ( $self, $result, $username ) {
    my $status = $REFUSAL_STATUS{ $result->{status} // q{} }
      // $HTTP_BAD_REQUEST;
    if ( $self->_wants_json ) {
        return $self->render(
            json   => { ok => 0, status => $result->{status} },
            status => $status,
        );
    }
    if ( $status == $HTTP_NOT_FOUND ) {
        return $self->render(
            template => 'identity/profile_not_found',
            status   => $status,
        );
    }
    if ( $result->{status} eq 'limit' || $result->{status} eq 'self' ) {
        $self->flash(
            error => $self->t(
                "community.relation_$result->{status}",
                { limit => $self->gp_relation_store->maximum_relations }
            )
        );
        return $self->redirect_to( 'profile', username => $username );
    }

    return $self->identity_bad_request;
}

1;

__END__

=head1 NAME

GPForum::Controller::Identity::Relations - Ignore and block a member.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->post('/u/:username/ignore')
      ->to('Identity::Relations#ignore');

=head1 DESCRIPTION

ADR 0130. A signed-in member ignores, blocks or stops ignoring another from
that member's profile, and manages the list on C<GET /settings/ignored>.
Every write checks the CSRF token and the C<identity.member_relation> rate
limit; a plain form is answered with a flash and a redirect to the profile
(or a safe C<return_to>), a JSON request with the store's result.

=head1 SUBROUTINES/METHODS

=head2 list

The member's list, privately cached: the C<identity/relations> page or JSON.

=head2 ignore

Ignores the member named in the route.

=head2 block

Blocks the member named in the route.

=head2 remove

Takes the member named in the route off the list.

=head1 DIAGNOSTICS

A refused CSRF token answers 403, a signed-out writer the login redirect
or 401, an unknown member 404, a full list or the member themself a flash
on the profile (409 or 400 to JSON), anything else malformed 400.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Community::RelationStore>, through the
C<gp_relation_store> helper.

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
