# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::Storage;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# A schema's DBIx::Class storage, or undef when there is none to be had: no
# schema, a test double without storage, or a storage call that died. Callers
# that only probe -- for a transaction depth, savepoint support, a database
# handle -- treat all three the same way.
sub storage_of ( $, $schema ) {
    if ( !blessed $schema || !$schema->can('storage') ) {
        return undef;
    }

    my $storage;
    try {
        $storage = $schema->storage;
    }
    catch ($error) {
        $storage = undef;
    };

    return $storage;
}

# The schema's database handle, or undef. DBIx::Class pings the handle in
# storage->dbh and reconnects when the ping fails, so this connects when it
# has to; a connection that cannot be made is undef here like any other
# missing handle.
# Runs $code with the schema's handle as it stands -- $code gets the storage
# and the handle, as DBIx::Class's dbh_do gives them -- without the ping
# dbh_of pays for: a read made on every request, like the cache bus's take,
# must not cost a round trip to ask whether the connection is alive. A
# handle that is gone fails the code, and the storage's own retry connects
# again when the code dies for that. Undef when there is no storage, or the
# code died.
sub with_handle ( $class, $schema, $code ) {
    my $storage = $class->storage_of($schema);
    if ( !blessed $storage || !$storage->can('dbh') ) {
        return undef;
    }

    # A storage without dbh_do -- a test's double -- gives its handle as it
    # has it.
    my $answer;
    try {
        $answer =
            $storage->can('dbh_do')
          ? $storage->dbh_do($code)
          : $code->( $storage, $storage->dbh );
    }
    catch ($error) {
        $answer = undef;
    };

    return $answer;
}

sub dbh_of ( $class, $schema ) {
    my $storage = $class->storage_of($schema);
    if ( !blessed $storage || !$storage->can('dbh') ) {
        return undef;
    }

    my $dbh;
    try {
        $dbh = $storage->dbh;
    }
    catch ($error) {
        $dbh = undef;
    };

    return $dbh;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::Storage - A schema's storage and database handle,
or undef.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    use GPForum::Infrastructure::Storage;

    my $dbh = GPForum::Infrastructure::Storage->dbh_of( $self->schema )
      or return undef;

    my $storage = GPForum::Infrastructure::Storage->storage_of($schema);

=head1 DESCRIPTION

Stores, workflows and commands ask their schema for its database handle to
run a statement DBIx::Class does not write, or to read a transaction depth,
and each kept its own copy of the same probe: no schema, a test double
without storage, a storage that died or a handle that could not be had all
answer undef. These two class methods are that probe, once.

They return undef rather than an empty list, so they are safe as a hash value
or an argument.

=head1 SUBROUTINES/METHODS

=head2 storage_of

Class method. C<< $schema->storage >>, or undef when the schema is not an
object, has no C<storage> method, or the call dies.

=head2 with_handle

Class method. Takes a schema and a code reference, and runs the code through
C<< $schema->storage->dbh_do >>, which gives it the storage and the handle
without pinging the connection first; a storage without C<dbh_do> (a
double) gives the code its C<dbh>. Returns what the code returned, or undef
when L</storage_of> is undef, the storage has no C<dbh>, or the code died.

=head2 dbh_of

Class method. C<< $schema->storage->dbh >>, or undef when L</storage_of> is
undef, the storage has no C<dbh> method, or the call dies. DBIx::Class
connects, or reconnects after a failed ping, inside that call.

=head1 DIAGNOSTICS

None: every failure is undef. A caller that has to report why it has no
handle calls C<< $schema->storage->dbh >> itself.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The error that made a probe undef is not kept.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
