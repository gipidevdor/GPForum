# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Search::Semantic;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';
__PACKAGE__->requires(qw(schema embedding));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Called after lexical indexing commits. Slow model inference never holds
# the document lock. Publication checks the exact projection we read again.
sub index_entity ( $self, $type, $id ) {
    my $source = $self->functions->row(
        'search_embedding_source',
        {
            entity_type => $type,
            entity_id   => $id,
            model_key   => $self->embedding->model_key,
        }
    );
    return if !$source;
    my $vector = $self->embedding->embed( $source->{text} );
    return $self->functions->row(
        'search_embedding_store',
        {
            document_id => $source->{document_id},
            fingerprint => $source->{fingerprint},
            model_key   => $self->embedding->model_key,
            embedding   => $vector,
        }
    );
}

sub ranked_call ( $self, $parameters ) {
    my %values = %{$parameters};
    delete @values{qw(like_pattern candidate_limit)};
    return [
        'search_semantic_ranked',
        {
            %values,
            model_key     => $self->embedding->model_key,
            embedding     => $self->embedding->embed( $values{query} ),
            thread_filter => $values{thread_filter},
            tag_slugs     => $values{tag_slugs} // [],
            tag_match     => $values{tag_match} // 'all',
        }
    ];
}

1;

__END__

=head1 NAME

GPForum::Service::Search::Semantic - Local embedding projection and retrieval.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $semantic->index_entity('thread', $id);
    my $call = $semantic->ranked_call($validated_search_parameters);

=head1 DESCRIPTION

Publishes embeddings only while the source projection fingerprint still
matches. Model identity isolates incompatible embeddings. The SQL retrieval
applies the same access and search filters as lexical search.

=head1 SUBROUTINES/METHODS

=head2 index_entity

Embeds a missing or stale document, outside its indexing transaction.

=head2 ranked_call

Builds a typed semantic search call from validated lexical search parameters.

=head1 DIAGNOSTICS

Indexing failures propagate for outbox retry; reads fall back in Searcher.

=head1 CONFIGURATION AND ENVIRONMENT

An embedding provider is required. No remote service is used.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction> and pgvector.

=head1 INCOMPATIBILITIES

Requires the PostgreSQL function adapter.

=head1 BUGS AND LIMITATIONS

Projection updates invalidate old embeddings until asynchronous indexing runs.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause license.

=cut
