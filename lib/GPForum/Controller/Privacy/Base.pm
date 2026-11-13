# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Privacy::Base;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Base', -async_await;
use v5.40;

use GPForum::Web::Access;
use GPForum::Web::Guard;
use GPForum::Web::PrivacyAccess;
use GPForum::Web::SecurityEvent;
use GPForum::Web::UrlId;

our $VERSION = '0.001';

const my $HTTP_OK => 200;

# The workflow's own names for the rows the review placeholders address, so a
# malformed id answers word for word as one naming no row.
const my %PATH_ID_NOUN => (
    hold_id    => 'retention hold',
    job_id     => 'erasure job',
    request_id => 'deletion request',
);

sub privacy_access {
    return GPForum::Web::PrivacyAccess->new;
}

sub limit_param ($self) {
    return $self->privacy_access->page_limit( $self->param('limit') );
}

sub member_user_id ($self) {
    my $user_id = GPForum::Web::Access->new->user_id($self);
    if ( !$user_id ) {
        GPForum::Web::Guard->new->unauthorized($self);
        return;
    }

    # Every privacy route passes here before a query. An export, deletion
    # request or erasure job id that is not a uuid made PostgreSQL refuse the
    # lookup: the download answered 500 and the staff reviews 503.
    if ( my $malformed = GPForum::Web::UrlId->malformed_path_id($self) ) {
        $self->not_found(
            GPForum::Web::UrlId->not_found_error( $malformed, \%PATH_ID_NOUN )
        );
        return;
    }

    return $user_id;
}

async sub write_user_id ($self) {
    if ( GPForum::Web::Access->new->csrf_invalid($self) ) {
        $self->_csrf_failure;
        return;
    }

    # scalar: a refusal returns an empty list, which shifted the action into
    # the user id and died on the signature after the 401 was rendered -- the
    # client lost the connection instead of reading the 401.
    return (
        await $self->await_p(
            $self->_rate_limited_user_id(
                scalar $self->member_user_id,
                $self->privacy_access->request_action
            )
        )
    );
}

async sub authorized_write_user_id ($self) {
    if ( GPForum::Web::Access->new->csrf_invalid($self) ) {
        $self->_csrf_failure;
        return;
    }

    # scalar, as in write_user_id: a 401, 403 or 404 already rendered.
    my $user_id = scalar(
        await $self->await_p(
            $self->authorized_user_id( $self->privacy_access->manage_action )
        )
    );
    if ( !$user_id ) {
        return;
    }

    # Staff take no part while suspended, as in the admin and moderation
    # consoles. Only these staff writes: a suspended member keeps the right
    # to ask for their own export or erasure (write_user_id).
    return
      if !(
        await $self->await_p(
            $self->participating(
                $user_id, $self->privacy_access->review_action
            )
        )
      );

    return (
        await $self->await_p(
            $self->_rate_limited_user_id(
                $user_id, $self->privacy_access->review_action,
            )
        )
    );
}

async sub authorized_user_id ( $self, $action ) {
    my $user_id = $self->member_user_id;
    if ( !$user_id ) {
        return;
    }
    my $permission = {
        %{ $self->privacy_access->permission_target($action) },
        %{ $self->global_permission_scope },
    };
    if (
        !(
            await $self->call_p(
                $self->gp_permission_gate, 'allowed',
                { user_id => $user_id },   $permission
            )
        )
      )
    {
        my $guard = GPForum::Web::Guard->new;
        $guard->log_denial( $self, $user_id, $permission );
        $guard->forbidden($self);
        return;
    }

    return $user_id;
}

sub export_write_response ( $self, $result ) {
    my $failure = $self->write_failure($result);
    if ($failure) {
        return $failure;
    }

    return $self->privacy_action_response(
        $self->gp_privacy_view_model->export_request_response(
            'export_requested', $result->{stored},
        ),
    );
}

sub deletion_write_response ( $self, $result ) {
    my $failure = $self->write_failure($result);
    if ($failure) {
        return $failure;
    }

    return $self->privacy_action_response(
        $self->gp_privacy_view_model->deletion_request_response(
            'deletion_requested', $result->{stored},
        ),
    );
}

sub deletion_review_write_response ( $self, $result, $ok_status ) {
    my $failure = $self->write_failure($result);
    if ($failure) {
        return $failure;
    }

    return $self->privacy_action_response(
        $self->gp_privacy_view_model->deletion_review_response(
            $ok_status, $result->{stored},
        ),
        'privacy_review',
    );
}

sub erasure_write_response ( $self, $result ) {
    my $failure = $self->write_failure($result);
    if ($failure) {
        return $failure;
    }

    return $self->privacy_action_response(
        $self->gp_privacy_view_model->erasure_job_response(
            'erasure_completed', $result->{stored},
        ),
        'privacy_review',
    );
}

