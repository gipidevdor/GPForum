# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use Storable qw(dclone);
use Test::Fatal;
use Test::More;
use lib 'lib';
use GPForum::Domain::EventEnvelope;
our $VERSION = '0.001';

const my %EVENT => (
    aggregate_id   => 'thread-1',
    aggregate_type => 'thread',
    correlation_id => 'correlation-1',
    event_id       => 'event-1',
    event_type     => 'thread.created',
);
const my $CREATED => '2026-11-06T12:00:00Z';
const my $EARLIER => '2026-11-05T12:00:00Z';
my $envelope = GPForum::Domain::EventEnvelope->new;

subtest 'explicit text identifiers survive record and transport' => sub {
    my $event = $envelope->record( %EVENT, idempotency_key => '0' );
    is( $event->{idempotency_key}, '0', 'a nonempty zero key is explicit' );
    is( $envelope->transport_payload($event)->{idempotency_key},
        '0', 'transport preserves the explicit key' );
    my $key_only;
    is(
        exception {
            $key_only = $envelope->record(
                %EVENT,
                aggregate_id    => undef,
                idempotency_key => '0'
            );
        },
        undef,
        'an explicit key does not require a concrete aggregate'
    );
    is( $key_only && $key_only->{idempotency_key}, '0', 'the key is retained' );
    for my $missing ( undef, q{} ) {
        is(
            $envelope->record( %EVENT, idempotency_key => $missing )
              ->{idempotency_key},
            'thread.created:thread-1',
            'missing keys still use the generated default'
        );
    }
    for my $case ( [ 0, '0' ], [ q{}, 'event-1' ], [ undef, 'event-1' ] ) {
        my ( $id, $expected ) = @{$case};
        my $row = $envelope->record(
            %EVENT,
            aggregate_id    => $id,
            idempotency_key => 'key'
        );
        is( $envelope->transport_payload($row)->{transport}{partition_key},
            $expected,
            'partitioning preserves nonempty aggregate identifiers' );
    }
};

subtest
  'version normalization accepts positive ASCII integers without warnings' =>
  sub {
    for my $field (qw(schema_version aggregate_version)) {
        for my $value ( 2, '02', '19' ) {
            is( $envelope->record( %EVENT, $field => $value )->{$field},
                $value, "$field retains a supported version" );
        }
        for my $case (
            [ undef,                         'missing' ],
            [ q{},                           'empty' ],
            [ 0,                             'zero' ],
            [ '-1',                          'negative' ],
            [ '1.5',                         'fractional' ],
            [ '1e2',                         'exponential' ],
            [ '1x',                          'trailing text' ],
            [ "\N{ARABIC-INDIC DIGIT ONE}",  'Unicode digits' ],
            [ "1\N{ARABIC-INDIC DIGIT ONE}", 'mixed ASCII and Unicode digits' ],
          )
        {
            my ( $value, $label ) = @{$case};
            my @warnings;
            my $event;
            {
                local $SIG{__WARN__} = sub { push @warnings, $_[0]; return; };
                $event = $envelope->record( %EVENT, $field => $value );
            }
            is( $event->{$field}, 1, "$field defaults for $label" );
            is_deeply( \@warnings, [],
                "$field rejects $label without numeric warnings" );
        }
    }
  };

subtest
  'transport snapshots retain timestamp precedence and leave the event intact'
  => sub {
    for my $created ( $CREATED, undef ) {
        my $event = $envelope->record(
            %EVENT,
            metadata  => { timestamp => $EARLIER, request_id => 'request-1' },
            payload   => { title     => 'Welcome' },
            timestamp => $created
        );
        $event->{metadata}{timestamp} = $EARLIER;
        my $before    = dclone($event);
        my $transport = $envelope->transport_payload($event);
        my $expected  = $created // $EARLIER;
        is_deeply(
            [
                @{$transport}{qw(timestamp occurred_at)},
                $transport->{metadata}{timestamp}
            ],
            [ $expected, $expected, $expected ],
            'the durable timestamp wins, with metadata as fallback'
        );
        is_deeply( $event, $before,
            'building transport does not change the durable event' );
        is_deeply( $transport->{payload}, $event->{payload},
            'domain data is preserved' );
    }
  };

done_testing;
1;
