# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Privacy::ErasedExports;

use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::X::Unavailable;

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

our $VERSION = '0.001';

__PACKAGE__->requires(qw(schema));

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(qw(discard may_export));

# An erased member's exports are copies of the data the erasure removes: the
# profile with the e-mail, every post body. The erasure anonymized the
# account and left both copies behind, in export_requests.manifest and in the
# export answer the command log keeps for a replay. The command row stays,
# so the command id still replays and does not start a new export; only the
# bundle leaves its stored answer (api.privacy_discard_exports), on the call
# layer of the caller's transaction when one is given.
async sub discard_p ( $self, $user_id, $context = undef, $functions = undef ) {
    $functions //= $self->_functions;

    return (
        await $functions->row_p(
            'privacy_discard_exports', { user_id => $user_id }, $context
        )
    )->{document};
}

# The other side of the erasure: an export takes the member's account row
# FOR SHARE before it writes anything and keeps it until it commits. The
# erasure's anonymizing UPDATE needs that row, so it waits for a running
# export to commit -- and its delete, a later statement, then sees the
# bundle and discards it; an export that waited for an erasure reads the
# row again and finds the member erased. Without it, an export running while
# the erasure committed kept its bundle: the delete could not see rows the
# export had not committed yet. The share lock lasts until the transaction
# of the given call layer ends.
async sub may_export_p ( $self, $user_id, $context = undef, $functions = undef )
{
    $functions //= $self->_functions;

    return (
        await $functions->row_p(
            'privacy_may_export', { user_id => $user_id }, $context
        )
    )->{allowed} ? 1 : 0;
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'erased exports need the PostgreSQL database' );
}

1;

__END__

=head1 NAME

GPForum::Service::Privacy::ErasedExports - Discard an erased member's export bundles.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $discarded =
      GPForum::Service::Privacy::ErasedExports->new( schema => $schema )
      ->discard($user_id);

=head1 DESCRIPTION

A completed export stores the member's bundle -- profile with the e-mail
address, post bodies, attachment names, notifications, subscriptions and
preferences -- as the C<export_requests> row's manifest, and the export
command's answer in C<command_log> carries the same bundle for a replay.
Both are copies of the data the erasure removes.

L<GPForum::Service::Privacy::DeletionWorkflow> calls C<discard> inside the
erasure transaction, so the bundles go with the account or not at all, and
an export calls C<may_export> first, so an export that runs while the
member is erased either commits before the erasure discards it or finds the
member erased. The
evidence that they existed stays: the C<privacy.export_requested> and
C<privacy.export_completed> events and audit entries, which carry the counts
and never the data, the export command rows, and the erasure's own audit
entry, which names the requests it discarded.

=head1 SUBROUTINES/METHODS

=head2 discard_p

Takes a user id, an optional query context and an optional transaction call
layer: given one, it writes in that transaction. Deletes every C<export_requests> row whose subject is the
member, whatever its status, and removes the bundle (C<stored.manifest>)
from the answer of each C<privacy.export> command the member sent,
recomputing the row's C<response_hash>. The rest of the answer -- status,
request id, format -- is kept, so a replay of the command id answers
without the data instead of starting a new export. Returns the deleted
request ids, sorted, as an array reference. Writes in the caller's
transaction and starts none of its own.

=head2 may_export_p

Takes a user id, an optional query context and an optional transaction call
layer: given one, the share lock lasts until that transaction ends. Locks the member's C<users> row C<FOR SHARE> for the rest
of the caller's transaction and returns 1 when the member exists and is not
erased (no C<deleted_at>), 0 otherwise.
L<GPForum::Service::Privacy::Workflow> calls it before an export writes
anything: an erasure's anonymizing update of that row waits for the export
to commit, and then discards its bundle; an export that waited for an
erasure finds the member erased and writes nothing.

=head2 discard, may_export

The blocking twins of L</discard_p> and L</may_export_p> (ADR 0177): each
runs its promise method on the blocking layer, the process's own connection
and the transaction it holds, and returns its answer.

=head1 DIAGNOSTICS

Without the SQL function layer it throws L<GPForum::X::Unavailable>.
Database errors propagate and roll the caller's transaction back.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Uses L<GPForum::Base> and L<GPForum::Infrastructure::SqlFunction>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The two sides meet on the C<users> row: an export that does not go through
C<may_export> first is not ordered against the erasure, and its bundle can
survive an erasure that commits while it runs.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
