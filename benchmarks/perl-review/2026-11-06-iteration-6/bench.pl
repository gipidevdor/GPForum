# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Config;
use JSON::MaybeXS;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use lib 'lib', 't/lib';
use GPForum::Infrastructure::ResultRow;
use GPForum::Service::Forum::BodyRenderer;
use GPForum::Service::Forum::ReadState;
use GPForum::Service::Integration::Registry;
use GPForum::Test::ReadStateResultSet;
use GPForum::Test::ReadStateSchema;

my $markers = GPForum::Test::ReadStateResultSet->new;
$markers->create(
    {
        user_id            => 'reader',
        thread_id          => 'thread',
        last_read_position => 12,
        last_read_at       => 'recorded'
    }
);
my $reader = GPForum::Service::Forum::ReadState->new(
    schema => GPForum::Test::ReadStateSchema->new(
        resultsets => { ThreadReadState => $markers }
    )
);
my @cases;

for my $spec (
    [ 'hash_25',         25,  0, 1, 20_000 ],
    [ 'result_rows_25',  25,  1, 1, 12_000 ],
    [ 'result_rows_200', 200, 1, 1, 2_000 ],
    [ 'empty_member',    0,   0, 1, 30_000 ],
    [ 'anonymous_25',    25,  1, 0, 20_000 ]
  )
{
    my ( $name, $size, $objects, $member, $iterations ) = @{$spec};
    my $posts = [
        map {
            my $row = { post_id => 'post-' . $_, position => $_ };
            $objects ? GPForum::Infrastructure::ResultRow->from($row) : $row
        } 1 .. $size
    ];
    my $expected = {
        authenticated         => $member,
        unread_in_page        => ( $member && $size > 12 ? $size - 12 : 0 ),
        last_visible_position => $size,
        first_unread_position => ( $member ? ( $size > 12 ? 13 : 0 ) : undef )
    };
    push @cases, [
        'summary_' . $name,
        $iterations,
        sub {
            return $reader->summary_for_page( $member ? 'reader' : undef,
                'thread', $posts );
        },
        sub($result) {
            for my $key ( keys %{$expected} ) {
                die "Changed summary $name/$key\n"
                  if defined $result->{$key} != defined $expected->{$key}
                  || ( defined $expected->{$key}
                    && $result->{$key} != $expected->{$key} );
            }
        }
    ];
}
my $math = GPForum::Service::Forum::BodyRenderer->new(
    math_plugins => GPForum::Service::Integration::Registry->new(
        enabled => ['mathematics']
    )
);
my $plain    = GPForum::Service::Forum::BodyRenderer->new;
my $disabled = GPForum::Service::Forum::BodyRenderer->new( math_plugins =>
      GPForum::Service::Integration::Registry->new( enabled => [] ) );
my $source =
  q{A **rendered** post with $x_i^2$ and a [link](https://example.test).};
for my $spec (
    [ 'math',              $math ],
    [ 'plain',             $plain ],
    [ 'disabled_registry', $disabled ]
  )
{
    my ( $name, $renderer ) = @{$spec};
    my $expected = $renderer->render_safe($source);
    push @cases,
      [
        'body_hit_' . $name,
        300_000,
        sub { return $renderer->render_safe($source); },
        sub($result) { die "Changed body $name\n" if $result ne $expected; }
      ];
}
for my $spec ( [ 'math', $math ], [ 'plain', $plain ] ) {
    my ( $name, $renderer ) = @{$spec};
    my $sequence = 0;
    push @cases, [
        'body_cold_' . $name,
        3_000,
        sub {
            return $renderer->render_safe(
                'cold-' . $name . '-' . ++$sequence . ' ' . $source );
        },
        sub($result) {
            die "Body not rendered\n"
              if $result !~ /<strong>rendered<\/strong>/;
        }
    ];
}
my @results;
for my $case (@cases) {
    my ( $name, $iterations, $code, $validate ) = @{$case};
    my $sink;
    $sink = $code->() for 1 .. 100;
    for my $repetition ( 1 .. 3 ) {
        my $start = clock_gettime(CLOCK_MONOTONIC);
        $sink = $code->() for 1 .. $iterations;
        my $seconds = clock_gettime(CLOCK_MONOTONIC) - $start;
        $validate->($sink);
        push @results,
          {
            name                  => $name,
            repetition            => $repetition,
            iterations            => $iterations,
            seconds               => $seconds,
            operations_per_second => $iterations / $seconds
          };
    }
}
print JSON::MaybeXS->new( canonical => 1, utf8 => 1, pretty => 1 )->encode(
    {
        perl         => "$^V",
        architecture => $Config{archname},
        platform     => $^O,
        method       =>
'Three fixed-iteration batches after 100 warmups, monotonic wall time. Read-state lookup uses an identical in-memory resultset; positions are hashes or actual ResultRow objects, with mixed read/unread positions. Anonymous and empty summaries are controls. Body rendering uses the real Mathematics registry and renderer; warm HTML has identical bytes, while cold cases generate a distinct source per operation and include that common generation cost. Every timed case checks its output. Values describe Perl CPU cost without SQL or network latency. HTTP separately exercises the real migrated PostgreSQL thread page.',
        results => \@results,
    }
);
