# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::MissedCalls;

use Mojo::Base 'GPForum::Infrastructure::SqlFunction', -signatures;
use v5.40;

use Mojo::Promise;

our $VERSION = '0.001';

# The PostgreSQL call layer, whose next calls to the named functions find
# nothing: what a writer sees when it looks just before a concurrent writer
# commits the same row. Only the look is scripted. The insert that follows,
# the unique violation PostgreSQL raises and the savepoint that recovers
# from it are the database's own. The misses are shared with the blocking
# layer made from this one, which the blocking twins run on.
#
#   GPForum::Test::MissedCalls->new(
#       schema => $schema,
#       misses => { admin_lookup_role => 1 },
#   );
has misses => sub { return {}; };

sub blocking_layer ($self) {
    return $self if $self->blocking;
    return $self->{gp_missed_blocking} //= ref($self)->new(
        blocking  => 1,
        catalogue => $self->catalogue,
        misses    => $self->misses,
        schema    => $self->schema,
    );
}

sub rows ( $self, $name, $values ) {
    return [] if $self->_missed($name);
    return $self->SUPER::rows( $name, $values );
}

sub rows_p ( $self, $name, $values, $context = undef ) {
    return Mojo::Promise->resolve( [] ) if $self->_missed($name);
    return $self->SUPER::rows_p( $name, $values, $context );
}

# True once for each call to $name still to miss.
sub _missed ( $self, $name ) {
    my $due = $self->misses->{$name} // 0;
    return 0 if $due < 1;
    $self->misses->{$name} = $due - 1;

    return 1;
}

1;

__END__

=head1 NAME

GPForum::Test::MissedCalls - A call layer whose next looks lose a race.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $functions = GPForum::Test::MissedCalls->new(
        schema => $schema,
        misses => { admin_live_category_by_slug => 1 },
    );
    GPForum::Service::Admin::CategoryStore->new(
        functions => $functions,
        schema    => $schema,
    )->create_category( {...} );

=head1 DESCRIPTION

A L<GPForum::Infrastructure::SqlFunction> on a real schema whose next calls
to the functions named in C<misses> answer no rows, each as many times as
its count says; every other call, and every write, reaches PostgreSQL: a
lookup that misses the row a racing writer committed, for stores that look
rows up through functions.

=head1 SUBROUTINES/METHODS

=head2 misses

The functions still to miss, with how many times each.

=head2 blocking_layer

The blocking layer, sharing the misses.

=head2 rows

=head2 rows_p

No rows for a call still to miss; otherwise the layer's answer.

=head1 DIAGNOSTICS

None of its own.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>, L<Mojo::Promise>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A pooled transaction's layer is made afresh and does not miss: the misses
apply on the layer given and on its blocking layer.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
