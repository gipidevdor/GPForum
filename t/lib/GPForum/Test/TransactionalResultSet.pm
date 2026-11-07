# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::TransactionalResultSet;

use Mojo::Base 'GPForum::Base';
use v5.40;

our $VERSION = '0.001';

# What the result-set doubles share with a real transaction: a statement in
# an aborted one fails, and a unique violation aborts it. Each double kept
# its own copy of these; a subclass gives schema, and the doubles that check
# unique constraints check_unique_constraints($row).

sub assert_usable {
    my ($self) = @_;
    my $schema = $self->schema;
    if ( $schema && $schema->can('assert_transaction_usable') ) {
        $schema->assert_transaction_usable;
    }

    return;
}

sub mark_aborted {
    my ($self) = @_;
    my $schema = $self->schema;
    if ( $schema && $schema->can('mark_transaction_aborted') ) {
        $schema->mark_transaction_aborted;
    }

    return;
}

# A unique violation is what puts a real transaction into the aborted state.
# Marking it here is what makes the doubles able to fail a recovery path that
# would be unreachable against PostgreSQL. The violation goes on unchanged,
# for the caller to classify.
sub assert_unique_constraints {
    my ( $self, $row ) = @_;

    try { $self->check_unique_constraints($row); }
    catch ($failure) {
        $self->mark_aborted;
        die $failure;    ## no critic (ErrorHandling::RequireCarping) -- the violation goes on as it was raised
    };

    return;
}

1;

__END__

=head1 NAME

GPForum::Test::TransactionalResultSet - What the result-set doubles share
with a transaction.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    package GPForum::Test::AttachmentResultSet;
    use Mojo::Base 'GPForum::Test::TransactionalResultSet';

    sub create {
        my ( $self, $row ) = @_;
        $self->assert_usable;
        $self->assert_unique_constraints($row);
        ...
    }

=head1 DESCRIPTION

The parent of the domain result-set doubles and L<GPForum::Test::ResultSet>.
A subclass gives C<schema>, a test schema that may keep a transaction state,
and, when it checks unique constraints, C<check_unique_constraints>, which
throws the violation.

=head1 SUBROUTINES/METHODS

=head2 assert_usable

Fails as PostgreSQL does when the schema's transaction is aborted.

=head2 mark_aborted

Marks the schema's transaction aborted.

=head2 assert_unique_constraints

Takes a row and runs C<check_unique_constraints> on it; a violation marks
the transaction aborted and goes on unchanged.

=head1 DIAGNOSTICS

The violation C<check_unique_constraints> throws.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

For tests only. A schema without a transaction state is left alone.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
