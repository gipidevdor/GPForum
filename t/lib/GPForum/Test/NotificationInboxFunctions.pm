# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::NotificationInboxFunctions;

use Carp qw(croak);
use Const::Fast;
use Mojo::Base 'GPForum::Test::SettledCalls', -signatures;
use v5.40;

use Mojo::Promise;

use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

# The unread count stops past 99, as api.notification_unread_count does.
const my $UNREAD_CAP => 99;

# The notification functions the dispatcher calls, over an inbox kept in
# memory: a delivery, a read, a read of everything and the unread count,
# answered as the api functions answer them. Every call is recorded. A
# function named in failures dies instead -- with the text given, or what a
# code reference given the call's values returns -- as a statement
# PostgreSQL cancelled. A transaction counts its depth, so a double of the
# notifier can ask whether one is open; nothing is rolled back.
has calls         => sub { return []; };
has failures      => sub { return {}; };
has inbox         => sub { return {}; };
has notifications => sub { return {}; };
has rolled_back   => sub { return []; };
has depth         => 0;

my %ANSWER = (
    notification_deliver       => \&_deliver,
    notification_mark_read     => \&_mark_read,
    notification_mark_all_read => \&_mark_all_read,
    notification_unread_count  => \&_unread_count,
);

sub rows ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, $values ];
    my $failure = $self->failures->{$name};
    if ( defined $failure ) {
        croak ref $failure eq 'CODE' ? $failure->($values) : $failure;
    }
    my $answer = $ANSWER{$name} or return [];

    return [ $answer->( $self, $values ) ];
}

sub row ( $self, $name, $values ) {
    return $self->rows( $name, $values )->[0];
}

# The work at one more depth; a failure it ends in is kept as rolled back
# and answered as the rejected promise transaction_p answers.
sub transaction_p ( $self, $work, $context = undef, $readonly = 0 ) {
    $self->depth( $self->depth + 1 );
    my ( $value, $error, $failed );
    try {
        $value =
          GPForum::Infrastructure::SqlFunction->settled( $work->($self) );
    }
    catch ($caught) {
        ( $error, $failed ) = ( $caught, 1 );
    };
    $self->depth( $self->depth - 1 );
    if ($failed) {
        push @{ $self->rolled_back }, $error;
        return Mojo::Promise->reject($error);
    }

    return Mojo::Promise->resolve($value);
}

sub in_transaction ($self) {
    return $self->depth ? 1 : 0;
}

# The calls made to one function, as their values.
sub asked ( $self, $name ) {
    return [ map { $_->[1] } grep { $_->[0] eq $name } @{ $self->calls } ];
}

sub _deliver ( $self, $call ) {
    my %inbox        = %{ $call->{inbox} };
    my $key          = _key( @inbox{qw(recipient_user_id notification_id)} );
    my $stored_inbox = $self->inbox->{$key};
    if ($stored_inbox) {
        return {
            result => {
                ok              => 1,
                duplicate       => 1,
                idempotency_key => $call->{idempotency_key},
                notification    => {
                    %{ $call->{notification} },
                    notification_id => $stored_inbox->{notification_id},
                    created_at      => $stored_inbox->{created_at},
                },
                inbox => { %{$stored_inbox} },
            }
        };
    }
    my $stored       = $self->notifications->{ $inbox{notification_id} };
    my $at           = $stored ? $stored->{created_at} : $inbox{created_at};
    my %notification = ( %{ $call->{notification} }, created_at => $at );
    $inbox{created_at} = $at;
    $self->notifications->{ $inbox{notification_id} } //= {%notification};
    $self->inbox->{$key} = {%inbox};

    return {
        result => {
            ok              => 1,
            duplicate       => 0,
            idempotency_key => $call->{idempotency_key},
            notification    => \%notification,
            inbox           => \%inbox,
        }
    };
}

sub _mark_read ( $self, $call ) {
    my $inbox =
      $self->inbox->{ _key( @{$call}{qw(recipient_user_id notification_id)} ) };
    return { result => { ok => 0, error => 'not_found' } } if !$inbox;
    my $duplicate = defined $inbox->{read_at} ? 1 : 0;
    $inbox->{read_at} //= $call->{read_at};

    return {
        result => {
            ok        => 1,
            duplicate => $duplicate,
            %{$inbox}{qw(notification_id recipient_user_id read_at)},
        }
    };
}

sub _mark_all_read ( $self, $call ) {
    my @unread = grep {
        $_->{recipient_user_id} eq $call->{user_id}
          && !defined $_->{read_at}
    } values %{ $self->inbox };
    for my $inbox (@unread) { $inbox->{read_at} = $call->{read_at}; }

    return {
        result => {
            ok                => 1,
            duplicate         => @unread ? 0 : 1,
            marked_count      => scalar @unread,
            read_at           => $call->{read_at},
            recipient_user_id => $call->{user_id},
        }
    };
}

sub _unread_count ( $self, $call ) {
    my $unread = grep {
        $_->{recipient_user_id} eq $call->{recipient_user_id}
          && !defined $_->{read_at}
    } values %{ $self->inbox };

    return {
        unread_count => $unread > $UNREAD_CAP ? $UNREAD_CAP + 1 : $unread };
}

sub _key ( $recipient_user_id, $notification_id ) {
    return join "\0", $recipient_user_id, $notification_id;
}

1;

__END__

=head1 NAME

GPForum::Test::NotificationInboxFunctions - The notification functions over an inbox kept in memory.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $functions = GPForum::Test::NotificationInboxFunctions->new;
    my $dispatcher = GPForum::Service::Notification::Dispatcher->new(
        functions => $functions, schema => {} );
    $functions->failures->{notification_unread_count} =
      "canceling statement due to statement timeout\n";

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::SqlFunction> under
L<GPForum::Service::Notification::Dispatcher>. It answers
C<notification_deliver>, C<notification_mark_read>,
C<notification_mark_all_read> and C<notification_unread_count> as the api
functions do, over the C<notifications> and C<inbox> it keeps: a delivery
the recipient already has is a duplicate answered with the stored row, a
notification already stored under the id gives the inbox row its time, a
read already made is a duplicate with its earlier time, and the count stops
at 100. Any other function answers no rows. Its promises are settled
(L<GPForum::Test::SettledCalls>), so the dispatcher's promise methods and
their blocking twins both run on it.

=head1 SUBROUTINES/METHODS

=head2 calls

Each call made, as C<[ $name, $values ]>.

=head2 failures

Function name to the error it croaks with: a string, or a code reference
given the call's values that returns one. End it with a newline to keep
it as it is.

=head2 inbox

The inbox rows, by recipient and notification id.

=head2 notifications

The notification rows, by id.

=head2 rolled_back

The errors each transaction ended in, in order.

=head2 depth

How many transactions are open.

=head2 rows

Records the call and answers the function's rows, or dies as C<failures>
says.

=head2 row

The first of L</rows>.

=head2 transaction_p

Runs the work on the double one depth further in, answering its value as
a settled promise, or its failure, kept in C<rolled_back>, as a rejected
one. Nothing written in it is rolled back.

=head2 in_transaction

True while a transaction is open.

=head2 asked

The values of each call made to one function, in order.

=head1 DIAGNOSTICS

Dies as C<failures> says.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Carp>, L<Const::Fast>, L<Mojo::Base>, L<Mojo::Promise>,
L<GPForum::Infrastructure::SqlFunction>, L<GPForum::Test::SettledCalls>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The readability filter is not applied: every source counts as readable.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
