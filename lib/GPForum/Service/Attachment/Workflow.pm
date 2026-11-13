# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::Workflow;

use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use Scalar::Util qw(blessed);

use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::WorkflowResult
  qw(log_error missing_command_id workflow_result);
our $VERSION = '0.001';

__PACKAGE__->requires(
    qw(command_idempotency delivery pipeline post_reader store));
has logger => undef;    # optional: failures go unlogged

# The store's call layer: blocking_copy makes the workflow's parts block
# only when the workflow has one.
has functions => sub ($self) {
    my $store = $self->store;
    return blessed $store
      && $store->can('functions') ? $store->functions : undef;
};

# Each command and the download are written once, as their promise methods
# (ADR 0177); the blocking methods are their twins, every collaborator
# blocking with them. The pipeline is handed the command's call layer.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(upload_for_post delete_for_post download download_metadata));
GPForum::Infrastructure::SqlFunction->blocking_parts(
    qw(command_idempotency delivery post_reader store));

# The upload under its command id: the command log's steps, the post's
# locks, the rows and, in PostgreSQL storage, the bytes in one transaction.
async sub upload_for_post_p ( $self, $input, $context = undef ) {
    my $invalid = missing_command_id($input);
    return $invalid if $invalid;

    # The scan reads the source alone: it runs before the command's
    # transaction takes a connection and the post's locks, in the process
    # on a blocking layer and in a child that cannot reach the database
    # otherwise.
    $input = {
        %{$input},
        prescanned =>
          await $self->pipeline->prescan_p( $input, $self->functions )
    };
    return $self->_settled(
        await $self->_commanded_p(
            _upload_job($input),
            $input, $context,
            sub ($functions) {
                return $self->_upload_once_p( $input, $functions, $context );
            }
        )
    );
}

sub _upload_job ($input) {
    return {
        actor_id     => $input->{actor_user_id},
        command_id   => $input->{command_id},
        command_type => 'attachment.upload',
        request      => {
            actor_user_id => $input->{actor_user_id},
            post_id       => $input->{post_id},
        },
    };
}

# The bytes are written before the rows, inside the command's transaction:
# a command that does not go through rolls the rows back, and its bytes
# stayed in storage, where the orphan purge, which walks rows, never looks.
sub _settled ( $self, $result ) {
    if ( $result->{ok} ) {
        $self->pipeline->forget_written;
    }
    else {
        $self->pipeline->discard_written;
    }

    return $result;
}

# A download's decision and its object, as the delivery answers them.
async sub download_p ( $self, $input, $context = undef ) {
    my ( $value, $failure );
    try {
        $value =
          await $self->delivery->download_p( _download_input($input),
            $context );
    }
    catch ($error) { $failure = $error; };
    return $self->_store_answer( 'attachment not found', $value, $failure );
}

# The download's decision, its object described as data.
async sub download_metadata_p ( $self, $input, $context = undef ) {
    return _metadata( await $self->download_p( $input, $context ) );
}

# A download's answer with its object as plain data: a PostgreSQL object by
# key, a file by path, anything else read whole.
sub _metadata ($result) {
    return $result if !$result->{ok};
    my $stored = $result->{stored};
    my $asset  = delete $stored->{object_asset};
    if ($asset) {
        if ( $asset->isa('GPForum::Service::Attachment::PostgresAsset') ) {
            $stored->{database_asset} = {
                object_key  => $asset->object_key,
                byte_size   => $asset->size,
                modified_at => $asset->mtime,
            };
        }
        elsif ( $asset->isa('Mojo::Asset::File') ) {
            $stored->{object_path} = $asset->path;
        }
        else {
            $stored->{content} = $asset->slurp;
        }
    }
    return $result;
}

async sub _upload_once_p ( $self, $input, $functions, $context ) {
    my $post =
      await $self->post_reader->find_visible_post_p( $input->{post_id},
        $input->{viewer}, $context );
    return undef if !$post;
    return { error => 'post author required', forbidden => 1 }
      if !_same_author( $post, $input->{actor_user_id} );

    return _linked_upload(
        await $self->pipeline->upload_and_link_p(
            _upload_request( $input, $post ),
            $context, $functions
        ),
        $post,
    );
}

sub _upload_request ( $input, $post ) {
    return {
        actor_user_id    => $input->{actor_user_id},
        target_id        => column_of( $post, 'post_id' ),
        target_type      => 'post',
        upload           => $input->{upload},
        source_kind      => $input->{source_kind},
        source_url       => $input->{source_url},
        rights_confirmed => $input->{rights_confirmed},
        (
            exists $input->{prescanned}
            ? ( prescanned => $input->{prescanned} )
            : ()
        ),
    };
}

