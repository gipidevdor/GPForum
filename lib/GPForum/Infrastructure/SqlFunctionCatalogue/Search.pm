# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::SqlFunctionCatalogue::Search;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my %FUNCTION => (

    search_embedding_source => {
        version    => 2,
        parameters =>
          [ entity_type => 'text', entity_id => 'uuid', model_key => 'text' ],
    },
    search_embedding_store => {
        version    => 2,
        parameters => [
            document_id => 'uuid',
            fingerprint => 'text',
            model_key   => 'text',
            embedding   => 'text'
        ],
    },
    search_semantic_ranked => {
        version    => 2,
        parameters => [
            permission_mode   => 'text',
            visibility_values => 'text[]',
            member            => 'boolean',
            global_read       => 'boolean',
            viewer_user_id    => 'uuid',
            category_ids      => 'uuid[]',
            space_ids         => 'uuid[]',
            query             => 'text',
            config            => 'text',
            category_filter   => 'uuid',
            author_filter     => 'uuid',
            from_at           => 'timestamp with time zone',
            to_at             => 'timestamp with time zone',
            to_exclusive      => 'boolean',
            row_limit         => 'integer',
            entity_type       => 'text',
            thread_filter     => 'uuid',
            tag_slugs         => 'text[]',
            tag_match         => 'text',
            model_key         => 'text',
            embedding         => 'text',
        ],
    },
    search_ranked => {
        version    => 16,
        parameters => [
            permission_mode   => 'text',
            visibility_values => 'text[]',
            member            => 'boolean',
            global_read       => 'boolean',
            viewer_user_id    => 'uuid',
            category_ids      => 'uuid[]',
            space_ids         => 'uuid[]',
            query             => 'text',
            like_pattern      => 'text',
            config            => 'text',
            candidate_limit   => 'integer',
            category_filter   => 'uuid',
            author_filter     => 'uuid',
            from_at           => 'timestamp with time zone',
            to_at             => 'timestamp with time zone',
            to_exclusive      => 'boolean',
            row_limit         => 'integer',
            entity_type       => 'text'
        ]
    },
    search_tagged_ranked => {
        version    => 2,
        parameters => [
            permission_mode   => 'text',
            visibility_values => 'text[]',
            member            => 'boolean',
            global_read       => 'boolean',
            viewer_user_id    => 'uuid',
            category_ids      => 'uuid[]',
            space_ids         => 'uuid[]',
            query             => 'text',
            like_pattern      => 'text',
            config            => 'text',
            candidate_limit   => 'integer',
            category_filter   => 'uuid',
            author_filter     => 'uuid',
            from_at           => 'timestamp with time zone',
            to_at             => 'timestamp with time zone',
            to_exclusive      => 'boolean',
            row_limit         => 'integer',
            entity_type       => 'text',
            tag_slugs         => 'text[]',
            tag_match         => 'text'
        ]
    },
    search_thread_ranked => {
        version    => 8,
        parameters => [
            permission_mode   => 'text',
            visibility_values => 'text[]',
            member            => 'boolean',
            global_read       => 'boolean',
            viewer_user_id    => 'uuid',
            category_ids      => 'uuid[]',
            space_ids         => 'uuid[]',
            query             => 'text',
            like_pattern      => 'text',
            config            => 'text',
            candidate_limit   => 'integer',
            category_filter   => 'uuid',
            author_filter     => 'uuid',
            from_at           => 'timestamp with time zone',
            to_at             => 'timestamp with time zone',
            to_exclusive      => 'boolean',
            row_limit         => 'integer',
            entity_type       => 'text',
            thread_filter     => 'uuid'
        ]
    },
    search_tagged_thread_ranked => {
        version    => 2,
        parameters => [
            permission_mode   => 'text',
            visibility_values => 'text[]',
            member            => 'boolean',
            global_read       => 'boolean',
            viewer_user_id    => 'uuid',
            category_ids      => 'uuid[]',
            space_ids         => 'uuid[]',
            query             => 'text',
            like_pattern      => 'text',
            config            => 'text',
            candidate_limit   => 'integer',
            category_filter   => 'uuid',
            author_filter     => 'uuid',
            from_at           => 'timestamp with time zone',
            to_at             => 'timestamp with time zone',
            to_exclusive      => 'boolean',
            row_limit         => 'integer',
            entity_type       => 'text',
            thread_filter     => 'uuid',
            tag_slugs         => 'text[]',
            tag_match         => 'text'
        ]
    },
    search_autocomplete => {
        version    => 8,
        parameters => [
            permission_mode   => 'text',
            visibility_values => 'text[]',
            member            => 'boolean',
            global_read       => 'boolean',
            viewer_user_id    => 'uuid',
            category_ids      => 'uuid[]',
            space_ids         => 'uuid[]',
            like_pattern      => 'text',
            row_limit         => 'integer'
        ]
    },
    search_set_timeout => { version => 2, parameters => [ timeout => 'text' ] },
    search_index_entity => {
        version    => 4,
        parameters => [
            entity_type => 'text',
            entity_id   => 'uuid',
            document_id => 'uuid',
            indexed_at  => 'text',
            config      => 'text'
        ],
        json => ['result']
    },
    search_remove_document => {
        version    => 2,
        parameters => [ entity_type => 'text', entity_id => 'uuid' ],
        json       => ['result']
    },
    search_thread_post_batch => {
        version    => 2,
        parameters => [
            thread_id      => 'uuid',
            after_position => 'bigint',
            row_limit      => 'integer'
        ]
    },
    search_live_ids => {
        version    => 2,
        parameters =>
          [ entity_type => 'text', after_id => 'uuid', row_limit => 'integer' ]
    },
    search_prune_candidates =>
      { version => 2, parameters => [ entity_type => 'text' ] },
    search_remove_post_batch => {
        version    => 2,
        parameters => [ thread_id => 'uuid', post_ids => 'uuid[]' ]
    },
    search_observe_lag    => { version => 4, parameters => [] },
    search_latest_rebuild => { version => 2, parameters => [] },
);

sub entries ($class) {
    return \%FUNCTION;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::SqlFunctionCatalogue::Search - The PostgreSQL functions of search: documents, queries and the semantic projection.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $entries = GPForum::Infrastructure::SqlFunctionCatalogue::Search->entries;

=head1 DESCRIPTION

A part of the table L<GPForum::Infrastructure::SqlFunctionCatalogue> reads:
the entries for the functions of search: documents, queries and the semantic projection. See that module for what an
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
