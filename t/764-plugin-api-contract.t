# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Test::More;
use Test::Fatal;
use lib 'lib';
use GPForum::Service::Plugin::Contract;
use GPForum::Service::Integration::Registry;
use GPForum::Service::Integration::Spotify;

our $VERSION = '0.001';
my $api = GPForum::Service::Plugin::Contract->new;
my $manifest =
  $api->manifest_v1( GPForum::Service::Integration::Spotify->new->manifest_v1 );
my $url     = 'https://open.spotify.com/track/0Lr4kGOYn9l83EjuK6cZFQ';
my $request = $api->request_v1( { api_version => 1, url => $url } );
like( exception { $request->{url} = 'https://evil.test'; },
    qr/read-only/msx, 'plugin request values are immutable' );
like(
    exception { $request->{controller} = {}; },
    qr/disallowed|restricted/msx,
    'a plugin cannot expand the input contract'
);

for my $bad (
    { api_version => '1', url => $url },
    { api_version => 2,   url => $url },
    { api_version => 1,   url => $url, controller => {} },
    { api_version => 1,   url => $url, token      => 'secret' },
    { api_version => 1,   url => [] },
    { url         => $url },
  )
{
    ok( exception { $api->request_v1($bad) },
        'unknown, incompatible or non-data request is rejected' );
}
my $valid = {
    api_version => 1,
    provider    => 'spotify',
    kind        => 'audio',
    label       => 'Audio',
    url         => $url,
    embed       => {
        kind => 'audio',
        url  => 'https://open.spotify.com/embed/track/0Lr4kGOYn9l83EjuK6cZFQ'
    }
};
ok( $api->response_v1( $manifest, $valid ),
    'declared origins and fields pass' );
for my $bad (
    +{ %{$valid}, html     => '<script>x</script>' },
    +{ %{$valid}, provider => 'youtube' },
    +{ %{$valid}, url      => 'javascript:alert(1)' },
    +{ %{$valid}, url      => 'https://evil.test/path' },
    +{ %{$valid}, label    => [] },
    +{ %{$valid}, kind     => 'arbitrary-widget' },
    +{
        %{$valid},
        embed => { kind => 'audio', url => 'https://evil.test/embed' }
    },
    +{
        %{$valid},
        embed => {
            kind   => 'audio',
            url    => $valid->{embed}{url},
            script => 'external.js'
        }
    },
    +{ %{$valid}, embed => { kind => 'video', url => $valid->{embed}{url} } },
  )
{
    ok(
        exception { $api->response_v1( $manifest, $bad ) },
        'unsafe or undeclared plugin output is rejected'
    );
}
for my $bad (
    +{ %{$manifest}, api_version  => 2 },
    +{ %{$manifest}, capabilities => ['database.write'] },
    +{ %{$manifest}, capabilities => [qw(link.resolve.v1 link.resolve.v1)] },
    +{ %{$manifest}, frame_hosts  => ['*.spotify.com'] },
    +{ %{$manifest}, sql          => 'forbidden' },
  )
{
    ok(
        exception { $api->manifest_v1($bad) },
        'manifest is a closed capability contract'
    );
}

my $registry = GPForum::Service::Integration::Registry->new(
    enabled => [qw(instagram spotify apple_music)] );
is(
    $registry->resolve('https://www.instagram.com/reel/ABC123/?igsh=x')->{url},
    'https://www.instagram.com/reel/ABC123/',
    'Instagram is an independent canonical link provider'
);
ok(
    !defined $registry->resolve(
        'https://www.instagram.com.evil.test/p/ABC123/'),
    'Instagram lookalike origin rejected'
);
is(
    $registry->resolve($url)->{embed}{url},
    'https://open.spotify.com/embed/track/0Lr4kGOYn9l83EjuK6cZFQ',
    'Spotify returns a player descriptor'
);
is(
    $registry->resolve(
'https://open.spotify.com/intl-it/album/0Lr4kGOYn9l83EjuK6cZFQ?si=tracking'
    )->{url},
    'https://open.spotify.com/album/0Lr4kGOYn9l83EjuK6cZFQ',
    'Spotify localized URLs are normalized'
);
is(
    $registry->resolve(
        'https://music.apple.com/it/album/example/12345?i=67890&at=tracking')
      ->{embed}{url},
    'https://embed.music.apple.com/it/album/example/12345?i=67890',
    'Apple Music preserves selected track and removes tracking'
);
is(
    $registry->resolve('https://music.apple.com/us/playlist/example/pl.abc123')
      ->{provider},
    'apple_music', 'Apple Music supports playlists'
);
ok(
    !defined $registry->resolve(
        'https://music.apple.com/us/album/example/not-a-number'),
    'invalid Apple Music identifier rejected'
);
my $links_only = GPForum::Service::Integration::Registry->new(
    enabled => ['spotify'],
    modes   => { spotify => 'link' }
);
ok(
    !exists $links_only->resolve($url)->{embed},
    'GUI link-only mode removes the player'
);
is_deeply( $links_only->frame_origins,
    [], 'link-only mode grants no frame origin' );
isnt( $links_only->cache_variant,
    $registry->cache_variant,
    'mode and module selection change the public page variant' );

done_testing();

1;
