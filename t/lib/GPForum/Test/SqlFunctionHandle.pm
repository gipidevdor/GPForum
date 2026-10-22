# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::SqlFunctionHandle;

use Carp qw(croak);
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# The schema, its storage, its handle and a statement handle in one double,
# for GPForum::Infrastructure::SqlFunction: what was prepared and executed
# with which values is recorded, and the rows or the error a test gives are
# answered.
has rows        => sub { return []; };
has error       => undef;                # optional: execute dies with it
has error_state => q{};
has prepared    => sub { return []; };
has executed    => sub { return []; };
has debugobj    => undef;    # optional: the statistics a call reports to

sub storage ($self) {
    return $self;
}

sub debug ($self) {
    return $self->debugobj ? 1 : 0;
}

sub dbh_do ( $self, $code ) {
    return $code->( $self, $self );
}

sub prepare_cached ( $self, $sql, $attributes = undef ) {
    push @{ $self->prepared }, $sql;

    return $self;
}

sub execute ( $self, @values ) {
    push @{ $self->executed }, [@values];
    if ( defined $self->error ) {
        $self->{state} = $self->error_state;
        croak $self->error;
    }
    $self->{state} = q{};

    return 1;
}

sub fetchall_arrayref ( $self, $slice ) {
    return [ map { _copy($_) } @{ $self->rows } ];
}

sub _copy ($row) {
    return { %{$row} };
}

## no critic (Subroutines::ProhibitBuiltinHomonyms)
# The name is DBI's: the layer asks a statement handle for its SQLSTATE.
sub state ($self) {
    return $self->{state} // q{};
}
## use critic

1;

__END__

=head1 NAME

GPForum::Test::SqlFunctionHandle - A schema, storage and DBI handle double for the SQL function layer.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $handle = GPForum::Test::SqlFunctionHandle->new( rows => [ {...} ] );
    my $layer  = GPForum::Infrastructure::SqlFunction->new( schema => $handle );

=head1 DESCRIPTION

Answers what L<GPForum::Infrastructure::SqlFunction> asks of a DBIx::Class
schema, its storage and its DBI handles, and records the statements
prepared and the values each was executed with.

=head1 SUBROUTINES/METHODS

=head2 storage

=head2 debug

=head2 dbh_do

=head2 prepare_cached

=head2 execute

=head2 fetchall_arrayref

=head2 state

The schema's, the storage's and DBI's methods of those names.

=head1 DIAGNOSTICS

C<execute> dies with C<error> when a test gives one.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>.

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
