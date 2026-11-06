use v5.40;
use lib 'lib';
use JSON::MaybeXS;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use GPForum::Infrastructure::SqlFunction;
my $json=JSON::MaybeXS->new(canonical=>1,utf8=>0);
my $layer=GPForum::Infrastructure::SqlFunction->new(schema=>bless({},'UnusedSchema'));
my $values={post_ids=>[map {sprintf '018f1003-%04x-7000-8000-%012x',$_,$_}1..25],viewer_user_id=>'018f1002-0001-7000-8000-000000000001'};
sub normalize($value){
 return undef if !defined $value;
 return [map {!defined $_ ? undef : ref $_ eq 'ARRAY' ? normalize($_) : "$_"} @$value] if ref $value eq 'ARRAY';
 return "$value";
}
my $current=GPForum::Infrastructure::SqlFunction->can('_key');
my @variants=(['current',$current],['json',sub($entry,$bound){return $json->encode([$entry->{function},map{normalize($_)}@$bound]);}]);
for my $variant(@variants){
 no warnings 'redefine';
 local *GPForum::Infrastructure::SqlFunction::_key=$variant->[1];
 my $sink;
 for(1..100){$sink=$layer->answer_key('community_post_likes',$values)}
 for my $rep(1..3){my $start=clock_gettime(CLOCK_MONOTONIC);for(1..20_000){$sink=$layer->answer_key('community_post_likes',$values)}my $elapsed=clock_gettime(CLOCK_MONOTONIC)-$start;print "$variant->[0] $rep ",20_000/$elapsed,"\n"}
}
