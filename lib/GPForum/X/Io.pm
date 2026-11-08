# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::X::Io;

use Mojo::Base 'GPForum::X', -signatures;
use v5.40;

our $VERSION = '0.001';

has failure_type => 'transient';

1;

__END__

=head1 NAME

GPForum::X::Io - A local file or directory operation failed.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    open my $fh, '>', $file
      or GPForum::X::Io->throw( message => 'cannot write signing key' );

=head1 DESCRIPTION

A local read, write, sync, rename, link or lock failed: a full disk, a
vanished directory, a lock that cannot be taken. The same call may succeed a
moment later, so the failure type is C<transient> and the outbox retries it.

A file that is present but unsafe (wrong mode, a symlink, a missing key) is
not this class: that is a L<GPForum::X::Config> problem, permanent, which an
operator must fix. A dependency that did not answer over the network is a
L<GPForum::X::Unavailable>.

It is a L<GPForum::X>: it stringifies to its message and is always true.

=head1 SUBROUTINES/METHODS

None beyond L<GPForum::X>'s. C<failure_type> is C<transient>.

=head1 DIAGNOSTICS

None of its own.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::X>.

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
