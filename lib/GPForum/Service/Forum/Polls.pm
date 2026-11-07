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

sub overview ( $self, $actor, $thread_id ) {
    return _overview(
        $self->functions->row(
            'forum_poll_read', _overview_values( $actor, $thread_id )
        )
    );
}

# The poll page as the web worker reads it, on its pooled asynchronous
# connections rather than in a forked child with a connection of its own.
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

sub change ( $self, $input ) {
    return { status => 'invalid' }
      if !GPForum::Infrastructure::Id->is_uuid( $input->{command} );
    my $row = $self->functions->row( 'forum_poll_change', $input );
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

=head2 overview

Returns a permission-filtered poll, or a not-found result.

=head2 overview_p

L</overview> as a promise, with the request's optional query context last,
read on the worker's pooled asynchronous connections.

=head2 change

Creates, votes or closes, authorizing and recording the command atomically.

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
