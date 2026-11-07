# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Moderation::Media;

use Mojo::Base 'GPForum::Controller::Moderation::Base', -async_await;
use v5.40;
use GPForum::Infrastructure::FileAsset;

use Mojo::Asset::File;
use Const::Fast;
use GPForum::Web::MediaResponse;

our $VERSION = '0.001';
const my $PAGE_LIMIT => 50;
const my %HTTP_CODE => (
    ok        => 200,
    unchanged => 200,
    not_found => 404,
    invalid   => 400,
    refused   => 409,
    failed    => 503,
);
const my %DECISION_ERROR => (
    refused   => 'media.decision_refused',
    invalid   => 'media.decision_invalid',
    not_found => 'media.decision_not_found',
);

# Queue, preview and decisions all require global moderation. Preview is a
# separate private route, never a way around the public download's gate.
async sub queue ($self) {
    my $actor = (
        await $self->await_p(
            $self->authorized_user_id( 'thread', 'moderate' ) ) )
      or return;
    return await $self->_queue_page( $actor, {} );
}

async sub _queue_page ( $self, $actor, $response ) {
    $self->res->headers->cache_control('private, no-store');
    my $rows;
    try {
        $rows = (
            await $self->call_p(
                $self->gp_attachment_content_review, 'queue',
                $self->param('after_at'),            $self->param('after_id')
            )
        );
    }
    catch ($error) {
        $self->app->log->error("media review queue: $error");
        return $self->system_failure;
    };
    my $more = @{$rows} > $PAGE_LIMIT ? pop @{$rows} : undef;
    my $tail = @{$rows}               ? $rows->[-1]  : undef;
    my $next =
      $more && $tail
      ? $self->url_for('moderation_media')->query(
        after_at => $tail->{created_at},
        after_id => $tail->{attachment_id}
      )
      : undef;
    return $self->render(
        json => { uploads => $rows, next => $next ? "$next" : undef } )
      if $self->wants_json;
    for my $file ( @{$rows} ) {
        $file->{own_upload} = ( $file->{owner_user_id} // q{} ) eq $actor;
    }
    return $self->render(
        template       => 'moderation/media',
        uploads        => $rows,
        next           => $next,
        status         => $response->{status} // $HTTP_CODE{ok},
        decision_error => $response->{error_key}
        ? $self->i18n( $response->{error_key} )
        : undef,
        decision_attachment => $response->{attachment_id} // q{},
        decision_reason     => $response->{reason}        // q{},
    );
}

async sub preview ($self) {
    return
      if !(
        await $self->await_p(
            $self->authorized_user_id( 'thread', 'moderate' ) ) );
    $self->res->headers->cache_control('private, no-store');
    my ( $row, $asset );
    try {
        $row = (
            await $self->call_p(
                $self->gp_attachment_content_review, 'find',
                $self->param('attachment_id')
            )
        );
        return $self->not_found('attachment not found')
          if !$row
          || $row->{scan_status} ne 'clean'
          || $row->{status} ne 'pending';
        my $storage = $self->gp_attachment_storage;
        $asset =
          $storage->can('asset_for')
          ? ( await $self->call_p( $storage, 'asset_for', $row->{object_key} ) )
          : await GPForum::Infrastructure::FileAsset->from_path_p(
            await $self->call_p( $storage, 'path_for', $row->{object_key} ) );
    }
    catch ($error) {
        $self->app->log->error("media review preview: $error");
        return $self->system_failure;
    };
    $self->res->headers->content_type( $row->{media_type} );

    # Only display allowed raster/audio/video types inline. Documents download.
    $self->res->headers->content_disposition(
        $row->{media_type} =~ m{\A (?:image|audio|video)/}msx
        ? 'inline'
        : 'attachment'
    );
    return GPForum::Web::MediaResponse->new->render( $self, $asset,
        $row->{checksum} );
}

async sub decide ($self) {
    my $actor = (
        await $self->await_p(
            $self->authorized_write_user_id( 'thread', 'moderate' )
        )
    ) or return;
    my $answer;
    try {
        $answer = (
            await $self->call_p(
                $self->gp_attachment_content_review,
                'decide',
                {
                    actor_user_id => $actor,
                    attachment_id => $self->param('attachment_id'),
                    decision      => $self->param('decision'),
                    reason        => $self->param('reason'),
                }
            )
        );
    }
    catch ($error) {
        $self->app->log->error("media review decision: $error");
        return $self->system_failure;
    };
    my $code = $HTTP_CODE{ $answer->{status} } // $HTTP_CODE{failed};
    return $self->render( json => $answer, status => $code )
      if $self->wants_json;
    return $self->redirect_to('moderation_media')
      if $code == $HTTP_CODE{ok};
    return await $self->_queue_page(
        $actor,
        {
            status    => $code,
            error_key => $DECISION_ERROR{ $answer->{status} // q{} }
              // 'media.decision_failed',
            attachment_id => $self->param('attachment_id'),
            reason        => $self->param('reason'),
        }
    );
}

1;

__END__

=head1 NAME

GPForum::Controller::Moderation::Media - Private media provenance and review.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/moderation/media')->to('Moderation::Media#queue');

=head1 DESCRIPTION

Lists held uploads with keyset pagination, permits clean-file staff previews,
and records CSRF-protected decisions under the global moderation permission.

=head1 SUBROUTINES/METHODS

=head2 queue

Lists pending uploads for a globally authorized moderator.

=head2 preview

Streams a clean pending upload privately after the staff permission check.

=head2 decide

Checks CSRF and global moderation permission before recording a decision.

=head1 DIAGNOSTICS

Uses 400, 401, 403, 404, 409 and 503 for validation, access and service failures.

=head1 CONFIGURATION AND ENVIRONMENT

The composition layer supplies the schema, storage and source policy.

=head1 DEPENDENCIES

L<Mojo::Base> and the composed Good Phorum services.

=head1 INCOMPATIBILITIES

Requires a global moderator; it supplies no automatic semantic content classifier.

=head1 BUGS AND LIMITATIONS

Requires a global moderator; it supplies no automatic semantic content classifier.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
