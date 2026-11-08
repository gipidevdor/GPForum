# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::Workflow;

use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Service::WorkflowResult
  qw(log_error missing_command_id workflow_result);
our $VERSION = '0.001';

has command_idempotency => undef;    # optional: writes run unlogged without it
__PACKAGE__->requires(qw(delivery pipeline post_reader store));
has logger => undef;                 # optional: failures go unlogged

sub upload_for_post ( $self, $input ) {
    my $invalid = missing_command_id($input);
    if ($invalid) {
        return $invalid;
    }

    return $self->_commanded_upload($input);
}

sub _commanded_upload ( $self, $input ) {
    return $self->_settled(
        $self->_commanded_write(
            {
                %{ _upload_job($input) },
                run => sub { return $self->_upload_store_write($input); },
            }
        )
    );
}

# The upload on the worker's pooled asynchronous connections: the command
# log's steps, the post's locks, the rows and, in PostgreSQL storage, the
# bytes in one transaction. The scan runs in a child that cannot reach the
# database.
async sub upload_for_post_p ( $self, $input, $context = undef ) {
    my $invalid = missing_command_id($input);
    return $invalid if $invalid;
    my ( $store, $log ) = ( $self->store, $self->command_idempotency );
    return $self->upload_for_post($input)
      if !$store->can('with_post_write_p')
      || !$store->functions
      || !$self->pipeline->can('upload_and_link_p')
      || ( $log && !$log->can('result_of_p') );

    # The scan reads the source alone: it runs before the command's
    # transaction takes a pooled connection and the post's locks.
    if ( $self->pipeline->can('prescan_p') ) {
        $input =
          { %{$input}, prescanned => await $self->pipeline->prescan_p($input) };
    }
    my $run_p = async sub ($scope) {
        return await $self->_post_store_write_p(
            $input, $scope, $context,
            sub ($functions) {
                return $self->_upload_once_p( $input, $functions, $context );
            }
        );
    };
    my $result;
    try {
        $result =
          $log
          ? await $log->result_of_p(
            { %{ _upload_job($input) }, run_p => $run_p }, $context )
          : await $store->functions->transaction_p( $run_p, $context );
    }
    catch ($error) {
        log_error( $self->logger, "attachment command log failed: $error" );
        $result = _failed_result();
    };
    return $self->_settled($result);
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

sub _upload_store_write ( $self, $input ) {
    return _public_write_result(
        $self->_run_store(
            'post not found',
            sub {
                return $self->_post_write( $input,
                    sub { return $self->_upload_once($input); } );
            },
        )
    );
}

sub download ( $self, $input ) {
    return $self->_run_store(
        'attachment not found',
        sub { return $self->_download_once($input); },
    );
}

sub download_metadata ( $self, $input ) {
    return _metadata( $self->download($input) );
}

# The download's decision on the worker's pooled asynchronous connections.
async sub download_metadata_p ( $self, $input, $context = undef ) {
    my $delivery = $self->delivery;
    return $self->download_metadata($input) if !$delivery->can('download_p');
    my ( $value, $failure );
    try {
        $value =
          await $delivery->download_p( _download_input($input), $context );
    }
    catch ($error) { $failure = $error; };
    return _metadata(
        $self->_store_answer( 'attachment not found', $value, $failure ) );
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

sub _upload_once ( $self, $input ) {
    my $post = $self->post_reader->find_visible_post( $input->{post_id},
        $input->{viewer} );
    if ( !$post ) {
        return undef;
    }
    if ( !_same_author( $post, $input->{actor_user_id} ) ) {
        return {
            error     => 'post author required',
            forbidden => 1,
        };
    }

    return _linked_upload(
        $self->pipeline->upload_and_link( _upload_request( $input, $post ) ),
        $post, );
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
        target_id        => _column( $post, 'post_id' ),
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

sub delete_for_post ( $self, $input ) {
    my $invalid = missing_command_id($input);
    if ($invalid) {
        return $invalid;
    }

    return $self->_commanded_delete($input);
}

sub _commanded_delete ( $self, $input ) {
    return $self->_commanded_write(
        {
            %{ _delete_job($input) },
            run => sub { return $self->_delete_store_write($input); },
        }
    );
}

# The deletion on the worker's pooled asynchronous connections: the command
# log's steps, the post's locks and the store's writes in one transaction.
async sub delete_for_post_p ( $self, $input, $context = undef ) {
    my $invalid = missing_command_id($input);
    return $invalid if $invalid;
    my ( $store, $log ) = ( $self->store, $self->command_idempotency );
    return $self->delete_for_post($input)
      if !$store->can('delete_linked_p')
      || !$store->functions
      || ( $log && !$log->can('result_of_p') );

    my $run_p = async sub ($scope) {
        return await $self->_post_store_write_p(
            $input, $scope, $context,
            sub ($functions) {
                return $self->_delete_once_p( $input, $functions, $context );
            }
        );
    };
    my $result;
    try {
        $result =
          $log
          ? await $log->result_of_p(
            { %{ _delete_job($input) }, run_p => $run_p }, $context )
          : await $store->functions->transaction_p( $run_p, $context );
    }
    catch ($error) {
        log_error( $self->logger, "attachment command log failed: $error" );
        return _failed_result();
    };
    return $result;
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
# in the transaction $scope belongs to.
async sub _post_store_write_p ( $self, $input, $scope, $context, $once_p ) {
    my ( $value, $failure );
    try {
        $value = await $self->store->with_post_write_p( $input, $once_p, $scope,
            $context );

        # As _post_write: a guard's refusal does not reveal a post the
        # viewer cannot read.
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

sub _delete_store_write ( $self, $input ) {
    return _public_write_result(
        $self->_run_store(
            'post not found',
            sub {
                return $self->_post_write( $input,
                    sub { return $self->_delete_once($input); } );
            },
        )
    );
}

# The store holds the thread and post stable through both the visible read
# and the side effect. In-memory boundary doubles do not own database locks.
sub _post_write ( $self, $input, $work ) {
    return $work->() if !$self->store->can('with_post_write');
    my $result = $self->store->with_post_write( $input, $work );

    # A guard refusal must not reveal a post the viewer cannot read. The
    # successful path performs this audience check inside the held locks.
    return undef
      if $result
      && $result->{forbidden}
      && !$self->post_reader->find_visible_post( $input->{post_id},
        $input->{viewer} );
    return $result;
}

sub _commanded_write ( $self, $job ) {
    if ( !$self->command_idempotency ) {
        return $job->{run}->();
    }

    return $self->_idempotent_write($job);
}

sub _idempotent_write ( $self, $job ) {
    my $result;
    try {
        $result = $self->command_idempotency->result_of($job);
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
        attachment_id     => _column( $attachment, 'attachment_id' ),
        byte_size         => _column( $attachment, 'byte_size' ),
        media_type        => _column( $attachment, 'media_type' ),
        original_filename => _column( $attachment, 'original_filename' ),
        scan_status       => _column( $attachment, 'scan_status' ),
        state             => _column( $attachment, 'state' ),
    };
}

sub _public_link ($link) {
    if ( !$link ) {
        return undef;
    }

    return {
        attachment_id      => _column( $link, 'attachment_id' ),
        attachment_link_id => _column( $link, 'attachment_link_id' ),
        target_id          => _column( $link, 'target_id' ),
        target_type        => _column( $link, 'target_type' ),
    };
}

sub _public_post ($post) {
    if ( !$post ) {
        return undef;
    }

    return {
        post_id   => _column( $post, 'post_id' ),
        thread_id => _column( $post, 'thread_id' ),
    };
}

sub _failed_result {
    return workflow_result(
        error  => 'attachment store failed',
        status => 'failed',
    );
}

sub _delete_once ( $self, $input ) {
    my $post = $self->post_reader->find_visible_post( $input->{post_id},
        $input->{viewer} );
    if ( !$post ) {
        return undef;
    }
    if ( !_same_author( $post, $input->{actor_user_id} ) ) {
        return {
            error     => 'post author required',
            forbidden => 1,
        };
    }

    return _linked_delete(
        $self->store->delete_linked( _delete_link( $input, $post ) ), $post, );
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
        target_id     => _column( $post, 'post_id' ),
        target_type   => 'post',
    };
}

sub _download_once ( $self, $input ) {
    return $self->delivery->download( _download_input($input) );
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
    return ( _column( $post, 'author_user_id' ) || q{} ) eq ( $user_id || q{} );
}

sub _run_store ( $self, $not_found, $code ) {
    my ( $value, $failure );
    try {
        $value = $code->();
    }
    catch ($error) { $failure = $error; };

    return $self->_store_answer( $not_found, $value, $failure );
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

sub _column ( $row, $name ) {
    if ( !$row ) {
        return undef;
    }
    if ( ref $row eq 'HASH' ) {
        return $row->{$name};
    }

    return $row->can('get_column') ? $row->get_column($name) : undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Attachment::Workflow - Attachment upload and download writes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = $workflow->upload_for_post(
        {
            actor_user_id => $user_id,
            post_id       => $post_id,
            upload        => $upload,
        }
    );

=head1 DESCRIPTION

Application boundary for post attachment uploads, author deletes, and
attachment downloads.
Looks up a visible post, enforces author ownership, and delegates binary
storage to the existing upload pipeline and delivery service. Upload and
delete require C<command_id> and replay from C<command_log> when the
helper is present. Command hashes include actor and target ids only, never
the uploaded bytes. Returns a normalized JSON-safe result hash. Stores
keep transaction, event, audit, and object storage ownership.
A failed command log or write is logged at C<error> level through C<logger>
(a L<Mojo::Log>, or anything with C<error>) when one is given.

=head1 SUBROUTINES/METHODS

=head2 upload_for_post

Uploads and links an attachment to a visible post owned by the actor.
Requires C<command_id>.

=head2 upload_for_post_p

L</upload_for_post> as a promise, with an optional query context last: the
command log's steps, the post's locks, the attachment's rows and, in
PostgreSQL storage, its bytes commit in one transaction on the worker's
pooled asynchronous connections. Hashing a large upload and the antivirus
scan run in a child that cannot reach the database.

=head2 delete_for_post

Soft-deletes an attachment linked to a visible post owned by the actor.
Already-deleted rows replay as success. Requires C<command_id>.

=head2 delete_for_post_p

L</delete_for_post> as a promise, with an optional query context last: the
command log's steps, the post's locks and the store's writes commit in one
transaction on the worker's pooled asynchronous connections.

=head2 download

Delivers attachment bytes for an authorized viewer.

=head2 download_metadata

Authorizes a download and returns a data-only descriptor for reconstruction in the web process; database handles never cross subprocess IPC.

=head2 download_metadata_p

L</download_metadata> as a promise, with an optional query context last: the
decision and the object's size are read on the worker's pooled asynchronous
connections.

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
