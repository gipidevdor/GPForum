# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::CategorySubscriptions;

use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Id;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

__PACKAGE__->requires('schema');
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins('change');

# Follows, mutes or removes a member's category subscription; a command
# that is not a uuid is invalid.
async sub change_p ( $self, $input, $context = undef ) {
    return { status => 'invalid' }
      if !GPForum::Infrastructure::Id->is_uuid( $input->{command} );
    my $functions = $self->functions
      // GPForum::X::Unavailable->throw( message =>
          'category subscriptions need the PostgreSQL function layer' );
    my $row = await $functions->row_p( 'notification_category_follow',
        $input, $context );

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

=head2 change_p

Follows, mutes or removes an active member's category subscription, with an
optional query context last.

=head2 change

The blocking twin: L</change_p> run on the blocking call layer (ADR 0177).

=head1 DIAGNOSTICS

Returns a status; database failures propagate to the shared web error
handler. Without the PostgreSQL function layer a change raises
L<GPForum::X::Unavailable>.

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
