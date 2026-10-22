# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::ResultRow::NotificationInbox;

use Mojo::Base 'GPForum::Infrastructure::ResultRow', -signatures;
use v5.40;

use GPForum::Infrastructure::ResultRow::Notification;

our $VERSION = '0.001';

sub from ( $class, $row, $filtered = 1 ) {
    return undef if ref $row ne 'HASH';
    my %notification =
      map { $_ => $row->{$_} } qw(recipient_user_id notification_id created_at);
    for my $column (qw(source_type source_id notification_type payload)) {
        $notification{$column} = delete $row->{$column};
    }
    $row->{notification} =
      GPForum::Infrastructure::ResultRow::Notification->from( \%notification );
    if ( !$filtered ) {
        delete @{$row}{qw(source_thread_id source_thread_title)};
    }

    return $class->SUPER::from($row);
}

sub notification ($self) {
    return $self->{notification};
}

sub get_columns ($self) {
    return
      map { $_ => $self->{$_} } grep { $_ ne 'notification' } keys %{$self};
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::ResultRow::NotificationInbox - A plain inbox row with its prefetched notification.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $row = GPForum::Infrastructure::ResultRow::NotificationInbox->from($values);
    my $payload = $row->notification->get_column('payload');

=head1 DESCRIPTION

Adapts the columns of a notification API call to the existing inbox readers
without DBIx row inflation or an additional relationship query. Unfiltered
lists omit source titles, as their old resultsets did.

=head1 SUBROUTINES/METHODS

=head2 from

Builds an inbox row and its notification from one fetched hash. Takes whether
the query filtered source permissions, defaulting to true.

=head2 notification

Returns the notification row already fetched by the same function call.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::ResultRow>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The input hash is consumed in place.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
