# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::ContentStore;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::Row;
use GPForum::Infrastructure::UniqueConflict;

our $VERSION = '0.001';

# What the post and the thread stores write the same way: a body or a
# revision in a savepoint, an id given up for a new one, a write through
# api.forum_store_write. Each store says what a part is with part($kind):
# its result source, its primary key's constraint, and the parts that carry
# its id.

# Inserts the command's body or revision in a savepoint. A row of the same id
# already stored for the same post is an earlier run's and is kept; an id
# taken by another post's row is given up for a new one, once. Returns the
# command as written.
sub stored_part ( $self, $command, $kind ) {
    my $part = $self->part($kind);
    my $rows = $self->schema->resultset( $part->{source} );
    my ( $created, $error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
        sub { return $rows->create( $command->{$kind} ); } );
    return $command if $created;
    if ( !GPForum::Infrastructure::UniqueConflict->conflict_of($error)
        ->on( $part->{constraint} ) )
    {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }

    my $id_column = "${kind}_id";
    my $stored = $rows->find( { $id_column => $command->{$kind}{$id_column} } );
    return $command
      if GPForum::Infrastructure::Row->belongs( $stored,
        post_id => $command->{$kind}{post_id} );

    my $retry = $self->with_new_id( $command, $kind );
    GPForum::Infrastructure::UniqueConflict->once_more( $self->schema,
        sub { return $rows->create( $retry->{$kind} ); } );

    return $retry;
}

# The command with a new id for a part, in every part that carries it.
sub with_new_id ( $self, $command, $kind ) {
    my $id_column = "${kind}_id";
    my $id        = $self->id_service->uuid;
    my %retry     = %{$command};
    for my $part ( @{ $self->part($kind)->{holders} } ) {
        $retry{$part} = { %{ $command->{$part} }, $id_column => $id };
    }

    return \%retry;
}

# A write through api.forum_store_write, with the store's parameters and
# read back as the store answers.
sub write_by_function ( $self, $event_type, $command ) {
    my $row = $self->functions->row( 'forum_store_write',
        $self->function_parameters( $event_type, $command ) );

    return $self->function_answer( $row->{stored} );
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::ContentStore - What the post and thread stores
write alike.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    package GPForum::Service::Forum::PostStore;
    use Mojo::Base 'GPForum::Service::Forum::ContentStore', -signatures;

    sub part ( $, $kind ) { return $PART{$kind}; }

=head1 DESCRIPTION

The parent of L<GPForum::Service::Forum::PostStore> and
L<GPForum::Service::Forum::ThreadStore>. A subclass gives C<schema>,
C<id_service> and C<functions>, C<function_parameters> and
C<function_answer>, and C<part>: for a kind of row (C<post>, C<body>,
C<revision>, ...) a hash reference of its C<source>, its primary key's
C<constraint>, and the C<holders>, the parts of a command that carry its id.

=head1 SUBROUTINES/METHODS

=head2 stored_part

Takes a command and a kind and inserts that part in a savepoint. A row of
the same id already stored for the same post is kept; an id another post's
row took is given up for a new one, once. Returns the command as written.

=head2 with_new_id

Takes a command and a kind and returns a copy with a new id for that kind
in every part that carries it.

=head2 write_by_function

Takes an event type and a command and writes it through
C<api.forum_store_write>, answering as C<function_answer> reads it.

=head1 DIAGNOSTICS

A conflict other than on the part's primary key, a second conflict, and
any other error are rethrown.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::Row>, L<GPForum::Infrastructure::UniqueConflict>.

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
