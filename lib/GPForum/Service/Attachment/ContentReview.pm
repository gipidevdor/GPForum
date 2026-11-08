# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::ContentReview;

use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::SqlFunction;
use Const::Fast;
use Mojo::URL;

our $VERSION = '0.001';
const my $SOURCE_URL_LENGTH => 2_048;
const my $HTTPS_PORT        => 443;
const my $FETCH_LIMIT       => 51;
__PACKAGE__->requires('schema');
has source_hosts => sub { return []; };
has functions    => \&GPForum::Infrastructure::SqlFunction::for_service;
has recorder     => sub ($self) {
    return GPForum::Infrastructure::EventRecorder->new(
        schema => $self->schema );
};

sub validate_source ( $self, $input ) {
    my $kind = $input->{source_kind} // q{};
    return _invalid( 'source_kind', 'source is required' )
      if $kind ne 'original' && $kind ne 'authorized';
    my $confirmed = $input->{rights_confirmed} // q{};
    return _invalid( 'rights_confirmed', 'content rights must be confirmed' )
      if $confirmed ne '1' && $confirmed ne 'on';
    return { ok => 1 } if $kind eq 'original';
    return _invalid( 'source_url', 'an authorized HTTPS source is required' )
      if !$self->_authorized_source( $input->{source_url} // q{} );
    return { ok => 1 };
}

sub _authorized_source ( $self, $source ) {
    return 0
      if length $source > $SOURCE_URL_LENGTH || $source =~ /[\x00-\x20]/msx;
    my $url = Mojo::URL->new($source);
    return 0 if ( $url->scheme // q{} ) ne 'https' || $url->userinfo;
    return 0 if defined $url->port && $url->port != $HTTPS_PORT;
    my %allowed = map { (lc) => 1 } @{ $self->source_hosts };
    return defined $url->host && $allowed{ lc $url->host } ? 1 : 0;
}

sub validate_checksum ( $self, $checksum ) {
    return _checksum_answer(
        $self->functions->row(
            'attachment_content_blocked', { checksum => $checksum }
        )
    );
}

# validate_checksum on the worker's pooled asynchronous connections, or on
# the transaction $functions belongs to.
async sub validate_checksum_p (
    $self, $checksum,
    $context = undef,
    $functions = undef
  )
{
    $functions //= $self->functions;
    return $self->validate_checksum($checksum) if !$functions;
    return _checksum_answer(
        await $functions->row_p(
            'attachment_content_blocked', { checksum => $checksum },
            $context
        )
    );
}

sub _checksum_answer ($blocked) {
    return _invalid( 'attachment', 'this content has been rejected' )
      if $blocked->{blocked};
    return { ok => 1 };
}

sub submit ( $self, $id, $input ) {
    return $self->functions->row( _submit_values( $id, $input ) );
}

# submit on the worker's pooled asynchronous connections, or on the
# transaction $functions belongs to.
async sub submit_p ( $self, $id, $input, $context = undef, $functions = undef )
{
    $functions //= $self->functions;
    return $self->submit( $id, $input ) if !$functions;
    return await $functions->row_p( _submit_values( $id, $input ), $context );
}

sub _submit_values ( $id, $input ) {
    return (
        'attachment_review_submit',
        {
            attachment_id => $id,
            source_kind   => $input->{source_kind},
            source_url    => $input->{source_kind} eq 'authorized'
            ? $input->{source_url}
            : q{},
        }
    );
}

sub queue ( $self, $after_at = undef, $after_id = undef ) {
    return [ map { $_->{result} }
          @{ $self->functions->rows( _queue_values( $after_at, $after_id ) ) }
    ];
}

# The media review page's read on the worker's pooled asynchronous
# connections, not a forked child with a connection of its own.
async sub queue_p ( $self, $after_at = undef, $after_id = undef,
    $context = undef )
{
    return [
        map { $_->{result} }
          @{ await $self->functions->rows_p(
                _queue_values( $after_at, $after_id ), $context )
          }
    ];
}

sub _queue_values ( $after_at, $after_id ) {
    return (
        'attachment_review_queue',
        {
            after_at  => $after_at,
            after_id  => $after_id,
            row_limit => $FETCH_LIMIT,
        }
    );
}

sub find ( $self, $id ) {
    my $row = $self->functions->row( 'attachment_review_find',
        { attachment_id => $id } );
    return $row ? $row->{result} : undef;
}

# The same upload read on the worker's pooled asynchronous connections.
async sub find_p ( $self, $id, $context = undef ) {
    return $self->find($id) if !$self->functions;
    my $row = await $self->functions->row_p( 'attachment_review_find',
        { attachment_id => $id }, $context );
    return $row ? $row->{result} : undef;
}

sub decide ( $self, $input ) {
    return $self->schema->txn_do(
        sub {
            if ( _approves($input) ) {
                my $refusal =
                  $self->_approval_refusal(
                    $self->find( $input->{attachment_id} ) );
                return $refusal if $refusal;
            }
            my $answer = $self->functions->row( _decide_values($input) )
              // { status => 'not_found' };
            if ( $answer->{status} eq 'ok' ) {
                my ( $audit, $event ) = _decision_records($input);
                $self->recorder->record_audit( %{$audit} );
                if ($event) { $self->recorder->record_event( %{$event} ); }
            }
            return $answer;
        }
    );
}

# The same decision, its audit and its event in one transaction on the
# worker's pooled asynchronous connections, not a forked child with a
# connection of its own.
async sub decide_p ( $self, $input, $context = undef ) {
    return $self->decide($input) if !$self->functions;
    return await $self->functions->transaction_p(
        async sub ($scope) {
            if ( _approves($input) ) {
                my $row = await $scope->row_p( 'attachment_review_find',
                    { attachment_id => $input->{attachment_id} } );
                my $refusal =
                  $self->_approval_refusal( $row ? $row->{result} : undef );
                return $refusal if $refusal;
            }
            my $answer = ( await $scope->row_p( _decide_values($input) ) )
              // { status => 'not_found' };
            if ( $answer->{status} eq 'ok' ) {
                my ( $audit, $event ) = _decision_records($input);
                await $scope->row_p( 'ops_record_audit',
                    $self->recorder->audit_call( %{$audit} ) );
                if ($event) {
                    await $scope->row_p( 'ops_record_event',
                        $self->recorder->event_call( %{$event} ) );
                }
            }
            return $answer;
        },
        $context
    );
}

sub _approves ($input) {
    return ( $input->{decision} // q{} ) eq 'approved' ? 1 : 0;
}

# An upload that cannot be approved: gone, or its source not authorized.
sub _approval_refusal ( $self, $file ) {
    return { status => 'not_found' } if !$file;
    return { status => 'refused' }
      if !$self->validate_source( { %{$file}, rights_confirmed => 1, } )->{ok};
    return undef;
}

sub _decide_values ($input) {
    return (
        'attachment_review_decide',
        {
            attachment_id => $input->{attachment_id},
            actor         => $input->{actor_user_id},
            status        => $input->{decision},
            reason        => $input->{reason} // q{},
        }
    );
}

# The decision's audit, and the event an approval publishes.
sub _decision_records ($input) {
    my $audit = {
        action      => 'attachment.content.' . $input->{decision},
        actor_id    => $input->{actor_user_id},
        target_type => 'attachment',
        target_id   => $input->{attachment_id},
        metadata    => { reason => $input->{reason} },
    };
    return ($audit) if $input->{decision} ne 'approved';
    return (
        $audit,
        {
            event_type     => 'attachment.content.approved',
            aggregate_type => 'attachment',
            aggregate_id   => $input->{attachment_id},
            actor_id       => $input->{actor_user_id},
            schema_version => 1,
            payload        => {
                attachment_id => $input->{attachment_id},
                scan_status   => 'clean'
            },
        }
    );
}

sub _invalid ( $field, $message ) {
    return { ok => 0, errors => { $field => $message } };
}

1;

__END__

=head1 NAME

GPForum::Service::Attachment::ContentReview - Provenance and publication policy.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $review = GPForum::Service::Attachment::ContentReview->new(schema => $schema);

=head1 DESCRIPTION

Accepts original content attested by its author, or an HTTPS source whose
exact hostname an operator authorized. Never fetches that URL. An attested
original needs no separate staff decision. Third-party content requires a
separate staff decision and reason; authors cannot approve those uploads
themselves. Both paths retain malware scanning and rejected SHA-256 checksums.
This policy is not an automatic legality classifier.

=head1 SUBROUTINES/METHODS

=head2 validate_source

Requires rights confirmation and original authorship or an explicitly authorized HTTPS source hostname.


=head2 validate_checksum

Rejects an exact SHA-256 match of content staff previously rejected.


=head2 validate_checksum_p

L</validate_checksum> as a promise, with an optional query context and an
optional transaction call layer last: the blocked-content list is read on
the worker's pooled asynchronous connections.

=head2 submit_p

L</submit> as a promise, with an optional query context and an optional
transaction call layer last, so the review row commits with the upload's
own rows.

=head2 submit

Records the source attestation before scanning. Originals satisfy content
policy automatically; third-party content enters the staff review queue.


=head2 queue

Returns at most 51 pending entries, ordered with a timestamp and UUID keyset cursor.

=head2 queue_p

L</queue> as a promise, with an optional query context after the two cursor
values, read on the worker's pooled asynchronous connections.

=head2 find

Returns one live upload and its review details for an authorized staff preview.

=head2 find_p

L</find> as a promise, with an optional query context last, read on the
worker's pooled asynchronous connections.


=head2 decide

Makes a decision and its audit entry atomically, and queues media processing on approval.

=head2 decide_p

L</decide> as a promise, with an optional query context last: the
decision, its audit and its event in one transaction on the worker's pooled
asynchronous connections.

=head1 DIAGNOSTICS

Returns field validation errors and decision statuses; database and audit failures propagate.

=head1 CONFIGURATION AND ENVIRONMENT

The composition layer supplies the schema, storage and source policy.

=head1 DEPENDENCIES

L<Mojo::Base> and the composed Good Phorum services.

=head1 INCOMPATIBILITIES

Human review does not automatically classify legality, verify authorship or match altered copies.

=head1 BUGS AND LIMITATIONS

Human review does not automatically classify legality, verify authorship or match altered copies.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
