# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use Test::Exception;
use GPForum::Config;
use GPForum::Service::Integration::Readiness;
use GPForum::Service::Integration::Registry;
use GPForum::ViewModel::Admin::IntegrationOverview;
our $VERSION = '0.001';
use Const::Fast;
const my $TOKEN_LENGTH => 40;
my $config = GPForum::Config->new;
my $ready  = 'GPForum::Service::Integration::Readiness';
is_deeply(
    $ready->missing( 'discord', $config ),
    [qw(discord_webhook public_base_url)],
    'Discord reports each missing prerequisite without values'
);
is_deeply(
    $ready->missing( 'feeds', $config ),
    ['syndication_sources'],
    'feeds require an authorized source'
);
my $registry = GPForum::Service::Integration::Registry->new;
my $page = GPForum::ViewModel::Admin::IntegrationOverview->new->page( $config,
    $registry, 1 );
my ($openid) = grep { $_->{id} eq 'openid' } @{ $page->{network} };
ok( !$openid->{configured},
    'partial OpenID configuration is never advertised as ready' );

for my $field ( @{ $openid->{missing} } ) {
    like(
        $field,
        qr/\A(?:oidc_[[:lower:]_]+|public_base_url)\z/msx,
        'the view receives setting names only'
    );
}
my @before = @{ $ready->missing( 'openid', $config ) };
$config->oidc_issuer('https://login.example.org');
my @after = @{ $ready->missing( 'openid', $config ) };
cmp_ok(
    scalar @after,
    '<',
    scalar @before,
    'the setup checklist follows individual configuration changes'
);
$config->public_base_url('https://forum.example.org');
$config->discord_webhook( 'https://discord.com/api/webhooks/123456789012345678/'
      . ( 'A' x $TOKEN_LENGTH ) );
is_deeply(
    $ready->missing( 'discord', $config ),
    [],
    'valid canonical HTTPS plus a configured webhook meets local prerequisites'
);

for my $url (
    'http://forum.example.org',       'https://127.0.0.1',
    'https://forum.example.org:8443', 'https://forum.internal'
  )
{
    $config->public_base_url($url);
    is_deeply( $ready->missing( 'discord', $config ),
        ['public_base_url'], 'readiness uses the actual outbound URL policy' );
}
throws_ok { $ready->missing( 'unknown', $config ) }
qr/Unknown[ ]integration/msx, 'unknown readiness types are refused';
done_testing;
1;
