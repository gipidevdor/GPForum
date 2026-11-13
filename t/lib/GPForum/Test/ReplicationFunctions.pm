# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::ReplicationFunctions;

use Mojo::Base 'GPForum::Test::SettledCalls', -signatures;
use v5.40;

our $VERSION = '0.001';

# The replication functions' answers, as GPForum::Test::ReplicationDbh gives
# the catalog's: every value a string, booleans as 1 and 0.
has in_recovery      => 0;
has standbys         => sub { return []; };
has slots            => sub { return []; };
has standby_position => sub { return {}; };

# The error every call dies with, when set: a database that cannot answer.
has failure => undef;

sub rows ( $self, $name, $values ) {
    die $self->failure . "\n" if defined $self->failure;

    return [ { in_recovery => $self->in_recovery ? 1 : 0 } ]
      if $name eq 'ops_replication_recovery';
    return [ $self->standby_position ] if $name eq 'ops_replication_position';
    return $self->standbys             if $name eq 'ops_replication_standbys';
    return $self->slots                if $name eq 'ops_replication_slots';

    return [];
}

sub row ( $self, $name, $values ) {
    return $self->rows( $name, $values )->[0];
}

1;

__END__

=head1 NAME

GPForum::Test::ReplicationFunctions - A call layer answering the replication functions.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $functions = GPForum::Test::ReplicationFunctions->new(
        standbys => [ { application_name => 'standby', ... } ],
        slots    => [ { slot_name => 'standby', active => 1, ... } ],
    );
    my $metrics = GPForum::Service::Operations::MetricsSnapshot->new(
        functions => $functions )->collect;

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::SqlFunction> where a test reads
the replication snapshot through C<api.ops_replication_recovery>,
C<api.ops_replication_position>, C<api.ops_replication_standbys> and
C<api.ops_replication_slots>, with what the test gives. Its promises are
settled (L<GPForum::Test::SettledCalls>).

=head1 SUBROUTINES/METHODS

=head2 in_recovery

True for a standby.

=head2 standbys

The standbys' rows.

=head2 slots

The slots' rows.

=head2 standby_position

A standby's replay position row.

=head2 failure

The error every call dies with, when set.

=head2 rows

The function's rows; none for a function it does not answer.

=head2 row

The first of L</rows>.

=head1 DIAGNOSTICS

Dies with C<failure> when it is set.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Test::SettledCalls>.

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
