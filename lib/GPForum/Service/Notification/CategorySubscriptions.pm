# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::CategorySubscriptions;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Id;

our $VERSION = '0.001';

__PACKAGE__->requires('schema');
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

sub change ( $self, $input ) {
    return { status => 'invalid' }
      if !GPForum::Infrastructure::Id->is_uuid( $input->{command} );
    my $row = $self->functions->row( 'notification_category_follow', $input );
    return $row ? $row->{result} : { status => 'invalid' };
}

1;

__END__

=head1 NAME

GPForum::Service::Notification::CategorySubscriptions - Follow a category through the function API.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $service->change({actor => $member, command => $id, category_id => $category, operation => 'follow'});

=head1 DESCRIPTION

Reuses subscriptions, recipient permissions, preferences and digest delivery.
The database authorizes the target and records each command atomically.

=head1 SUBROUTINES/METHODS

=head2 change

Follow, mute or remove an active member's category subscription.

=head1 DIAGNOSTICS

Returns a status; database failures propagate to the shared web error handler.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>.

=head1 INCOMPATIBILITIES

Requires migration 1025.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. BSD-3-Clause.

=cut
