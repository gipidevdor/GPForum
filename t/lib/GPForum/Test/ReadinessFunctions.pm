# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::ReadinessFunctions;

use Const::Fast;
use Mojo::Base 'GPForum::Test::AnsweringFunctions', -signatures;
use v5.40;

use GPForum::Service::Operations::PartitionLifecycle;
use GPForum::Service::Operations::QueryBudget;
use GPForum::Test::ReplicationFunctions;

our $VERSION = '0.001';

const my $SECONDS_PER_DAY => 86_400;
const my $HORIZON_DAYS    => 365;

# The functions readiness reads, answering a healthy node unless a test
# says otherwise: every table probe answers, the stored query budgets are
# the catalog's, every partitioned table has a year of partitions ahead, and
# the replication functions answer what the replication double is given (a
# primary with no standby and no slot by default). A test's own answers take
# the place of these.
has replication => sub { return GPForum::Test::ReplicationFunctions->new; };

# The error every call dies with, when set: a database that cannot answer.
has failure => undef;

sub new ( $class, @arguments ) {
    my $self = $class->SUPER::new(@arguments);
    $self->answers( { %{ _healthy() }, %{ $self->answers } } );

    return $self;
}

sub rows ( $self, $name, $values ) {
    die $self->failure . "\n" if defined $self->failure;
    if ( $name =~ /\A ops_replication_ /msx ) {
        push @{ $self->calls }, [ $name, $values ];
        return $self->replication->rows( $name, $values );
    }

    return $self->SUPER::rows( $name, $values );
}

sub _healthy {
    my $catalog = GPForum::Service::Operations::QueryBudget->new->catalog;
    return {
        ops_readiness_probe   => [ { probed => 1 } ],
        ops_query_budget_list => [
            map {
                {
                    endpoint_name    => $_,
                    max_queries      => $catalog->{$_}{max_queries},
                    max_transactions => $catalog->{$_}{max_transactions},
                    notes            => $catalog->{$_}{notes},
                }
            } sort keys %{$catalog}
        ],
        ops_partition_horizon => sub ($values) {
            my $horizon = time + $HORIZON_DAYS * $SECONDS_PER_DAY;
            return [
                map {
                    {
                        table_name       => $_,
                        horizon_epoch    => $horizon,
                        default_has_rows => 0,
                    }
                  } @{ GPForum::Service::Operations::PartitionLifecycle
                      ->partitioned_tables
                  }
            ];
        },
    };
}

1;

__END__

=head1 NAME

GPForum::Test::ReadinessFunctions - A call layer answering the functions readiness reads.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $report = GPForum::Service::Operations::Readiness->new(
        functions => GPForum::Test::ReadinessFunctions->new,
        runtime   => $runtime,
        schema    => GPForum::Test::ReadinessSchema->new,
    )->check;

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::SqlFunction> where a test builds
a readiness report: C<api.ops_readiness_probe>,
C<api.ops_query_budget_list>, C<api.ops_partition_horizon> and the
replication functions answer a healthy node, and each call is recorded
(L<GPForum::Test::AnsweringFunctions>).

=head1 SUBROUTINES/METHODS

=head2 new

Takes C<answers> to put in place of the healthy ones, and C<replication>,
a L<GPForum::Test::ReplicationFunctions> answering the replication
functions.

=head2 replication

The double the replication functions are answered by.

=head2 failure

The error every call dies with, when set.

=head2 rows

Records the call and answers its rows.

=head1 DIAGNOSTICS

Dies with C<failure> when it is set.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Test::AnsweringFunctions>,
L<GPForum::Test::ReplicationFunctions>.

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