# The response a failed write answers with, or undef when it did not fail.
sub write_failure ( $self, $result ) {
    my $access = $self->privacy_access;
    my $guard  = GPForum::Web::Guard->new;
    if ( $access->is_failed($result) ) {
        return $guard->service_unavailable($self);
    }

    my $status = $access->failure_status($result) || q{};
    if ( $status eq 'not_found' ) {
        return $self->not_found( $result->{error} );
    }
    if ( $status eq 'invalid' ) {
        return $guard->bad_request( $self,
            $access->invalid_request( $result->{errors} ) );
    }
    if ( $status eq 'conflict' ) {
        return $guard->conflict( $self,
            $access->conflict_payload( $result->{error} ) );
    }

    return undef;
}

sub privacy_action_response ( $self, $payload, $redirect_route = undef ) {
    if ( GPForum::Web::Access->new->wants_json($self) ) {
        return $self->render(
            json   => $payload,
            status => $HTTP_OK,
        );
    }

    my $access = $self->privacy_access;
    $self->set_success_flash( $access->write_flash_key( $payload->{status} ) );

    return $self->redirect_to( $redirect_route || $access->default_redirect );
}

async sub _rate_limited_user_id ( $self, $user_id, $action ) {
    if ( !$user_id ) {
        return;
    }
    my $decision = (
        await $self->call_p(
            $self->gp_rate_limiter,
            'check',
            $self->privacy_access->write_rate_input(
                { action => $action, actor_id => $user_id }
            )
        )
    );
    if ( !$decision->{ok} ) {
        GPForum::Web::SecurityEvent->new->rate_limited($self);
        return;
    }

    return $user_id;
}

sub _csrf_failure ($self) {
    return GPForum::Web::Guard->new->csrf_failure($self);
}

# The manifest decoded: get_column returns the jsonb column's text, and the
# download sent the whole bundle as one JSON string.
sub render_export_download ( $self, $row ) {
    my $request_id = $self->_row_value( $row, 'export_request_id' );
    $self->res->headers->content_type('application/json; charset=UTF-8');
    $self->res->headers->content_disposition(
        $self->privacy_access->export_download_disposition($request_id) );

    my $manifest =
      ref $row ne 'HASH' && $row && $row->can('get_inflated_column')
      ? $row->get_inflated_column('manifest')
      : $self->_row_value( $row, 'manifest' );

    return $self->render(
        json   => $manifest || {},
        status => $HTTP_OK,
    );
}

sub _row_value ( $, $row, $name ) {
    if ( ref $row eq 'HASH' ) {
        return $row->{$name};
    }
    if ( $row && $row->can('get_column') ) {
        return $row->get_column($name);
    }

    return;
}

1;

__END__

=head1 NAME

GPForum::Controller::Privacy::Base - Shared privacy HTTP helpers.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    use Mojo::Base 'GPForum::Controller::Privacy::Base';
use v5.40;

=head1 DESCRIPTION

Owns CSRF, authorization, rate-limit checks, telemetry, and Guard errors
used by member privacy and staff review controllers. Page limits, write
rate-limit hashes, permission-target hashes, conflict payloads, and
failure-status mapping live on L<GPForum::Web::PrivacyAccess>.

=head1 SUBROUTINES/METHODS

=head2 member_user_id

Returns the signed-in actor, or answers 401. A route id that is not a uuid
answers 404 here, before any query (L<GPForum::Web::UrlId>).

=head2 write_user_id

Rejects invalid CSRF tokens, anonymous member writes, and rate-limited
actors.

=head2 authorized_write_user_id

Rejects invalid CSRF tokens, unauthorized staff writes, suspended staff (403,
recorded as a C<suspended_user_block>, as in the admin and moderation
consoles), and rate-limited actors. A suspended member can still use
L</write_user_id> for their own export and erasure requests.

=head2 authorized_user_id

Requires an authenticated actor with the requested privacy permission at
global scope. Export, deletion, and erasure rights cover a whole account and
have no category or space dimension, so privacy checks pass
L<GPForum::Controller::Base/global_permission_scope> on purpose and
L<GPForum::Service::Admin::PermissionGate> accepts global role bindings only.

=head2 write_failure

Maps workflow statuses to HTTP error responses.

=head1 DIAGNOSTICS

HTTP errors are rendered as JSON or HTML depending on the request.

=head1 CONFIGURATION AND ENVIRONMENT

Uses permission and privacy helpers registered during application startup.

=head1 DEPENDENCIES

Uses L<GPForum::Controller::Base>, L<GPForum::Web::Access>,
L<GPForum::Web::Guard>, L<GPForum::Web::PrivacyAccess>,
L<GPForum::Web::Responder>, L<GPForum::Web::SecurityEvent>, and
L<GPForum::Web::UrlId>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Helpers are HTTP-oriented and must not talk to DBIx::Class resultsets.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
