# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::FanoutFunctions;

use Carp qw(croak);
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

has calls      => sub { return []; };
has candidates => sub { return []; };
has outcomes   => sub { return {}; };
has uncounted  => sub { return {}; };
has refuses    => undef;
has placement  => sub {
    return {
        post_visibility     => 'members',
        post_author         => 'user-author',
        post_deleted_at     => undef,
        post_state          => 'visible',
        thread_visibility   => 'public',
        thread_author       => 'user-author',
        thread_deleted_at   => undef,
        thread_state        => 'visible',
        category_id         => 'category-1',
        category_visibility => 'public',
        category_deleted_at => undef,
        space_id            => 'space-1',
        space_visibility    => 'public',
    };
};

sub row ( $self, $name, $values ) {
    return $self->rows( $name, $values )->[0];
}

sub rows ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, $values ];
    return [ { %{ $self->placement } } ] if $name eq 'forum_post_placement';
    return [ map { +{ %{$_} } } @{ $self->candidates } ]
      if $name eq 'notification_fanout_candidates';
    return []            if $name ne 'notification_fanout_deliver';
    croak $self->refuses if defined $self->refuses;

    return [ map { $self->_answer($_) } @{ $values->{recipients} } ];
}

sub _answer ( $self, $recipient ) {
    my $user    = $recipient->{recipient_user_id};
    my $outcome = $self->outcomes->{$user}
      // ( $recipient->{in_app} ? 'created' : 'skipped' );
    if ( $outcome eq 'failed' ) {
        return {
            recipient_user_id => $user,
            outcome           => 'failed',
            result            => undef,
            unread_count      => undef,
            email_queued      => 0,
            error             => 'refused',
        };
    }
    my $uncounted = $self->uncounted->{$user};

    return {
        recipient_user_id => $user,
        outcome           => $outcome,
        result            => $outcome eq 'skipped'
        ? undef
        : {
            ok              => 1,
            duplicate       => $outcome eq 'duplicate' ? 1 : 0,
            idempotency_key => $recipient->{idempotency_key},
            notification    => $recipient->{notification},
            inbox           => $recipient->{inbox},
        },
        unread_count => $outcome eq 'skipped' || defined $uncounted ? undef : 1,
        email_queued => $recipient->{email}                         ? 1     : 0,
        error        => $uncounted,
    };
}

1;

__END__

=head1 NAME

GPForum::Test::FanoutFunctions - A function layer answering the fan-out's three calls from a script.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $functions = GPForum::Test::FanoutFunctions->new(
        candidates => [ { user_id => 'user-a', in_app => 1, ... } ],
        outcomes   => { 'user-f' => 'duplicate', 'user-g' => 'failed' },
        uncounted  => { 'user-h' => 'canceling statement due to lock timeout' },
    );

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::SqlFunction> under a
L<GPForum::Service::Notification::Dispatcher> whose fan-out is tested
without PostgreSQL. C<notification_fanout_candidates> answers the
C<candidates> given; C<notification_fanout_deliver> answers one row per
recipient sent, C<created> for one with the inbox channel on and C<skipped>
for one without, unless C<outcomes> names another, with the count's error
from C<uncounted>; C<forum_post_placement> answers the C<placement>, a
members-only post in a public thread, so a real recipient policy screens
the viewers. Every call is recorded.

=head1 SUBROUTINES/METHODS

=head2 calls

Each call made, as C<[ $name, $values ]>.

=head2 candidates

The rows the candidates call answers.

=head2 outcomes

Recipient user id to the outcome the deliveries call answers for them:
C<created>, C<duplicate>, C<skipped> or C<failed>.

=head2 uncounted

Recipient user id to the error the unread count failed with: the row then
has no count and carries the error.

=head2 refuses

A message the deliveries call dies with, when set.

=head2 placement

The row the post placement call answers.

=head2 row

The first row C<rows> answers.

=head2 rows

Records the call and answers it as scripted.

=head1 DIAGNOSTICS

Dies with C<refuses> when it is set and the deliveries are called.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
