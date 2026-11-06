# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Test::More;
use Const::Fast;
use Test::Fatal;
use lib 'lib';
use lib 't/lib';
use GPForum::Config;
use GPForum::Service::Integration::Registry;
use GPForum::Security::BrowserHeaders;
use GPForum::ViewModel::Forum::Rows;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use Mojo::Log;

our $VERSION = '0.001';
const my $URL_LIMIT    => 2_048;
const my $SOURCE_LIMIT => 50_000;
const my $MANY_LINKS   => 20;
const my $CARD_LIMIT   => 5;

my $config  = GPForum::Config->from_environment( {} );
my $plugins = GPForum::Service::Integration::Registry->new(
    enabled => $config->integration_plugins, );
is_deeply(
    [ map { $_->{id} } @{ $plugins->catalogue } ],
    [
        qw(youtube vimeo gitlab codeberg github facebook instagram spotify apple_music wikipedia mathematics)
    ],
    'packaged plugin catalogue'
);
ok(
    !(
        grep { !$_->{enabled} || $_->{api_version} != 1 || !$_->{version} }
        @{ $plugins->catalogue }
    ),
    'active providers declare compatible versions'
);

for my $link (
    'https://youtu.be/dQw4w9WgXcQ?si=tracking',
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10',
    'https://m.youtube.com/shorts/dQw4w9WgXcQ',
    'https://youtube.com/live/dQw4w9WgXcQ',
    'https://youtube.com:443/embed/dQw4w9WgXcQ',
  )
{
    is(
        $plugins->resolve($link)->{embed}{url},
        'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ',
        'YouTube normalizes a supported video link'
    );
}
is(
    $plugins->resolve(
        'https://github.com/octocat/Hello-World/issues/42?tracking=yes')->{url},
    'https://github.com/octocat/Hello-World/issues/42',
    'GitHub removes tracking'
);
is(
    $plugins->resolve('https://github.com/octocat/Hello-World/pull/42')->{kind},
    'pull_request', 'pull requests retain their kind'
);
is(
    $plugins->resolve('https://github.com/octocat/Hello-World/commit/abc1234')
      ->{kind},
    'commit', 'commits are supported'
);
is(
    $plugins->resolve(
        'https://github.com/octocat/Hello-World/releases/tag/v1.0')->{kind},
    'release',
    'releases are supported'
);
is(
    $plugins->resolve(
        'https://www.facebook.com/user/posts/pfbid123?tracking=yes')->{url},
    'https://www.facebook.com/user/posts/pfbid123',
    'Facebook canonical post link'
);
is(
    $plugins->resolve(
'https://m.facebook.com/permalink.php?story_fbid=123&id=456&tracking=yes'
    )->{url},
    'https://www.facebook.com/permalink.php?story_fbid=123&id=456',
    'Facebook keeps essential query parameters'
);
is( $plugins->resolve('https://facebook.com/watch/?v=123')->{provider},
    'facebook', 'Facebook watch URL is supported' );
is( $plugins->resolve('https://facebook.com/reel/123')->{provider},
    'facebook', 'Facebook reels are supported' );

for my $bad (
    'http://youtu.be/dQw4w9WgXcQ',
    'javascript:alert(1)',
    'https://www.youtube.com.evil.test/watch?v=dQw4w9WgXcQ',
    'https://github.com@evil.test/octocat/repo',
    'https://user:password@github.com/octocat/repo',
    'https://github.com:444/octocat/repo',
    'https://github.com/../..',
    'https://github.com/octocat/repo/<script>',
    'https://www.facebook.com/l.php?u=https://evil.test',
    'https://facebook.com/login.php',
    'https://youtube.com/watch?v=short',
    'https://youtu.be/dQw4w9WgXcQ/extra',
    'https://127.0.0.1/private',
    'https://github.com\\@evil.test/octocat/repo',
    'https://github.com/octocat/repo' . ( 'x' x $URL_LIMIT ),
  )
{
    ok( !defined $plugins->resolve($bad),
        'unsafe or unsupported URL remains ordinary source' );
}

