# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::SourceFunction;

use Mojo::Base -base, -signatures;
use v5.40;
use GPForum::Infrastructure::ResultRow;

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

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
