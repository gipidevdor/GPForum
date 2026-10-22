# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::ResultRow::Thread;

use Mojo::Base 'GPForum::Infrastructure::ResultRow', -signatures;
use v5.40;

our $VERSION = '0.001';

# A thread row a function returned, with an accessor for each column of the
# threads table, as the GPForum::Schema::Result::Thread rows it replaces had: a
# caller that asks the row for ->position or ->title keeps working (ADR
# 0126). An accessor reads the column the row holds, undef when the function
# did not return it.
__PACKAGE__->attr(
    [
        qw(
          thread_id category_id author_user_id title slug pinned visibility
          moderation_state locked_at last_activity_at version visibility_version
          permission_version created_at updated_at deleted_at deleted_by
        )
    ]
);

1;

__END__

=head1 NAME

GPForum::Infrastructure::ResultRow::Thread - A thread row from a function, with the column accessors a Thread row had.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $row = GPForum::Infrastructure::ResultRow::Thread->from($hash);
    my $id  = $row->thread_id;    # as $row->get_column('thread_id')

=head1 DESCRIPTION

A L<GPForum::Infrastructure::ResultRow> with an accessor for every column
of the C<threads> table: C<thread_id>, C<category_id>, C<author_user_id>, C<title>, C<slug>, C<pinned>, C<visibility>, C<moderation_state>, C<locked_at>, C<last_activity_at>, C<version>, C<visibility_version>, C<permission_version>, C<created_at>, C<updated_at>, C<deleted_at>, C<deleted_by>.

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