my $video = 'https://youtu.be/dQw4w9WgXcQ';
my $cards = $plugins->for_source(
"$video\n[video](https://youtube.com/watch?v=dQw4w9WgXcQ)\n\nhttps://github.com/octocat/repo"
);
is( scalar @{$cards}, 2, 'normalized duplicate links create one card' );
is_deeply(
    $plugins->for_source(
"```perl\n$video\n```not-a-close\nhttps://github.com/octocat/repo\n```\n`$video`\n> $video\n- $video\nLook at $video"
    ),
    [],
    'code, quotes, lists and inline URLs produce no cards'
);
is(
    scalar @{
        $plugins->for_source( join "\n",
            map { "https://github.com/octocat/repo$_" } 1 .. $MANY_LINKS )
    },
    $CARD_LIMIT,
    'cards per post are bounded'
);
is_deeply( $plugins->for_source( ( 'x' x $SOURCE_LIMIT ) . "\n$video" ),
    [], 'oversized source does not extend scanning' );

my $disabled =
  GPForum::Service::Integration::Registry->new( enabled => ['none'] );
is_deeply( $disabled->for_source($video),
    [], 'disable all leaves source alone' );
my $only_github =
  GPForum::Service::Integration::Registry->new( enabled => ['github'] );
ok( !defined $only_github->resolve($video), 'per-provider disable works' );
is( $only_github->resolve('https://github.com/octocat/repo')->{provider},
    'github', 'selected plugin stays active' );
like(
    exception {
        GPForum::Config->from_environment(
            { GPFORUM_INTEGRATION_PLUGINS => 'unknown' } )
    },
    qr/GPFORUM_INTEGRATION_PLUGINS/msx,
    'unknown plugin configuration fails at startup'
);
like(
    exception {
        GPForum::Service::Integration::Registry->new( enabled => ['unknown'] )
          ->active
    },
    qr/unknown[ ]integration[ ]plugin/msx,
    'direct registry use also validates IDs'
);
with_replaced_subs(
    'GPForum::Service::Integration::GitHub',
    { manifest_v1 => sub { return { id => 'github', api_version => 99 } } },
    sub {
        like(
            exception {
                GPForum::Service::Integration::Registry->new(
                    enabled => ['github'] )->active
            },
            qr/plugin[ ]API[ ]v1[ ]contract[ ]violation/msx,
            'incompatible contract is refused'
        );
    }
);

my @logs;
my $log = Mojo::Log->new;
$log->on(
    message => sub ( $emitter, $level, @messages ) { push @logs, @messages; } );
my $failing = GPForum::Service::Integration::Registry->new(
    enabled => [ 'github', 'youtube' ],
    logger  => $log
);
with_replaced_subs(
    'GPForum::Service::Integration::GitHub',
    { resolve_link_v1 => sub { die "private source secret\n"; } },
    sub {
        is(
            $failing->for_source("https://github.com/octocat/repo\n$video")
              ->[0]{provider},
            'youtube',
            'failing optional plugin cannot prevent another from resolving'
        );
    }
);
like(
    join( q{}, @logs ),
    qr/integration[ ]plugin[ ]failed:[ ]github/msx,
    'provider failure is observable'
);
unlike(
    join( q{}, @logs ),
    qr/secret|private source|youtu[.]be/msx,
    'failure log contains no source or provider exception'
);

my $rows =
  GPForum::ViewModel::Forum::Rows->new( integration_plugins => $plugins );
is( scalar @{ $rows->post( { body_source => $video } )->{integrations} },
    1, 'post presenter calls the plugin registry' );
is_deeply(
    $rows->post( { body_source => $video, deleted_at => '2026-11-01' } )
      ->{integrations},
    [],
    'deleted posts expose no integration cards'
);
is_deeply(
    $rows->post(
        { body => '<a href="https://youtu.be/dQw4w9WgXcQ">stored HTML</a>' }
    )->{integrations},
    [],
    'stored markup is never treated as source'
);
unlike(
    GPForum::Security::BrowserHeaders->new->content_security_policy,
    qr/youtube/msx,
    'disabled browser policy permits no YouTube frame'
);
like(
    GPForum::Security::BrowserHeaders->new(
        embed_origins => ['https://www.youtube-nocookie.com']
    )->content_security_policy,
    qr/frame-src[ ]'self'[ ]https:\/\/www[.]youtube-nocookie[.]com/msx,
    'only privacy-enhanced YouTube frame origin is added'
);

done_testing();

1;
