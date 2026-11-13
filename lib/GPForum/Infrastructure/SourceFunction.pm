# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::SourceFunction;

use Mojo::Base -base, -async_await;
use v5.40;
use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::Row qw(rows_in);

our $VERSION = '0.001';

# A resolved viewer is shared by every source in a page. PostgreSQL applies
# the same visibility predicates before LIMIT; a row never asks for a query.
sub parameters ( $class, $readability, $user_id, $viewer = undef ) {
    if ( !$readability ) {
        $viewer = undef;
    }
    if ( $readability && !ref $viewer ) {
        $viewer = $readability->viewer_resolver->resolve( $viewer // $user_id );
    }
    return {
        user_id        => $user_id,
        filter_sources => $readability ? 1                     : 0,
        member         => $viewer      ? $viewer->member       : 0,
        global_read    => $viewer      ? $viewer->global_read  : 0,
        viewer_user_id => $viewer      ? $viewer->user_id      : undef,
        category_ids   => $viewer      ? $viewer->category_ids : [],
        space_ids      => $viewer      ? $viewer->space_ids    : [],
    };
}

sub rows ( $class, $rows, $filtered ) {
    if ( !$filtered ) {
        for my $row ( @{$rows} ) {
            delete @{$row}{qw(source_thread_id source_thread_title)};
        }
    }
    return [ map { GPForum::Infrastructure::ResultRow->from($_) } @{$rows} ];
}

# A source list read through its function: the call the store builds, its
# rows filtered as rows does. The bookmark, feed and mention readers each
# kept this copy.
sub list ( $class, $functions, $call, $filtered ) {
    my ( $name, $values ) = @{$call};

    return $class->rows( $functions->rows( $name, $values ), $filtered );
}

# The values every source list function takes: the viewer's parameters, the
# keyset position after which the page starts and the row limit.
sub page_values ( $class, $readability, $user_id, $options, $default_limit ) {
    my $after = $options->{after} || {};
    return {
        %{ $class->parameters( $readability, $user_id, $options->{viewer} ) },
        after_created_at => $after->{sort_value},
        after_id         => $after->{id},
        row_limit        => $options->{limit} || $default_limit,
    };
}

# The resultset condition keeping only sources the viewer can still read
# (ADR 0102); empty without readability.
sub readable_condition ( $class, $readability, $user_id, $viewer, $type_column,
    $id_column )
{
    return {} if !$readability;
    return {
        -and => [
            $readability->sources_condition(
                $viewer // $user_id,
                $type_column, $id_column
            )
        ]
    };
}

# A source list page read on the blocking connection: through the reader's
# function when it has SQL functions, through its resultset otherwise.
sub page ( $class, $reader, $user_id, $options, $columns, $resultset ) {
    my $page =
      $reader->page_window->plan( { %{$options}, sort => 'timestamp' } );
    my %window = (
        %{ $options || {} },
        limit => $page->{fetch_rows},
        after => $page->{after},
    );
    my $rows =
      $reader->functions
      ? $class->list(
        $reader->functions,
        $reader->source_list_call( $user_id, \%window ),
        $reader->readability ? 1 : 0
      )
      : [ rows_in( $reader->$resultset( $user_id, \%window ) ) ];
    return $reader->page_window->page( $rows, $page->{limit}, $columns );
}

# The viewer parameters would resolve, read on a pooled asynchronous connection.
async sub viewer_p ( $class, $readability, $user_id, $viewer, $context ) {
    return $viewer if !$readability || ref $viewer;
    return (
        await $readability->viewer_resolver->resolve_p(
            $viewer // $user_id, $context
        )
    );
}

# A source list page as the web worker reads it: the viewer resolved and
# the list read on the worker's pooled asynchronous connections. Through
# call_p's fallback each page forked a child that opened a connection of
# its own, one child at a time per worker. The reader gives page_window,
# functions, readability and source_list_call, as the three readers do;
# without SQL functions the blocking page through its resultset answers.
async sub page_p ( $class, $reader, $user_id, $options, $columns, $resultset,
    $context = undef )
{
    return $class->page( $reader, $user_id, $options, $columns, $resultset )
      if !$reader->functions;
    my $readability = $reader->readability;
    my $page =
      $reader->page_window->plan( { %{$options}, sort => 'timestamp' } );
    my $viewer =
      await $class->viewer_p( $readability, $user_id, $options->{viewer},
        $context );
    my ( $name, $values ) = @{
        $reader->source_list_call(
            $user_id,
            {
                %{$options},
                after  => $page->{after},
                limit  => $page->{fetch_rows},
                viewer => $viewer,
            }
        )
    };
    my $rows = await $reader->functions->rows_p( $name, $values, $context );
    return $reader->page_window->page(
        $class->rows( $rows, $readability ? 1 : 0 ),
        $page->{limit}, $columns );
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::SourceFunction - Shared viewer parameters and rows for source lists.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $values = GPForum::Infrastructure::SourceFunction->parameters(
        $readability, $user_id, $viewer);
    my $rows = GPForum::Infrastructure::SourceFunction->rows($hashes, 1);

=head1 DESCRIPTION

Resolves one viewer for a PostgreSQL source list. The function filters each
source before applying the page limit. Its rows retain source thread columns
only when the caller requested the readability filter.

=head1 SUBROUTINES/METHODS

=head2 parameters

Takes the readability service, member id and optional resolved viewer or reader
id. Returns bound visibility arguments for a community source list.

=head2 rows

Takes an array of returned column hashes and whether source filtering was
requested. Returns generic result rows with the originally selected columns.

=head2 list

Takes the function layer, a C<[ name, values ]> call and whether the rows
are filtered, and returns the call's rows as L</rows> gives them.

=head2 page_values

Takes the readability service, member id, the page options (C<after> as a
decoded C<< { sort_value, id } >>, C<limit>, C<viewer>) and the default
limit. Returns L</parameters> with C<after_created_at>, C<after_id> and
C<row_limit> added: the values every source list function takes.

=head2 readable_condition

Takes the readability service, member id, optional viewer and the source
type and id columns. Returns the resultset condition keeping only sources
the viewer can still read, or an empty hash without readability.

=head2 page

Takes a source list reader, the member id, the page options, the cursor
columns and the name of the reader's resultset method. Returns the page
read on the blocking connection: through C<source_list_call> when the
reader has SQL functions, through the resultset otherwise.

=head2 page_p

Takes a source list reader (its C<page_window>, C<functions>,
C<readability> and C<source_list_call>), the member id, the page options
(C<after> cursor string, C<limit>, C<viewer>), the cursor columns, the name
of its resultset method and the request's query context. Returns a promise
of the page L</list> and the reader's page window give, read on the
worker's pooled asynchronous connections, the viewer resolved there too
when it is not given. Without SQL functions it answers L</page>.

=head2 viewer_p

Takes the readability service, member id, optional resolved viewer or
reader id and query context. Returns a promise of the viewer L</parameters>
would resolve, read on a pooled asynchronous connection; a resolved viewer,
or no readability, is answered as given.

=head1 DIAGNOSTICS

Viewer resolution and database errors propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::ResultRow>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause license.

=cut
