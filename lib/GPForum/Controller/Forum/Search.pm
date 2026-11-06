# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Forum::Search;

use Const::Fast;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::Text qw(trimmed);
use GPForum::Service::Forum::ThreadTags;
use Mojo::Base 'GPForum::Controller::Forum::Base', -signatures;
use v5.40;

our $VERSION = '0.001';

const my $HTTP_OK => 200;

sub search ($self) {
    if ( !$self->read_allowed('search') ) {
        return $self->_rate_limited;
    }

    my $query   = trimmed( $self->param('q') );
    my $filters = $self->search_filters;
    my $tags =
      GPForum::Service::Forum::ThreadTags->filter_slugs( $filters->{tags} );
    my $match = $filters->{tag_match} // 'all';
    return $self->render(
        text   => $self->t('forum.tag_filter_invalid'),
        status => 400
    ) if !$tags || ( $match ne 'all' && $match ne 'any' );
    if ( length( $filters->{thread_id} // q{} ) ) {
        return $self->not_found('thread not found')
          if !GPForum::Infrastructure::Id->is_uuid( $filters->{thread_id} )
          || !$self->gp_thread_detail_reader->find_thread(
            $filters->{thread_id}, $self->gp_forum_viewer );
    }
    my $limit = $self->forum_access->search_page_limit( $self->param('limit') );

    if ( !length($query) && !@{$tags} ) {
        return $self->_search_page(
            {
                filters => $filters,
                limit   => $limit,
                query   => q{},
                results => [],
            }
        );
    }

    return $self->_search_results( $query, $filters, $limit );
}

sub _search_results ( $self, $query, $filters, $limit ) {
    my $found;
    try {
        $found = $self->gp_search_service->ranked_search(
            {
                user_id => $self->current_user_id,
                viewer  => $self->gp_forum_viewer,
            },
            $query,
            {
                %{$filters}, limit => $self->_search_fetch_limit($limit),
            },
        );
    }
    catch ($error) {
        $self->app->log->warn( 'search degraded: ' . _reason($error) );
        return $self->_search_page(
            {
                filters => $filters,
                limit   => $limit,
                query   => $query,
                results => [],
                status  => 'degraded',
            }
        );
    };

    return $self->_search_success(
        {
            filters => $filters,
            found   => $found,
            limit   => $limit,
            query   => $query,
        }
    );
}

sub _search_success ( $self, $input ) {
    my $limit = $input->{limit};
    my $found = $input->{found};
    if ( ( $found->{semantic_status} // q{} ) eq 'degraded' ) {
        $self->app->log->warn(
            'semantic search degraded; lexical results served');
    }
    my @results = @{ $found->{results} };
    if ( my $thread_id = $input->{filters}{thread_id} ) {
        for my $result (@results) {
            if ( ( $result->{entity_type} // q{} ) eq 'post' ) {
                $result->{source_thread_id} = $thread_id;
            }
        }
    }
    my $has_more = 0;
    if ( @results > $limit ) {
        $has_more = 1;
        while ( @results > $limit ) {
            pop @results;
        }
    }

    return $self->_search_page(
        {
            candidate_limit => $found->{candidate_limit},
            filters         => $input->{filters},
            has_more        => $has_more,
            limit           => $limit,
            more_limit => scalar $self->_search_more_limit( $has_more, $limit ),
            query      => $input->{query},
            ranking_capped => $found->{ranking_capped},
            results        => \@results,
        }
    );
}

sub _search_more_limit ( $self, $has_more, $limit ) {
    return $self->forum_access->search_more_limit( $has_more, $limit );
}

sub _search_fetch_limit ( $self, $limit ) {
    return $self->forum_access->search_fetch_limit($limit);
}

sub _search_page ( $self, $input ) {
    return $self->render_payload(
        {
            controller => $self,
            payload    => $self->gp_forum_view_model->search_page(
                candidate_limit => $input->{candidate_limit},
                filters         => $input->{filters},
                has_more        => $input->{has_more} || 0,
                limit           => $input->{limit},
                more_limit      => $input->{more_limit},
                query           => $input->{query},
                ranking_capped  => $input->{ranking_capped} || 0,
                results         => $input->{results}        || [],
                status          => $input->{status},
            ),
            status   => $HTTP_OK,
            template => 'forum/search',
        }
    );
}

sub search_autocomplete ($self) {
    my $query = trimmed( $self->param('q') || $self->param('prefix') );
    if ( $self->forum_access->autocomplete_too_short($query) ) {
        return $self->_autocomplete_payload( $query, [] );
    }
    if ( !$self->read_allowed('search.autocomplete') ) {
        return $self->_rate_limited;
    }

    return $self->_autocomplete_lookup($query);
}

sub _autocomplete_lookup ( $self, $query ) {
    my $rows;
    try {
        $rows = $self->gp_search_service->autocomplete(
            {
                user_id => $self->current_user_id,
                viewer  => $self->gp_forum_viewer,
            },
            $query,
            {
                limit => $self->forum_access->autocomplete_limit(
                    $self->param('limit')
                ),
            },
        );
    }
    catch ($error) {
        $self->app->log->warn( 'autocomplete degraded: ' . _reason($error) );
        return $self->_autocomplete_payload( $query, [], 'degraded' );
    };

    return $self->_autocomplete_payload( $query, $rows );
}

# Why a search failed, for the log. DBI appends the statement and its bind
# values to its error, and those carry what the visitor typed and a member's
# id. A search cancelled at its own statement timeout is routine under load,
# so each one logged several kilobytes of that; the reason before it is what
# an operator acts on.
sub _reason ($error) {
    my ($reason) = split /\s* \[for [ ] Statement [ ]/msx, "$error", 2;
    $reason =~ s/\s+ \z//msx;

    return $reason;
}

sub _autocomplete_payload ( $self, $query, $suggestions, $status = undef ) {
    return $self->render(
        json => $self->gp_forum_view_model->autocomplete_response(
            query       => $query,
            suggestions => $suggestions,
            status      => $status,
        ),
        status => $HTTP_OK,
    );
}

1;

__END__

=head1 NAME

GPForum::Controller::Forum::Search - Forum search and autocomplete.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/search')->to('Forum::Search#search');

=head1 DESCRIPTION

Renders search results and JSON autocomplete suggestions. Page and
autocomplete limits live on L<GPForum::Web::ForumAccess>. Search backend
failures stay logged here.

=head1 SUBROUTINES/METHODS

=head2 search

Renders the search page after the C<forum_retrieval> rate limit, degrading
to an empty result set on backend failure -- a search the database cancelled
at its own statement timeout included. Says so when the results were ranked
among the newest matches only.

=head2 search_autocomplete

Returns JSON autocomplete suggestions for a query prefix.

=head1 DIAGNOSTICS

Search backend failures are rendered as degraded empty results and logged as
C<search degraded: REASON> or C<autocomplete degraded: REASON>. The reason is
the error without the statement and bind values DBI appends to it, which carry
what the visitor typed.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the search service helper configured during application startup, with
C<GPFORUM_SEARCH_STATEMENT_TIMEOUT_MS> and C<GPFORUM_SEARCH_CANDIDATE_LIMIT>.

=head1 DEPENDENCIES

Uses L<GPForum::Controller::Forum::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

HTML search and autocomplete are rate-limited independently.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
