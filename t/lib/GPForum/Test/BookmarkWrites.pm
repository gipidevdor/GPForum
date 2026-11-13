# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::BookmarkWrites;

use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::X::Conflict;

our $VERSION = '0.001';

# A bookmark's write alone, without a command log: the store steps
# api.community_save_bookmark and api.community_stamp_bookmark, with the row
# the store draws (ADR 0126). Members bookmark through
# api.community_bookmark_command (Community::Workflow); a test that reaches
# the store step -- a restore, a race on the target, a removal -- calls it
# here.
has store => undef;    # a Community::BookmarkStore on PostgreSQL

# The member's bookmark on the target, restored when there was one.
sub save_bookmark ( $self, $input ) {
    return $self->_saved( $input, 1 );
}

# A new bookmark, with no look for an existing one.
sub create_bookmark ( $self, $input ) {
    return $self->_saved( $input, 0 );
}

# The member's bookmark on the target, soft-deleted.
sub remove_for_user_target ( $self, $input ) {
    my $store = $self->store;
    return $store->functions->row(
        'community_stamp_bookmark',
        {
            user_id     => $input->{user_id},
            target_type => $input->{target_type},
            target_id   => $input->{target_id},
            column      => 'deleted_at',
            stamped_at  => $store->clock->now_iso8601,
        }
    )->{result};
}

# A minted id another bookmark holds is minted once more.
sub _saved ( $self, $input, $restore ) {
    my $store  = $self->store;
    my $row    = $store->new_bookmark_row($input);
    my $result = $self->_save( $row, $restore );
    return $result if !$result->{retry_id};

    $row->{bookmark_id} = $store->id_service->uuid;
    $result = $self->_save( $row, $restore );
    if ( $result->{retry_id} ) {
        GPForum::X::Conflict->throw(
            message => 'the replacement id is already stored' );
    }

    return $result;
}

sub _save ( $self, $row, $restore ) {
    return $self->store->functions->row( 'community_save_bookmark',
        { row => $row, restore => $restore } )->{result};
}

1;

__END__

=head1 NAME

GPForum::Test::BookmarkWrites - A bookmark's write alone, through its store steps.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $bookmarks = GPForum::Test::BookmarkWrites->new(
        store => GPForum::Service::Community::BookmarkStore->new(
            schema => $schema ) );
    my $saved = $bookmarks->save_bookmark(
        { user_id => $user, target_type => 'thread', target_id => $thread } );

=head1 DESCRIPTION

Calls C<api.community_save_bookmark> and C<api.community_stamp_bookmark>
with a L<GPForum::Service::Community::BookmarkStore>'s row and clock: the
writes the bookmark commands run, without their command log.

=head1 SUBROUTINES/METHODS

=head2 store

The bookmark store, on PostgreSQL.

=head2 save_bookmark

Saves the member's bookmark on the target, restoring the one there was;
answers the step's result.

=head2 create_bookmark

Inserts a new bookmark without restoring one.

=head2 remove_for_user_target

Soft-deletes the member's bookmark on the target.

=head1 DIAGNOSTICS

A replacement id that collides too throws L<GPForum::X::Conflict>; the
function's errors propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>, L<GPForum::X::Conflict>.

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
