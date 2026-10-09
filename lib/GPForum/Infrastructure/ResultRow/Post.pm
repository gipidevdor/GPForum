# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::ResultRow::Post;

use Mojo::Base 'GPForum::Infrastructure::ResultRow', -signatures;
use v5.40;

our $VERSION = '0.001';

# A post row a function returned, with an accessor for each column of the
# posts table, as the GPForum::Schema::Result::Post rows it replaces had: a
# caller that asks the row for ->position or ->title keeps working (ADR
# 0126). An accessor reads the column the row holds, undef when the function
# did not return it.
__PACKAGE__->attr(
    [
        qw(
          post_id thread_id author_user_id current_body_id current_revision_id
          position visibility moderation_state version visibility_version
          permission_version created_at updated_at hidden_at locked_at deleted_at
          deleted_by
        )
    ]
);

1;

__END__

=head1 NAME

GPForum::Infrastructure::ResultRow::Post - A post row from a function, with the column accessors a Post row had.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $row = GPForum::Infrastructure::ResultRow::Post->from($hash);
    my $id  = $row->post_id;    # as $row->get_column('post_id')

=head1 DESCRIPTION

A L<GPForum::Infrastructure::ResultRow> with an accessor for every column
of the C<posts> table: C<post_id>, C<thread_id>, C<author_user_id>, C<current_body_id>, C<current_revision_id>, C<position>, C<visibility>, C<moderation_state>, C<version>, C<visibility_version>, C<permission_version>, C<created_at>, C<updated_at>, C<hidden_at>, C<locked_at>, C<deleted_at>, C<deleted_by>.

=head1 SUBROUTINES/METHODS

The accessors, one per column, each the value of that column.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::ResultRow>, L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

An accessor given a value sets it in the row only: nothing is written.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
