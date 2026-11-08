# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::CategorySubscriptions;

use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Id;

our $VERSION = '0.001';

__PACKAGE__->requires('schema');
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

sub change ( $self, $input ) {
    return { status => 'invalid' }
      if !GPForum::Infrastructure::Id->is_uuid( $input->{command} );
    return _changed(
        $self->functions->row( 'notification_category_follow', $input ) );
}

async sub change_p ( $self, $input, $context = undef ) {
    return $self->change($input) if !$self->functions;
    return { status => 'invalid' }
      if !GPForum::Infrastructure::Id->is_uuid( $input->{command} );
    return _changed(
        await $self->functions->row_p(
            'notification_category_follow',
            $input, $context
        )
    );
}

sub _changed ($row) {
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

=head2 change_p

L</change> as a promise, with an optional query context last, run on the
worker's pooled asynchronous connections.

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

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
