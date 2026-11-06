# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::ContentReview;

use Mojo::Base 'GPForum::Base', -signatures;
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
has functions    => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};
has recorder => sub ($self) {
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
    return _invalid( 'attachment', 'this content has been rejected' )
      if $self->functions->row( 'attachment_content_blocked',
        { checksum => $checksum } )->{blocked};
    return { ok => 1 };
}

sub submit ( $self, $id, $input ) {
    return $self->functions->row(
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
    return [
        map { $_->{result} } @{
            $self->functions->rows(
                'attachment_review_queue',
                {
                    after_at  => $after_at,
                    after_id  => $after_id,
                    row_limit => $FETCH_LIMIT,
                }
            )
        }
    ];
}

sub find ( $self, $id ) {
    my $row = $self->functions->row( 'attachment_review_find',
        { attachment_id => $id } );
    return $row ? $row->{result} : undef;
}

sub decide ( $self, $input ) {
    return $self->schema->txn_do(
        sub {
            if ( ( $input->{decision} // q{} ) eq 'approved' ) {
                my $file = $self->find( $input->{attachment_id} );
                return { status => 'not_found' } if !$file;
                return { status => 'refused' }
                  if !$self->validate_source(
                    {
                        %{$file}, rights_confirmed => 1,
                    }
                  )->{ok};
            }
            my $answer = $self->functions->row(
                'attachment_review_decide',
                {
                    attachment_id => $input->{attachment_id},
                    actor         => $input->{actor_user_id},
                    status        => $input->{decision},
                    reason        => $input->{reason} // q{},
                }
            ) // { status => 'not_found' };
            if ( $answer->{status} eq 'ok' ) {
                $self->recorder->record_audit(
                    action      => 'attachment.content.' . $input->{decision},
                    actor_id    => $input->{actor_user_id},
                    target_type => 'attachment',
                    target_id   => $input->{attachment_id},
                    metadata    => { reason => $input->{reason} },
                );
                if ( $input->{decision} eq 'approved' ) {
                    $self->recorder->record_event(
                        event_type     => 'attachment.content.approved',
                        aggregate_type => 'attachment',
                        aggregate_id   => $input->{attachment_id},
                        actor_id       => $input->{actor_user_id},
                        schema_version => 1,
                        payload        => {
                            attachment_id => $input->{attachment_id},
                            scan_status   => 'clean'
                        },
                    );
                }
            }
            return $answer;
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
exact hostname an operator authorized. Never fetches that URL. Every upload
requires a separate staff decision, a clean malware result and a reason;
authors cannot approve themselves. Rejected SHA-256 checksums block exact
reuploads. This is human content review, not an automatic legality classifier.

=head1 SUBROUTINES/METHODS

=head2 validate_source

Requires rights confirmation and original authorship or an explicitly authorized HTTPS source hostname.


=head2 validate_checksum

Rejects an exact SHA-256 match of content staff previously rejected.


=head2 submit

Creates the pending content review before scanning can publish an upload.


=head2 queue

Returns at most 51 pending entries, ordered with a timestamp and UUID keyset cursor.


=head2 find

Returns one live upload and its review details for an authorized staff preview.


=head2 decide

Makes a decision and its audit entry atomically, and queues media processing on approval.

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
