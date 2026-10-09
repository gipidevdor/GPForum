# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::SqlFunctionCatalogue;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::X::Argument;

our $VERSION = '0.001';

# ADR 0126: the functions in schema api this release calls, by the name
# Perl asks for: the version it calls and its parameters, in order, each with
# its name (the function's own, without the p_ prefix) and its PostgreSQL
# type, and the result columns that hold a json document. A release moves to
# a function's next version by changing its line here. The core_ helpers the
# functions share are not listed: Perl never calls them.
# t/integration/postgres-sql-function-catalogue.t checks every entry against
# pg_proc on a migrated database.
const my %FUNCTION => ();

has entries => sub { return \%FUNCTION; };

sub names ($self) {
    return [ sort keys %{ $self->entries } ];
}

# The entry for a name: { name, version, function (api.NAME_vN), names,
# types, sql, json }, built once per catalogue. An unknown name is a
# caller's mistake.
sub function ( $self, $name ) {
    return $self->{built}{ $name // q{} } //=
      _built( $name, $self->entries );
}

sub _built ( $name, $entries ) {
    if ( !defined $name || !exists $entries->{$name} ) {
        GPForum::X::Argument->throw(
            message => 'unknown SQL function: ' . ( $name // q{} ) );
    }

    my $entry = $entries->{$name};
    my @pairs = @{ $entry->{parameters} };
    my ( @names, @types );
    while (@pairs) {
        push @names, shift @pairs;
        push @types, shift @pairs;
    }
    my $function = "api.${name}_v$entry->{version}";

    return {
        function => $function,
        json     => { map { $_ => 1 } @{ $entry->{json} // [] } },
        name     => $name,
        names    => \@names,
        sql      => "SELECT * FROM $function("
          . join( q{, }, map { "?::$_" } @types ) . ')',
        types   => \@types,
        version => $entry->{version},
    };
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::SqlFunctionCatalogue - The PostgreSQL functions this release calls, and their versions.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new;
    my $entry     = $catalogue->function('forum_thread_page_head');
    # $entry->{function}: api.forum_thread_page_head_v1
    # $entry->{sql}:      SELECT * FROM api.forum_thread_page_head_v1(?::uuid)

=head1 DESCRIPTION

ADR 0126 moves every statement into a function in schema C<api>, created by
a numbered migration and never changed after it ships: a change is the next
version, C<api.NAME_vN+1>. This module is the one place a release says which
version of each function it calls, with the function's parameters in order,
named and typed. L<GPForum::Infrastructure::SqlFunction> binds a call's
values by these names and casts each to its type in the statement it builds
from the entry, once per process.

=head1 SUBROUTINES/METHODS

=head2 entries

The functions listed, by name: C<version>, C<parameters> (name and type,
in order) and C<json> (the result columns that hold a json document). A
test gives its own.

=head2 names

The names of the functions listed, sorted.

=head2 function

The entry for a name: C<name>, C<version>, C<function> (the qualified
function name), C<names> and C<types> (the parameters, in order), C<sql>
(the call, C<SELECT * FROM api.NAME_vN(?::type, ...)>) and C<json> (a hash
of the result columns that hold a json document).

=head1 DIAGNOSTICS

L</function> throws L<GPForum::X::Argument> for a name that is not listed.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Const::Fast>, L<Mojo::Base>, L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
