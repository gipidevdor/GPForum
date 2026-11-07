# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use lib 'lib';
use GPForum::Service::Integration::Registry;
use GPForum::Service::Forum::BodyRenderer;
our $VERSION = '0.001';
my %links = (
    youtube     => 'https://youtu.be/dQw4w9WgXcQ',
    vimeo       => 'https://vimeo.com/123456',
    gitlab      => 'https://gitlab.com/group/project/-/issues/1',
    codeberg    => 'https://codeberg.org/team/project/issues/1',
    github      => 'https://github.com/octocat/Hello-World/issues/42',
    facebook    => 'https://www.facebook.com/user/posts/pfbid123',
    instagram   => 'https://www.instagram.com/p/AbCdEf123/',
    spotify     => 'https://open.spotify.com/episode/4uLU6hMCjMI75M1A2tKUQC',
    apple_music => 'https://music.apple.com/us/album/example/1234567890',
    wikipedia   => 'https://en.wikipedia.org/wiki/Perl',
    mastodon    => 'https://social.example.org/@user/123456',
    peertube    =>
      'https://video.example.org/w/52a10666-3a18-4e73-93da-e8d3c12c305a',
);
my @ids       = ( sort keys %links, 'mathematics' );
my %instances = (
    mastodon_hosts => ['social.example.org'],
    peertube_hosts => ['video.example.org']
);
my $registry =
  GPForum::Service::Integration::Registry->new( enabled => \@ids, %instances );
is_deeply(
    [ sort map { $_->{id} } @{ $registry->catalogue } ],
    [ sort @ids ],
    'every packaged provider has an executable feature case'
);

for my $id ( sort keys %links ) {
    my $card = $registry->resolve( $links{$id} );
    ok( $card, "provider $id resolves its resource" );
    is( $card->{provider}, $id, "provider $id owns its resolved card" );
    my $disabled =
      GPForum::Service::Integration::Registry->new( enabled => [], %instances );
    ok(
        !defined $disabled->resolve( $links{$id} ),
        "provider $id can be disabled independently"
    );
    my $link_only = GPForum::Service::Integration::Registry->new(
        enabled => [$id],
        modes   => { $id => 'link' },
        %instances
    );
    ok( !exists $link_only->resolve( $links{$id} )->{embed},
        "provider $id respects link-only mode" );
}
my $renderer =
  GPForum::Service::Forum::BodyRenderer->new( math_plugins => $registry );
like( $renderer->render_safe(q{$x^2$}),
    qr/math-expression/msx, 'provider mathematics renders its expression' );
my $plain = GPForum::Service::Forum::BodyRenderer->new;
unlike( $plain->render_safe(q{$x^2$}),
    qr/math-expression/msx,
    'provider mathematics can be disabled independently' );
done_testing();
1;
