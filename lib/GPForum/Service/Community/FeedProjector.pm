# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::FeedProjector;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $DEFAULT_RANK               => 0;
const my $DEFAULT_VISIBILITY_VERSION => 1;
const my $DEFAULT_PERMISSION_VERSION => 1;

__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(project_item remove_item remove_thread));

# Every recipient in one statement: the ids travel as one array, whatever
# their number, and PostgreSQL inserts or refreshes each row in place,
# rather than two statements per subscriber of a popular thread in one ever
# longer transaction (8.7). Rows that already hold this item unchanged are
# left alone.
async sub project_item_p ( $self, $input, $context = undef ) {
    my %seen;
    my @users = grep { defined && !$seen{$_}++ } @{ $input->{user_ids} || [] };
    return { ok => 1, projected => 0, written => 0 } if !@users;

    my $row = await $self->_functions->row_p(
        'community_project_feed',
        {
            user_ids => \@users,
            row      => {
                item_type          => $input->{item_type},
                item_id            => $input->{item_id},
                created_at         => $input->{created_at},
                rank_score         => $input->{rank_score} || $DEFAULT_RANK,
                visibility_version => $input->{visibility_version}
                  || $DEFAULT_VISIBILITY_VERSION,
                permission_version => $input->{permission_version}
                  || $DEFAULT_PERMISSION_VERSION,
            }
        },
        $context
    );
    return $row->{result};
}

# The item out of every feed.
async sub remove_item_p ( $self, $input, $context = undef ) {
    return { ok => 1, removed => 0 }
      if !defined $input->{item_type} || !defined $input->{item_id};

    my $row =
      await $self->_functions->row_p( 'community_remove_feed',
        { item_type => $input->{item_type}, item_id => $input->{item_id} },
        $context );
    return $row->{result};
}

# The thread row and every post row leave the feed together, otherwise a
# partial sweep keeps deleted posts visible in somebody's feed.
async sub remove_thread_p ( $self, $thread_id, $context = undef ) {
    my $row = await $self->_functions->row_p( 'community_remove_thread_feed',
        { thread_id => $thread_id }, $context );
    return $row->{result};
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'the feed needs the PostgreSQL function layer' );
}

1;

__END__

=head1 NAME

GPForum::Service::Community::FeedProjector - Write and remove items in members' personal feeds.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $projector =
      GPForum::Service::Community::FeedProjector->new( schema => $schema );

    $projector->project_item(
        {
            created_at => $created_at,
            item_id    => $post_id,
            item_type  => 'post',
            user_ids   => \@subscriber_ids,
        }
    );
    $projector->remove_item( { item_id => $post_id, item_type => 'post' } );
    $projector->remove_thread($thread_id);

=head1 DESCRIPTION

Maintains C<user_feed_items>, the per-member feed that
L<GPForum::Worker::Handler::FeedProjection> fills from domain events.

Each operation is one call of schema C<api> (ADR 0126), written once as
its promise method (ADR 0177). Projecting an item writes it for every
recipient in one statement: the ids travel as one array, whatever their number, and each row
is inserted or refreshed in place, rows that already hold the item
unchanged being left alone. It used to read and write each recipient in
turn, two statements per subscriber of a popular thread in one ever longer
transaction.

Removing a thread takes the thread item and the items of all its posts out
of every feed together, the posts in one statement by the
C<(item_type, item_id)> index, so a partial sweep cannot leave deleted posts
in somebody's feed.

=head1 SUBROUTINES/METHODS

=head2 project_item_p

Takes a hash reference with C<item_type>, C<item_id>, C<created_at>,
C<user_ids> (an array reference; duplicates and undef are dropped), and
optional C<rank_score> (default 0), C<visibility_version> and
C<permission_version> (default 1). In one statement, answers
C<< { ok => 1, projected, written } >>: the number of distinct recipients,
and of rows actually inserted or changed; both 0 without recipients.

=head2 remove_item_p

Takes a hash reference with C<item_type> and C<item_id>. Deletes that item
from every feed. Answers C<< { ok => 1, removed } >> with
the rows deleted, 0 when either key is missing.

=head2 remove_thread_p

Takes a thread id. Deletes the thread's item and its posts' items from
every feed, together. Answers C<< { ok => 1, removed, posts_removed } >>,
C<removed> counting both.

=head2 project_item, remove_item, remove_thread

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise. Every C<_p> method
takes an optional query context last.

=head1 DIAGNOSTICS

None of its own; database errors propagate. Without the PostgreSQL
function layer every call raises L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Base>, L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::X::Unavailable>, L<Const::Fast>.

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
