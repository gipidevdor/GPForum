# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Search::DocumentBuilder;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my $DEFAULT_LANGUAGE => 'public.gpforum_italian';

# The text-search configuration every document is built with (migration
# 1057: Italian stems, accents folded). Indexer passes it to the indexing
# function and Searcher binds it into its tsquery, so the query and the
# stored vectors cannot disagree about how text was tokenised -- and because
# it arrives as a bind parameter rather than being read from the row, the
# planner can use the GIN index on search_vector. Schema-qualified: the
# functions run with search_path pg_catalog.
sub search_config ($class) {
    return $DEFAULT_LANGUAGE;
}

1;

__END__

=head1 NAME

GPForum::Service::Search::DocumentBuilder - The text-search configuration search documents are built with.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $config = GPForum::Service::Search::DocumentBuilder->search_config;

=head1 DESCRIPTION

The documents themselves are built by C<api.search_index_entity>, from the
thread or post row, in the statement that writes them (ADR 0126, ADR
0177). Only what a reader could find is built: a thread while it is not
deleted and its moderation state is C<visible> or C<locked>; a post while
it is not deleted, its state is C<visible> and its thread is searchable.
This module names the one value the indexer and the searcher must share:
the text-search configuration.

=head1 SUBROUTINES/METHODS

=head2 search_config

A class method. Returns the text-search configuration every document is
built with, C<public.gpforum_italian>: PostgreSQL's Italian configuration
with C<unaccent> before the stemmer (migration 1057).
L<GPForum::Service::Search::Indexer> passes it to the indexing function and
L<GPForum::Service::Search::Searcher> binds the same value into its query,
so the query and the stored vectors cannot disagree about how text was
tokenised, and as a bind parameter rather than a column of the row it
leaves the planner free to use the GIN index on C<search_vector>.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Const::Fast>, L<Mojo::Base>.

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
