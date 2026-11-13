# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::NotifyingFunctions;

use Mojo::Base 'GPForum::Test::SettledCalls', -signatures;
use v5.40;

our $VERSION = '0.001';

# A call layer whose api.ops_publish_notification sends the NOTIFY on the
# handle it is given -- a GPForum::Test::RealtimeBusDbh, whose network
# delivers it to the backends listening on the channel -- as the function
# sends it on its connection. A handle that dies fails the call.
has dbh => undef;

sub rows ( $self, $name, $values ) {
    die "no handle to notify on\n" if !$self->dbh;
    die "$name is not answered here\n"
      if $name ne 'ops_publish_notification';

    $self->dbh->do( 'SELECT pg_notify(?, ?)',
        undef, $values->{channel}, $values->{payload} );

    return [ {} ];
}

sub row ( $self, $name, $values ) {
    return $self->rows( $name, $values )->[0];
}

1;

__END__

=head1 NAME

GPForum::Test::NotifyingFunctions - A call layer whose publish notifies on a test handle.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $peer = GPForum::Test::RealtimeBusDbh->new( pg_pid => 1 )
      ->join_network($backend);
    my $publisher = GPForum::Service::Operations::CacheInvalidationBus->new(
        functions => GPForum::Test::NotifyingFunctions->new( dbh => $peer ) );
    $publisher->publish( { tags => ['thread:1'] } );

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::SqlFunction> where a test
publishes through C<api.ops_publish_notification>: the call is the
C<pg_notify> the function makes, sent on the handle given. Its promises are
settled (L<GPForum::Test::SettledCalls>).

=head1 SUBROUTINES/METHODS

=head2 dbh

The handle the notification is sent on.

=head2 rows

Sends the notification for C<api.ops_publish_notification>; dies for any
other function, and without a handle.

=head2 row

The first of L</rows>.

=head1 DIAGNOSTICS

Dies as L</rows> says, and with whatever the handle dies with.

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
