# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::CommandLogFunctions;

use JSON::MaybeXS;
use Mojo::Base 'GPForum::Test::SettledCalls', -signatures;
use v5.40;

use Mojo::Promise;

use GPForum::Infrastructure::SqlFunction;
use GPForum::X::Conflict;

our $VERSION = '0.001';

my $JSON = JSON::MaybeXS->new( canonical => 1, utf8 => 1 );

# The command log's three functions -- api.ops_command_lookup,
# api.ops_command_insert and api.ops_command_finish -- over rows kept in
# memory, each written and read as the jsonb document the functions take
# and give. A transaction that fails takes back what it wrote, as
# PostgreSQL rolls it back: a failed command leaves no row.
has commands => sub { return {}; };

# How many lookups by key still miss, as a request's lookup misses the row
# a concurrent request commits right after it: its insert then conflicts.
has misses => 0;

sub rows ( $self, $name, $values ) {
    my $commands = $self->commands;
    if ( $name eq 'ops_command_lookup' ) {
        if ( defined $values->{key} && $self->misses ) {
            $self->misses( $self->misses - 1 );
            return [];
        }
        my $found =
          defined $values->{key}
          ? $self->_keyed( $values->{key} )
          : $commands->{ $values->{command_id} // q{} };
        return $found ? [ { document => _copy($found) } ] : [];
    }
    if ( $name eq 'ops_command_insert' ) {
        my $row = _copy( $values->{command} );
        for my $constraint (
            [ command_log_pkey => $commands->{ $row->{command_id} } ],
            [
                command_log_idempotency_key_key =>
                  $self->_keyed( $row->{idempotency_key} )
            ],
          )
        {
            next if !$constraint->[1];
            GPForum::X::Conflict->throw(
                message    => $constraint->[0],
                constraint => $constraint->[0]
            );
        }
        $commands->{ $row->{command_id} } = $row;
        return [ { document => _copy($row) } ];
    }
    if ( $name eq 'ops_command_finish' ) {
        my $row = $commands->{ $values->{command_id} }
          // die "command $values->{command_id} is not in the log\n";
        $commands->{ $values->{command_id} } =
          { %{$row}, %{ _copy( $values->{changes} ) } };
        return [];
    }

    die "$name is not answered here\n";
}

sub row ( $self, $name, $values ) {
    return $self->rows( $name, $values )->[0];
}

# The work on this layer, its writes taken back when it fails. The work
# answers a settled promise, as every call here does.
sub transaction_p ( $self, $work, $context = undef, $readonly = 0 ) {
    my %before = %{ $self->commands };
    my ( $answer, $failure );
    try {
        $answer =
          GPForum::Infrastructure::SqlFunction->settled( $work->($self) );
    }
    catch ($error) { $failure = $error; };
    if ( defined $failure ) {
        $self->commands( \%before );
        return Mojo::Promise->reject($failure);
    }

    return Mojo::Promise->resolve($answer);
}

# The row kept under an idempotency key, or undef.
sub _keyed ( $self, $key ) {
    for my $row ( values %{ $self->commands } ) {
        return $row if $row->{idempotency_key} eq $key;
    }

    return undef;
}

sub _copy ($document) {
    return $JSON->decode( $JSON->encode($document) );
}

1;

__END__

=head1 NAME

GPForum::Test::CommandLogFunctions - The command log's functions over rows kept in memory.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $log = GPForum::Service::Operations::CommandIdempotency->new(
        functions => GPForum::Test::CommandLogFunctions->new,
        schema    => GPForum::Test::Schema->new,
    );

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::SqlFunction> where a test runs the
real L<GPForum::Service::Operations::CommandIdempotency> on its call layer:
C<api.ops_command_lookup> finds a row by idempotency key or command id,
C<api.ops_command_insert> keeps one (a second under the same command id
or the same key is a L<GPForum::X::Conflict>), and C<api.ops_command_finish> records its
response. Its promises are settled (L<GPForum::Test::SettledCalls>).

=head1 SUBROUTINES/METHODS

=head2 commands

The rows kept, by command id.

=head2 misses

How many lookups by key still find nothing, whatever is kept: a request
racing one that commits the same key right after its lookup.

=head2 rows

The function's rows; dies for a function it does not answer.

=head2 row

The first of L</rows>.

=head2 transaction_p

Runs the work on the double; when it fails, the rows are put back as they
were before it and the failure is answered as a settled rejection.

=head1 DIAGNOSTICS

Dies for a function it does not answer, and for a finish of a command not
in the log.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Test::SettledCalls>, L<JSON::MaybeXS>.

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