# The deletion under its command id: the command log's steps, the post's
# locks and the store's writes in one transaction.
async sub delete_for_post_p ( $self, $input, $context = undef ) {
    my $invalid = missing_command_id($input);
    return $invalid if $invalid;

    return await $self->_commanded_p(
        _delete_job($input),
        $input, $context,
        sub ($functions) {
            return $self->_delete_once_p( $input, $functions, $context );
        }
    );
}

sub _delete_job ($input) {
    return {
        actor_id     => $input->{actor_user_id},
        command_id   => $input->{command_id},
        command_type => 'attachment.delete',
        request      => {
            actor_user_id => $input->{actor_user_id},
            attachment_id => $input->{attachment_id},
            post_id       => $input->{post_id},
        },
    };
}

# A write on a post (_upload_once_p, _delete_once_p) under the post's locks
# in the transaction $scope belongs to, or in one of the store's own.
async sub _post_store_write_p ( $self, $input, $scope, $context, $once_p ) {
    my ( $value, $failure );
    try {
        $value = await $self->store->with_post_write_p( $input, $once_p, $scope,
            $context );

        # The guard refuses before the write's own audience check runs: its
        # refusal must not reveal a post the viewer cannot read.
        if (
               $value
            && $value->{forbidden}
            && !await $self->post_reader->find_visible_post_p(
                $input->{post_id}, $input->{viewer}, $context
            )
          )
        {
            $value = undef;
        }
    }
    catch ($error) { $failure = $error; };
    return _public_write_result(
        $self->_store_answer( 'post not found', $value, $failure ) );
}

# The command's write ($once_p) under its id, on the command log's
# transaction.
async sub _commanded_p ( $self, $job, $input, $context, $once_p ) {
    my $run_p = async sub ( $scope = undef ) {
        return await $self->_post_store_write_p( $input, $scope, $context,
            $once_p );
    };
    my $result;
    try {
        $result =
          await $self->command_idempotency->result_of_p(
            { %{$job}, run_p => $run_p }, $context );
    }
    catch ($error) {
        log_error( $self->logger, "attachment command log failed: $error" );
        return _failed_result();
    };
    return $result;
}

sub _public_write_result ($result) {
    if ( !$result->{ok} ) {
        return $result;
    }

    return workflow_result(
        status => $result->{status},
        stored => _public_stored( $result->{stored} ),
    );
}

sub _public_stored ($stored) {
    my $public = { ok => $stored->{ok}, };
    $public->{attachment} = _public_attachment( $stored->{attachment} );
    $public->{idempotent} = $stored->{idempotent};
    $public->{link}       = _public_link( $stored->{link} );
    $public->{post}       = _public_post( $stored->{post} );

    return $public;
}

sub _public_attachment ($attachment) {
    if ( !$attachment ) {
        return undef;
    }

    return {
        attachment_id     => column_of( $attachment, 'attachment_id' ),
        byte_size         => column_of( $attachment, 'byte_size' ),
        media_type        => column_of( $attachment, 'media_type' ),
        original_filename => column_of( $attachment, 'original_filename' ),
        scan_status       => column_of( $attachment, 'scan_status' ),
        state             => column_of( $attachment, 'state' ),
    };
}

sub _public_link ($link) {
    if ( !$link ) {
        return undef;
    }

    return {
        attachment_id      => column_of( $link, 'attachment_id' ),
        attachment_link_id => column_of( $link, 'attachment_link_id' ),
        target_id          => column_of( $link, 'target_id' ),
        target_type        => column_of( $link, 'target_type' ),
    };
}

sub _public_post ($post) {
    if ( !$post ) {
        return undef;
    }

    return {
        post_id   => column_of( $post, 'post_id' ),
        thread_id => column_of( $post, 'thread_id' ),
    };
}

sub _failed_result {
    return workflow_result(
        error  => 'attachment store failed',
        status => 'failed',
    );
}

async sub _delete_once_p ( $self, $input, $functions, $context ) {
    my $post =
      await $self->post_reader->find_visible_post_p( $input->{post_id},
        $input->{viewer}, $context );
    return undef if !$post;
    return { error => 'post author required', forbidden => 1 }
      if !_same_author( $post, $input->{actor_user_id} );

    return _linked_delete(
        await $self->store->delete_linked_p(
            _delete_link( $input, $post ),
            $functions, $context
        ),
        $post,
    );
}

sub _delete_link ( $input, $post ) {
    return {
        actor_id      => $input->{actor_user_id},
        attachment_id => $input->{attachment_id},
        target_id     => column_of( $post, 'post_id' ),
        target_type   => 'post',
    };
}

sub _download_input ($input) {
    return {
        attachment_id  => $input->{attachment_id},
        preview        => $input->{preview},
        viewer         => $input->{viewer},
        viewer_user_id => $input->{viewer_user_id},
    };
}

