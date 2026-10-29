# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::BadgeBatchSpy;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

has batches => sub { return []; };
has refuses => undef;

sub notify_many ( $self, $events ) {
    push @{ $self->batches }, [ @{$events} ];
    return $self->refuses if $self->refuses;

    return {
        ok       => 1,
        channel  => 'spy',
        sent     => scalar @{$events},
        rejected => 0,
        bytes    => 0,
    };
}

1;

__END__

=head1 NAME

GPForum::Test::BadgeBatchSpy - A realtime notifier that takes badges in batches and remembers them.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $spy = GPForum::Test::BadgeBatchSpy->new;
    my $dispatcher = GPForum::Service::Notification::Dispatcher->new(
        realtime_notifier => $spy, ... );
    is( scalar @{ $spy->batches }, 1, 'one NOTIFY statement' );

=head1 DESCRIPTION

Stands in for L<GPForum::Service::Realtime::PgNotifier> where a test checks
that a fan-out sends its badges in one C<notify_many> call. It has no
C<notify>: a dispatcher that sent badges one at a time would die here.

=head1 SUBROUTINES/METHODS

=head2 batches

Each C<notify_many> call's events, as an array reference.

=head2 refuses

The answer every batch gets instead of C<ok>, when set.

=head2 notify_many

Records the events and answers C<ok> with C<sent>, or C<refuses>.

=head1 DIAGNOSTICS

None.

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
