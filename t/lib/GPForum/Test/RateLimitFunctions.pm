# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RateLimitFunctions;

use Mojo::Base 'GPForum::Test::SettledCalls', -signatures;
use v5.40;

our $VERSION = '0.001';

# api.ops_rate_limit_check and api.ops_rate_limit_snapshot over buckets in
# memory. Every store handed the same double counts in the same buckets, as
# every worker counts in the same table. Each call is recorded.
has calls   => sub { return []; };
has buckets => sub { return {}; };

sub row ( $self, $name, $values ) {
    push @{ $self->calls }, { name    => $name, values => $values };
    return                  { buckets => scalar keys %{ $self->buckets } }
      if $name eq 'ops_rate_limit_snapshot';

    my $key = join q{:}, @{$values}{qw(scope actor_hash action window_start)};
    my $bucket = $self->buckets->{$key} //= {
        actor_hash        => $values->{actor_hash},
        observed_count    => 0,
        blocked_count     => 0,
        window_started_at => $values->{window_start},
    };
    $bucket->{observed_count} += 1;
    if ( $bucket->{observed_count} > $values->{limit} ) {
        $bucket->{blocked_count} += 1;
    }

    return { %{$bucket} };
}

sub rows ( $self, $name, $values ) {
    return [ $self->row( $name, $values ) ];
}

1;

__END__

=head1 NAME

GPForum::Test::RateLimitFunctions - The rate limit functions over buckets in memory.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $functions = GPForum::Test::RateLimitFunctions->new;
    my $store =
      GPForum::Service::Operations::RateLimiter::PostgreSQLStore->new(
        schema    => 'unused',
        functions => $functions,
      );

=head1 DESCRIPTION

A call layer double for
L<GPForum::Service::Operations::RateLimiter::PostgreSQLStore>: it counts a
request in its window's bucket and answers the bucket, as
C<api.ops_rate_limit_check> does, and counts the buckets for
C<api.ops_rate_limit_snapshot>.

=head1 SUBROUTINES/METHODS

=head2 row

Answers one call, recording it in C<calls>.

=head2 rows

The same answer as a list of one row.

=head2 calls

The calls made, each a hash with C<name> and C<values>.

=head2 buckets

The buckets, by scope, actor hash, action and window start.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Test::SettledCalls>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Buckets never expire.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