sub _linked_upload ( $uploaded, $post ) {
    if ( !$uploaded ) {
        return undef;
    }
    if ( !$uploaded->{ok} ) {
        return {
            errors  => $uploaded->{errors} || {},
            invalid => 1,
        };
    }

    return { %{$uploaded}, post => $post, };
}

sub _linked_delete ( $deleted, $post ) {
    if ( !$deleted ) {
        return undef;
    }
    if ( !$deleted->{ok} ) {
        return $deleted;
    }

    return { %{$deleted}, post => $post, };
}

sub _same_author ( $post, $user_id ) {
    return ( column_of( $post, 'author_user_id' ) || q{} ) eq
      ( $user_id || q{} );
}

# A store that died failed and is logged; otherwise its answer decides.
sub _store_answer ( $self, $not_found, $value, $failure ) {
    if ( defined $failure ) {
        log_error( $self->logger, "attachment request failed: $failure" );
        return workflow_result(
            error  => 'attachment store failed',
            status => 'failed',
        );
    }

    return _stored_result( $not_found, $value );
}

# The result a store call answers: not_found when it found nothing, a refusal
# it tagged (forbidden, invalid) or reported as ok => 0, else ok.
sub _stored_result ( $not_found, $value ) {
    if ( !$value ) {
        return workflow_result( error => $not_found, status => 'not_found' );
    }
    if ( $value->{forbidden} ) {
        return workflow_result(
            error  => $value->{error},
            status => 'forbidden'
        );
    }
    if ( $value->{invalid} ) {
        return workflow_result(
            errors => $value->{errors},
            status => 'invalid'
        );
    }
    if ( ref $value eq 'HASH' && exists $value->{ok} && !$value->{ok} ) {
        my $missing = ( $value->{error} || q{} ) eq 'not_found';
        my $fallback =
          $missing ? 'attachment not found' : 'attachment is not available';
        return workflow_result(
            error  => $value->{error} || $fallback,
            status => $missing ? 'not_found' : 'forbidden',
        );
    }

    return workflow_result( status => 'ok', stored => $value );
}

1;

__END__

=head1 NAME

GPForum::Service::Attachment::Workflow - Attachment upload and download writes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = await $workflow->upload_for_post_p(
        {
            actor_user_id => $user_id,
            command_id    => $command_id,
            post_id       => $post_id,
            upload        => $upload,
        }
    );

=head1 DESCRIPTION

Application boundary for post attachment uploads, author deletes, and
attachment downloads.
Looks up a visible post, enforces author ownership, and delegates binary
storage to the existing upload pipeline and delivery service. Upload and
delete require C<command_id> and replay from the command log
(C<command_idempotency>, required). Command hashes include actor and
target ids only, never the uploaded bytes. Returns a normalized JSON-safe
result hash. Stores keep transaction, event, audit, and object storage
ownership.
A failed command log or write is logged at C<error> level through C<logger>
(a L<Mojo::Log>, or anything with C<error>) when one is given.

Each operation is written once, as its promise method (ADR 0177), and
takes an optional query context last. The blocking methods are its twins,
settled on the blocking layer with the command log, the delivery, the post
reader and the store; the pipeline is handed the command's call layer.

=head1 SUBROUTINES/METHODS

=head2 upload_for_post_p

Uploads and links an attachment to a visible post owned by the actor.
Requires C<command_id>. The source is scanned first, before any
transaction opens: in the process on a blocking layer, else in a child that
cannot reach the database. Then the command log's steps, the post's locks,
the attachment's rows and, in PostgreSQL storage, its bytes commit in one
transaction. Bytes written for a command that did not go through are
discarded. C<upload_for_post> is its blocking twin.

=head2 delete_for_post_p

Soft-deletes an attachment linked to a visible post owned by the actor.
Already-deleted rows replay as success. Requires C<command_id>. The
command log's steps, the post's locks and the store's writes commit in one
transaction. C<delete_for_post> is its blocking twin.

=head2 download_p

Delivers attachment bytes for an authorized viewer. C<download> is its
blocking twin.

=head2 download_metadata_p

Authorizes a download and returns a data-only descriptor for
reconstruction in the web process; database handles never cross subprocess
IPC. C<download_metadata> is its blocking twin.

=head1 DIAGNOSTICS

Returns C<invalid>, C<not_found>, C<forbidden>, C<conflict>, or C<failed>
statuses instead of throwing for expected outcomes. Unexpected store
exceptions are logged and mapped to C<failed>.

=head1 CONFIGURATION AND ENVIRONMENT

Uses post reader, upload pipeline, attachment store, and delivery services
supplied by the composition root.

=head1 DEPENDENCIES

Uses L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Rate limits and CSRF checks remain in the HTTP controller.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
