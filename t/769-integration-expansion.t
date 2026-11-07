# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use Test::More;
use Test::Exception;
use Crypt::PK::RSA;
use Crypt::JWT qw(encode_jwt);
use lib 'lib';
use lib 't/lib';
use GPForum::Test::IntegrationResolver;
use GPForum::Test::IntegrationUserAgent;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use GPForum::Config;
use GPForum::Service::Integration::Registry;
use GPForum::Service::Integration::FeedParser;
use GPForum::Service::Integration::HttpClient;
use GPForum::Service::Identity::OpenID;

our $VERSION = '0.001';
const my $HTTPS_PORT        => 443;
const my $EXCESS_CANDIDATES => 150;
const my $MAX_CANDIDATES    => 100;
const my $RSA_EXPONENT      => 65_537;
const my $RSA_KEY_BYTES     => 256;
const my $SIGNATURE_OFFSET  => -5;
const my $TOKEN_SECONDS     => 300;
my $registry = GPForum::Service::Integration::Registry->new(
    enabled        => [qw(vimeo gitlab codeberg mastodon peertube)],
    mastodon_hosts => ['social.example.org'],
    peertube_hosts => ['video.example.org']
);

for my $pair (
    [
        'https://vimeo.com/123456/abcdef1234',
        'https://player.vimeo.com/video/123456?h=abcdef1234'
    ],
    [
        'https://player.vimeo.com/video/123456?h=abcdef1234',
        'https://player.vimeo.com/video/123456?h=abcdef1234'
    ],
    [
        'https://vimeo.com/channels/staffpicks/123456',
        'https://player.vimeo.com/video/123456'
    ],
    [
        'https://video.example.org/w/52a10666-3a18-4e73-93da-e8d3c12c305a',
'https://video.example.org/videos/embed/52a10666-3a18-4e73-93da-e8d3c12c305a'
    ],
  )
{
    is( $registry->resolve( $pair->[0] )->{embed}{url},
        $pair->[1], 'normalized allowlisted player' );
}
for my $pair (
    [
        'https://gitlab.com/group/subgroup/project/-/merge_requests/23',
        'pull_request'
    ],
    [ 'https://gitlab.com/group/project/-/issues/1',           'issue' ],
    [ 'https://codeberg.org/team/project/pulls/12',            'pull_request' ],
    [ 'https://gitlab.com/group/project/-/releases/v1.0.0',    'release' ],
    [ 'https://codeberg.org/team/project/releases/tag/v1.0.0', 'release' ],
    [ 'https://codeberg.org/team/project/commit/abcdef1234567', 'commit' ],
    [ 'https://social.example.org/@user/123456',                'post' ],
  )
{
    is( $registry->resolve( $pair->[0] )->{kind},
        $pair->[1], 'recognizes resource type' );
}
for my $bad (
    'https://vimeo.com.evil.test/123',
    'https://player.vimeo.com/video/123?h=abcdef1234&h=0000000000',
    'https://other.example.org/@user/123',
    'https://other.example.org/w/52a10666-3a18-4e73-93da-e8d3c12c305a',
    'https://gitlab.com/a/../b',
    'https://codeberg.org/a/b/raw/main/secret',
    'https://codeberg.org/a/b/merge_requests/1',
    'https://gitlab.com/a/b/-/pulls/1'
  )
{
    ok(
        !defined $registry->resolve($bad),
        'spoofs and unsupported paths fail closed'
    );
}
my $revoked_instance =
  GPForum::Service::Integration::Registry->new( enabled => ['peertube'] );
is_deeply( $revoked_instance->frame_origins, [],
'removing every authorized instance disables a saved provider choice without breaking startup'
);
my $new_instance = GPForum::Service::Integration::Registry->new(
    enabled        => ['peertube'],
    peertube_hosts => ['other.example.org']
);
my $old_instance = GPForum::Service::Integration::Registry->new(
    enabled        => ['peertube'],
    peertube_hosts => ['video.example.org']
);
isnt(
    $new_instance->cache_variant,
    $old_instance->cache_variant,
    'instance origin policy changes invalidate cached cards'
);
my $link_only = GPForum::Service::Integration::Registry->new(
    enabled => ['vimeo'],
    modes   => { vimeo => 'link' }
);
ok( !exists $link_only->resolve('https://vimeo.com/123')->{embed},
    'link-only policy removes player' );
