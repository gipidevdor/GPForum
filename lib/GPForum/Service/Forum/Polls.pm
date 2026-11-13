# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::Polls;

use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Id;

our $VERSION = '0.001';

__PACKAGE__->requires('schema');
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(qw(overview change));

# The poll of a thread as the actor may see it.
async sub overview_p ( $self, $actor, $thread_id, $context = undef ) {
    return _overview(
        await $self->functions->row_p(
            'forum_poll_read', _overview_values( $actor, $thread_id ),
            $context
        )
    );
}

sub _overview_values ( $actor, $thread_id ) {
    return { actor => $actor, thread_id => $thread_id };
}

sub _overview ($row) {
    return $row ? $row->{result} : { status => 'not_found' };
}

# Creates, votes or closes a poll; a command that is not a uuid is invalid.
async sub change_p ( $self, $input, $context = undef ) {
    return { status => 'invalid' }
      if !GPForum::Infrastructure::Id->is_uuid( $input->{command} );
    return _changed(
        await $self->functions->row_p( 'forum_poll_change', $input, $context )
    );
}

sub _changed ($row) {
    return $row ? $row->{result} : { status => 'invalid' };
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::Polls - Bounded single- and multiple-choice thread polls.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $polls->overview($member_id, $thread_id);

=head1 DESCRIPTION

One poll per thread, two to ten immutable options and one to ten choices per
ballot, chosen at creation. Active members can change their ballot until
closure; results expose totals and only the viewer's own selections.

=head1 SUBROUTINES/METHODS

=head2 overview_p

Answers a permission-filtered poll, or a not-found result. A promise, with
the request's optional query context last.

=head2 change_p

Creates, votes or closes, authorizing and recording the command atomically.

=head2 overview, change

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise.

=head1 DIAGNOSTICS

Returns status; database failures propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>.

=head1 INCOMPATIBILITIES

Requires migration 1060.

=head1 BUGS AND LIMITATIONS

Polls expire after thirty days and can close earlier. Results count selections,
so totals across options may exceed the number of voters.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
