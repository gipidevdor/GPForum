# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::NotificationWorkflowServices;

use Carp qw(croak);
use Mojo::Base -base, -async_await;
use v5.40;

our $VERSION = '0.001';

has preference_updates => sub { return []; };

# Each answers a settled promise, as the dispatcher's and the preference
# store's promise methods do on the blocking layer (ADR 0177).
async sub mark_read_p ( $, $notification_id, $user_id, $context = undef ) {
    croak 'dispatcher down'                  if $notification_id eq 'boom';
    return                                   if $notification_id eq 'gone';
    return { error => 'not_found', ok => 0 } if $notification_id eq 'missing';

    return {
        notification_id   => $notification_id,
        ok                => 1,
        recipient_user_id => $user_id,
    };
}

async sub mark_all_read_p ( $, $user_id, $context = undef ) {
    croak 'dispatcher down' if $user_id eq 'boom';

    return {
        duplicate         => 0,
        marked_count      => 2,
        ok                => 1,
        recipient_user_id => $user_id,
        unread_count      => 0,
    };
}

async sub set_preferences_p ( $self, $input, $context = undef, $scope = undef )
{
    my $user_id = $input->{user_id} || q{};
    croak 'preference store down' if $user_id eq 'boom';
    return                        if $user_id eq 'gone';
    push @{ $self->preference_updates }, $input;

    return $input->{preferences} || [];
}

1;

__END__

=head1 NAME

GPForum::Test::NotificationWorkflowServices - Notification write fakes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $services = GPForum::Test::NotificationWorkflowServices->new;

=head1 DESCRIPTION

Test double for C<Notification::Workflow> mark-read and preference outcomes:
success, missing row, empty result, and store exceptions.

=head1 SUBROUTINES/METHODS

=head2 mark_read_p

Answers a dispatcher-shaped hash, an empty result, or fails.

=head2 mark_all_read_p

Marks the inbox read or fails for C<boom>.

=head2 set_preferences_p

Records preference writes or fails.

=head1 DIAGNOSTICS

The C<boom> notification id or user id fails the promise.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Uses L<Mojo::Base> with C<-async_await>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Intended only for workflow unit tests.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
