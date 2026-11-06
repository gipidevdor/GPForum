# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Config;
use JSON::MaybeXS;
use MIME::Base64 qw(encode_base64url);
use Mojo::Date;
use Mojo::Message::Request;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use lib 'lib';
use GPForum::Service::Forum::PageWindow;
use GPForum::Service::Forum::ThreadReader;
use GPForum::Web::PublicCacheAccess;
{
    package GPForum::Review::ConditionalRequest;
    use Mojo::Base -base, -signatures;
    use v5.40;
    has request => sub {return Mojo::Message::Request->new;};
    sub req ($self) {return $self->request;}
}
my $access=GPForum::Web::PublicCacheAccess->new;
my $etag='W/"0123456789abcdef0123456789abcdef01234567"';
my $list=join ', ', (map {'W/"other-'.$_.'"'} 1 .. 7), $etag;
my $epoch=1_793_923_000;
my $request=GPForum::Review::ConditionalRequest->new;
$request->request->headers->header('If-None-Match' => 'W/"stale"');
$request->request->headers->header('If-Modified-Since' => Mojo::Date->new($epoch-1)->to_string);
my $entry={etag => $etag,last_modified_epoch => $epoch};
my $window=GPForum::Service::Forum::PageWindow->new;
my $reader=GPForum::Service::Forum::ThreadReader->new(schema => {},functions => undef);
my $id='018f1000-0000-7000-8000-000000000001';
my $instant='2026-11-06 01:02:03.123456+14:00';
my $plain={limit => 25};
my $cursor={limit => 25,sort => 'timestamp',after => encode_base64url("$instant|$id")};
my $oversized={limit => 25,after => 'A' x 4096};
my $category={category_id => $id,limit => 25,after => encode_base64url("1|$instant|$id")};
my $category_plain={category_id => $id,limit => 25};
my @cases=(
 ['etag_exact_weak',500_000,sub {return $access->etag_matches($etag,$etag);},1],
 ['etag_wildcard',500_000,sub {return $access->etag_matches('*',$etag);},1],
 ['etag_list_eight_members',200_000,sub {return $access->etag_matches($list,$etag);},1],
 ['stale_etag_with_older_date',100_000,sub {return $access->client_has_fresh_copy($request,$entry);},0],
 ['ordinary_plan_no_cursor',200_000,sub {return $window->plan($plain);} ],
 ['ordinary_plan_timestamp_cursor',50_000,sub {return $window->plan($cursor);} ],
 ['ordinary_plan_oversized_4096',100_000,sub {return $window->plan($oversized);} ],
 ['category_call_no_cursor_no_database',50_000,sub {return $reader->category_threads_call($category_plain);} ],
 ['category_call_pinned_cursor_no_database',30_000,sub {return $reader->category_threads_call($category);} ],
);
my @results;
for my $case (@cases) {
 my ($name,$iterations,$code,$expected)=@{$case};my $sink;
 for (1 .. 100) {$sink=$code->();}
 for my $repetition (1 .. 3) {
  my $start=clock_gettime(CLOCK_MONOTONIC);
  for (1 .. $iterations) {$sink=$code->();}
  my $seconds=clock_gettime(CLOCK_MONOTONIC)-$start;
  push @results,{name=>$name,repetition=>$repetition,iterations=>$iterations,seconds=>$seconds,operations_per_second=>$iterations/$seconds};
 }
 die "Validator result changed\n" if defined $expected && $sink!=$expected;
 die "Cursor result changed\n" if $name eq 'ordinary_plan_timestamp_cursor' && $sink->{after}{id} ne $id;
 die "Oversized cursor accepted\n" if $name eq 'ordinary_plan_oversized_4096' && defined $sink->{after};
 die "Pinned cursor changed\n" if $name eq 'category_call_pinned_cursor_no_database' && $sink->[1]{after_thread_id} ne $id;
}
print JSON::MaybeXS->new(canonical=>1,utf8=>1,pretty=>1)->encode({
 perl=>"$^V",architecture=>$Config{archname},platform=>$^O,
 method=>'Three fixed-iteration batches after 100 warmups, monotonic wall time. Validators and plans run without database or network. All timed inputs have identical semantic results before/after. The oversized 4096-character cursor is an invalid-input resource case, not a normal page. HTTP measurements use a different, explicitly cumulative baseline to revisit the preceding home latency concern.',results=>\@results,
});