my $parser = GPForum::Service::Integration::FeedParser->new;
my $rss    = $parser->parse(
'<rss version="2.0"><channel><item><guid>stable</guid><title>A &amp; B</title><link>https://example.org/a</link><description><![CDATA[<script>alert(1)</script>]]></description></item></channel></rss>'
);
is( $rss->[0]{title}, 'A & B', 'RSS title is plain decoded text' );
is_deeply(
    [ sort keys %{ $rss->[0] } ],
    [qw(identity_hash title url url_hash)],
    'no remote HTML or metadata can enter publication'
);
my $atom = $parser->parse(
'<feed xmlns="http://www.w3.org/2005/Atom"><entry><id>stable</id><title>Second</title><link rel="self" href="https://example.org/wrong"/><link rel="alternate" href="https://example.org/a"/></entry></feed>'
);
is(
    $atom->[0]{url_hash},
    $rss->[0]{url_hash},
    'same canonical URL deduplicates across formats'
);

for my $invalid (
    '<!DOCTYPE rss [<!ENTITY x SYSTEM "file:///etc/passwd">]><rss/>',
    '<html><body>not a feed</body></html>' )
{
    throws_ok { $parser->parse($invalid) } qr/(?:syndication|document)/msx,
      'invalid XML forms refused';
}
my $huge =
  '<rss><channel>'
  . ( '<item><title>A</title><link>https://example.org/a</link></item>' x
      $EXCESS_CANDIDATES )
  . '</channel></rss>';
is( scalar @{ $parser->parse($huge) },
    $MAX_CANDIDATES, 'feed candidate count is capped' );
my $http = GPForum::Service::Integration::HttpClient->new;
for my $ip (
    qw(127.0.0.1 10.0.0.1 172.16.0.1 192.168.1.1 169.254.169.254 100.64.0.1 198.18.0.1 203.0.113.1 224.0.0.1 0.1.2.3)
  )
{
    ok( !$http->public_ipv4($ip), 'reserved or private network refused' );
}
ok( $http->public_ipv4('1.1.1.1'), 'public network accepted' );
for my $url (
    'http://example.org',        'https://127.0.0.1/a',
    'https://example.org:8443/', 'https://user:secret@example.org/',
    'https://example.org/#fragment'
  )
{
    throws_ok { $http->https_url($url) } qr/HTTPS/msx,
      'unsafe outbound endpoint refused';
}
for my $addresses ( ['127.0.0.1'], [ '1.1.1.1', '169.254.169.254' ] ) {
    my $resolver =
      GPForum::Test::IntegrationResolver->new( addresses => $addresses );
    my $client =
      GPForum::Service::Integration::HttpClient->new( resolver => $resolver );
    throws_ok { $client->request( 'GET', 'https://example.org/feed' ) }
    qr/no[ ]permitted[ ]public[ ]address/msx,
      'private and mixed DNS answers cannot enter HTTP transport';
    is_deeply(
        $resolver->queries,
        [ [ 'example.org.', 'A' ] ],
        'DNS request is absolute and excludes search domains'
    );
}
my $offline = GPForum::Service::Integration::HttpClient->new(
    resolver => GPForum::Test::IntegrationResolver->new( unavailable => 1 ) );
throws_ok { $offline->request( 'GET', 'https://example.org/feed' ) }
qr/DNS[ ]unavailable/msx, 'DNS outage cannot bypass endpoint checks';

my $agent     = GPForum::Test::IntegrationUserAgent->new;
my $transport = GPForum::Service::Integration::HttpClient->new( resolver =>
      GPForum::Test::IntegrationResolver->new( addresses => ['1.1.1.1'] ) );
