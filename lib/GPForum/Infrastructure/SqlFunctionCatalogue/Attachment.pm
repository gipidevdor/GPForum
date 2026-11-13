# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::SqlFunctionCatalogue::Attachment;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my %FUNCTION => (

    attachment_object_import_candidates => {
        version    => 2,
        parameters => [ after_key => 'text', row_limit => 'integer' ]
    },
    attachment_review_submit => {
        version    => 4,
        parameters => [
            attachment_id => 'uuid',
            source_kind   => 'text',
            source_url    => 'text'
        ]
    },
    attachment_content_blocked =>
      { version => 2, parameters => [ checksum => 'text' ] },
    attachment_review_queue => {
        version    => 2,
        parameters => [
            after_at  => 'timestamptz',
            after_id  => 'uuid',
            row_limit => 'integer'
        ],
        json => ['result']
    },
    attachment_review_find => {
        version    => 2,
        parameters => [ attachment_id => 'uuid' ],
        json       => ['result']
    },
    attachment_review_decide => {
        version    => 2,
        parameters => [
            attachment_id => 'uuid',
            actor         => 'uuid',
            status        => 'text',
            reason        => 'text'
        ]
    },

    attachment_object_create => {
        version    => 2,
        parameters =>
          [ object_key => 'text', byte_size => 'bigint', checksum => 'text' ],
    },
    attachment_object_chunk_insert => {
        version    => 2,
        parameters =>
          [ object_key => 'text', chunk_number => 'integer', data => 'bytea' ],
    },
    attachment_object_finish =>
      { version => 2, parameters => [ object_key => 'text' ] },
    attachment_object_info =>
      { version => 2, parameters => [ object_key => 'text' ] },
    attachment_object_chunk => {
        version    => 2,
        parameters => [ object_key => 'text', chunk_number => 'integer' ],
    },
    attachment_object_delete =>
      { version => 2, parameters => [ object_key => 'text' ] },

    attachment_post_write_guard => {
        version    => 2,
        parameters => [ post_id => 'uuid', actor => 'uuid' ]
    },
    attachment_upload_quota => {
        version    => 2,
        parameters => [
            owner_user_id => 'uuid',
            byte_size     => 'bigint',
            max_bytes     => 'bigint',
            max_pending   => 'integer'
        ]
    },
    attachment_find => {
        version    => 4,
        parameters =>
          [ attachment_id => 'uuid', object_key => 'text', hold => 'boolean' ]
    },
    attachment_owned_post_files => {
        version    => 2,
        parameters =>
          [ post_id => 'uuid', actor_id => 'uuid', after_id => 'uuid' ],
    },
    attachment_post_files => {
        version    => 2,
        parameters => [
            target_type => 'text',
            post_ids    => 'uuid[]',
            row_limit   => 'integer'
        ]
    },
    attachment_links => {
        version    => 6,
        parameters => [
            attachment_id => 'uuid',
            target_type   => 'text',
            target_id     => 'uuid',
            row_limit     => 'integer'
        ]
    },
    attachment_variants => {
        version    => 4,
        parameters => [
            attachment_id => 'uuid',
            variant_type  => 'text',
            object_key    => 'text',
            row_limit     => 'integer'
        ]
    },
    attachment_insert => { version => 4, parameters => [ values => 'jsonb' ] },
    attachment_link_insert =>
      { version => 4, parameters => [ values => 'jsonb' ] },
    attachment_variant_insert =>
      { version => 4, parameters => [ values => 'jsonb' ] },
    attachment_update => {
        version    => 4,
        parameters => [ attachment_id => 'uuid', changes => 'jsonb' ]
    },
    attachment_scan_verdict => {
        version    => 4,
        parameters => [ attachment_id => 'uuid', changes => 'jsonb' ]
    },
    attachment_scan_queue => {
        version    => 4,
        parameters => [ pending => 'boolean', row_limit => 'integer' ]
    },
    attachment_confirm_clean => {
        version    => 4,
        parameters => [
            attachment_id => 'uuid',
            scan_engine   => 'text',
            scanned_at    => 'timestamptz'
        ]
    },
    attachment_scan_failure => {
        version    => 4,
        parameters => [ attachment_id => 'uuid', error => 'text' ]
    },
    attachment_orphans => {
        version    => 4,
        parameters => [ cutoff => 'timestamptz', row_limit => 'integer' ]
    },
    attachment_source_post =>
      { version => 4, parameters => [ target_id => 'uuid' ] },
    attachment_source_thread =>
      { version => 4, parameters => [ target_id => 'uuid' ] },
);

sub entries ($class) {
    return \%FUNCTION;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::SqlFunctionCatalogue::Attachment - The PostgreSQL functions of attachments: uploads, storage, previews, quotas and delivery.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $entries = GPForum::Infrastructure::SqlFunctionCatalogue::Attachment->entries;

=head1 DESCRIPTION

A part of the table L<GPForum::Infrastructure::SqlFunctionCatalogue> reads:
the entries for the functions of attachments: uploads, storage, previews, quotas and delivery. See that module for what an
entry holds and for ADR 0126.

=head1 SUBROUTINES/METHODS

=head2 entries

The hash reference of entries, by name, read-only.

=head1 DIAGNOSTICS

None of its own.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Const::Fast.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
