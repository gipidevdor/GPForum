# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::StoreWrites;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use Mojo::Util qw(monkey_patch);

our $VERSION = '0.001';

# A post or thread store's write alone, without a command log: the store
# step api.forum_store_write runs under the store's locks, with the
# store's parameters, answered as the store answers (ADR 0126). The posting
# workflow writes through api.forum_write_command and
# api.forum_create_reply; a test that reaches the store's own step -- a
# race on the locks, a recovery, the counters -- calls it here.
const my %WRITE => (
    create_post    => 'post.created',
    delete_post    => 'post.deleted',
    edit_post      => 'post.updated',
    restore_post   => 'post.undeleted',
    create_thread  => 'thread.created',
    delete_thread  => 'thread.deleted',
    edit_thread    => 'thread.updated',
    move_thread    => 'thread.moved',
    restore_thread => 'thread.undeleted',
);

has store => undef;    # a PostStore or a ThreadStore on PostgreSQL

monkey_patch __PACKAGE__, map { $_ => _writer( $WRITE{$_} ) } keys %WRITE;

sub _writer ($type) {
    return sub ( $self, $command ) { return $self->stored( $type, $command ); };
}

sub stored ( $self, $event_type, $command ) {
    my $store = $self->store;
    my $row   = $store->functions->row( 'forum_store_write',
        $store->function_parameters( $event_type, $command ) );

    return $store->function_answer( $row->{stored} );
}

1;

__END__

=head1 NAME

GPForum::Test::StoreWrites - A post or thread store's write alone, through its store step.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $posts = GPForum::Test::StoreWrites->new(
        store => GPForum::Service::Forum::PostStore->new( schema => $schema ) );
    my $created = $posts->create_post( $prepared->{command} );

=head1 DESCRIPTION

Calls C<api.forum_store_write> with a store's parameters and reads the
answer back as the store does: the write the posting workflow's command
runs, without its command log.

=head1 SUBROUTINES/METHODS

=head2 store

The L<GPForum::Service::Forum::PostStore> or
L<GPForum::Service::Forum::ThreadStore>, on PostgreSQL.

=head2 stored

Takes the event type and the command; answers the store's answer.

=head2 create_post, edit_post, delete_post, restore_post, create_thread, edit_thread, move_thread, delete_thread, restore_thread

L</stored> of C<post.created>, C<post.updated>, C<post.deleted>,
C<post.undeleted>, C<thread.created>, C<thread.updated>, C<thread.moved>,
C<thread.deleted> and C<thread.undeleted>.

=head1 DIAGNOSTICS

The function's errors propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>.

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