with_replaced_subs(
    'Mojo::UserAgent',
    { new => sub { return $agent; } },
    sub {
        local $ENV{MOJO_PROXY} = 1;
        local $ENV{HTTPS_PROXY} =
          'http://proxy-user:proxy-password@proxy.example.org:8080';
        $transport->request( 'POST', 'https://example.org/webhook',
            { json => { content => 'safe content' } } );
        my $transaction = $agent->captured;
        is_deeply(
            $transaction->req->json,
            { content => 'safe content' },
            'JSON payload reaches the real HTTP transaction'
        );
        is( $transaction->req->url->host,
            'example.org', 'original HTTP hostname is preserved' );
        is_deeply(
            [ $agent->transactor->peer($transaction) ],
            [ 'https', '1.1.1.1', $HTTPS_PORT ],
            'checked DNS peer is pinned with TLS and standard port'
        );
        ok( !defined $transaction->req->proxy,
            'process proxy credentials cannot enter the request' );
        is( $agent->tls_options->{SSL_verifycn_name},
            'example.org',
            'certificate identity remains the original hostname' );
        $transport->request( 'POST', 'https://example.org/token',
            { form => { code => 'one-use-code', code_verifier => 'verifier' } }
        );
        like( $agent->captured->req->body,
            qr/code=one-use-code/msx, 'OIDC form payload is serialized' );
    }
);
my $disabled = GPForum::Service::Identity::OpenID->new(
    schema        => {},
    config        => GPForum::Config->new,
    second_factor => {}
);
throws_ok { $disabled->begin } qr/external[ ]login[ ]is[ ]disabled/msx,
  'unconfigured external login cannot start';

my $config = GPForum::Config->new(
    oidc_issuer            => 'https://login.example.org',
    oidc_client_id         => 'forum',
    oidc_signing_algorithm => 'RS256'
);
my $oidc = GPForum::Service::Identity::OpenID->new(
    schema        => {},
    config        => $config,
    second_factor => {}
);
my $rsa    = Crypt::PK::RSA->new->generate_key( $RSA_KEY_BYTES, $RSA_EXPONENT );
my $public = $rsa->export_key_jwk( 'public', 1 );
$public->{kid} = 'test';
my $keys   = { keys => [$public] };
my $claims = {
    iss   => 'https://login.example.org',
    aud   => 'forum',
    sub   => 'stable-subject',
    nonce => 'test-nonce',
    iat   => time,
    exp   => time + $TOKEN_SECONDS
};
my $sign = sub ( $payload, $algorithm = 'RS256' ) {
    return encode_jwt(
        payload       => $payload,
        key           => $rsa,
        alg           => $algorithm,
        extra_headers => { kid => 'test' }
    );
};
is( $oidc->verify_id_token( $sign->($claims), $keys, 'test-nonce' )->{sub},
    'stable-subject', 'real RSA signature and pinned claims verify' );
for my $change (
    { nonce => 'other' },
    { iss   => 'https://evil.example.org' },
    { aud   => 'another-client' },
    { exp   => time - $MAX_CANDIDATES },
    { aud   => [ 'forum', 'other' ] },
    { azp   => 'other' },
    { sub   => q{} }
  )
{
    throws_ok {
        $oidc->verify_id_token( $sign->( { %{$claims}, %{$change} } ),
            $keys, 'test-nonce' )
    }
    qr/./msx, 'incorrect identity claim rejected';
}
throws_ok { $oidc->verify_id_token( $sign->($claims), $keys, 'test-nonce', 1 ) }
qr/recent/msx, 'linking requires recent external authentication';
lives_ok {
    $oidc->verify_id_token( $sign->( { %{$claims}, auth_time => time } ),
        $keys, 'test-nonce', 1 )
}
'recent provider authentication can link';
my $unsigned = encode_jwt( payload => $claims, alg => 'none', allow_none => 1 );
throws_ok { $oidc->verify_id_token( $unsigned, $keys, 'test-nonce' ) } qr/./msx,
  'unsigned identity tokens refused';
my $parts       = $sign->($claims);
my $replacement = substr( $parts, $SIGNATURE_OFFSET, 1 ) eq 'A' ? 'B' : 'A';
substr $parts, $SIGNATURE_OFFSET, 1, $replacement;
throws_ok { $oidc->verify_id_token( $parts, $keys, 'test-nonce' ) } qr/./msx,
  'altered signature refused';
done_testing;

1;
