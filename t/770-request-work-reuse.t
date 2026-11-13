# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use Test::More;
use Test::Fatal qw(exception);
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Config;
use GPForum::Runtime;
use Mojo::Promise;
use GPForum::Service::Admin::Configuration;
use GPForum::Service::Integration::Registry;
use GPForum::Service::Integration::Spotify;
use GPForum::Test::MigrationSchema;
use GPForum::Test::ForumWebServices;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';
const my $NEXT_REVISION => 2;
const my $HTTP_OK       => 200;
const my $KEY_LENGTH    => 64;

subtest 'plugin metadata is shared, policy and untrusted results are not' =>
  sub {
    my $valid_manifest = GPForum::Service::Plugin::Contract->can('manifest_v1');
    my $valid_response = GPForum::Service::Plugin::Contract->can('response_v1');
    my ( $manifests, $responses ) = ( 0, 0 );
    with_replaced_subs(
        'GPForum::Service::Plugin::Contract',
        {
            manifest_v1 => sub { ++$manifests; return $valid_manifest->(@_); },
            response_v1 => sub { ++$responses; return $valid_response->(@_); },
        },
        sub {
            my $base = GPForum::Service::Integration::Registry->new(
                providers => [ GPForum::Service::Integration::Spotify->new ],
                enabled   => ['spotify'],
            );
            $base->active;
            my $enabled = ['spotify'];
            my $modes   = { spotify => 'embed' };
            my $first   = $base->configured(
                {
                    enabled                => $enabled,
                    modes                  => $modes,
                    configuration_revision => 1
                }
            );
            my $variant = $first->cache_variant;
            is( $first->cache_variant, $variant,
                'repeat reads use the same variant' );
            $enabled->[0] = 'none';
            $modes->{spotify} = 'link';
            is_deeply(
                $first->frame_origins,
                ['https://open.spotify.com'],
                'caller mutations cannot change a policy snapshot'
            );
            ok(
                exception { $first->modes->{spotify} = 'link' },
                'the selected policy itself is immutable'
            );
            ok(
                exception { $first->configuration_revision($NEXT_REVISION) },
                'its revision cannot diverge from its cache variant'
            );
            ok(
                exception { $first->active( [] ) },
                'the active provider list cannot be replaced after activation'
            );
            ok( exception { $first->manifests( {} ) },
                'a selected registry cannot swap in unvalidated metadata' );
            ok( exception { $first->providers( [] ) },
                'the provider set cannot diverge from the validated metadata' );
            my $next = $base->configured(
                {
                    enabled                => ['spotify'],
                    modes                  => { spotify => 'link' },
                    configuration_revision => $NEXT_REVISION
                }
            );
            isnt( $next->cache_variant, $variant,
                'a new revision gets a new body-cache variant' );
            is_deeply( $next->frame_origins, [],
                'link-only mode immediately removes frame permission' );
            my $off = $base->configured(
                { enabled => [], configuration_revision => $NEXT_REVISION } );
            is_deeply( $off->active, [],
                'disabling a plugin takes effect on the next selection' );
            is( $manifests, 1,
                'provider manifests are validated once, not once per request' );
            my $manifest =
              $base->manifests->{'GPForum::Service::Integration::Spotify'};
            ok( exception { $manifest->{frame_hosts}[0] = 'evil.example' },
                'a validated origin cannot be replaced' );
            ok(
                exception { push @{ $manifest->{frame_hosts} },
                    'evil.example' },
                'a validated origin list cannot be expanded'
            );
            my $url = 'https://open.spotify.com/track/0Lr4kGOYn9l83EjuK6cZFQ';
            ok( $first->resolve($url), 'the first result is accepted' );
            ok( $first->resolve($url),
                'the next result is independently accepted' );
            is( $responses, 2,
                'every provider response still crosses the validator' );
            my $resolve =
              GPForum::Service::Integration::Spotify->can('resolve_link_v1');
            with_replaced_subs(
                'GPForum::Service::Integration::Spotify',
                {
                    resolve_link_v1 => sub {
                        my $result = $resolve->(@_);
                        $result->{embed}{url} = 'https://evil.example/player';
                        return $result;
                    },
                },
                sub {
                    ok(
                        !defined $first->resolve($url),
'an unsafe later response is refused even after a valid one'
                    );
                }
            );
            ok(
                exception { $base->configured( { providers => [] } ) },
                'configuration data cannot replace the validated providers'
            );
            my $copy = $base->catalogue;
            $copy->[0]{frame_hosts}[0] = 'evil.example';
            is_deeply( $first->frame_origins, ['https://open.spotify.com'],
                'editing a catalogue response does not poison shared metadata'
            );
        }
    );
  };

subtest
  'effective configuration is bounded, request-local and revision checked' =>
  sub {
    my $base = GPForum::Config->from_environment(
        {
            GPFORUM_ENV            => 'test',
            GPFORUM_SESSION_SECRET => 'a' x $KEY_LENGTH
        }
    );
    my $schema = GPForum::Test::MigrationSchema->new;
    my $cache  = {};
    my $make   = sub ( $state, %options ) {
        return GPForum::Service::Admin::Configuration->new(
            schema          => $schema,
            base_config     => $base,
            effective_cache => $cache,
            state           => $state,
            %options
        );
    };
    my $state = {
        available => 1,
        revision  => 1,
        settings  => { general => { GPFORUM_SITE_NAME => 'First forum' } }
    };
    my $build =
      GPForum::Service::Admin::Configuration->can('_effective_config');
    my $built = 0;
    with_replaced_subs(
        'GPForum::Service::Admin::Configuration',
        {
            _effective_config => sub { ++$built; return $build->(@_); },
        },
        sub {
            my $first = $make->($state)->effective_config;
            is( $first->site_name, 'First forum',
                'saved settings are applied' );
            $first->site_name('Request-local change');
            push @{ $first->integration_plugins }, 'request-only';
            my $again = $make->($state)->effective_config;
            is( $again->site_name, 'First forum',
                'a request cannot mutate the cached config' );
            ok(
                !(
                    grep { $_ eq 'request-only' }
                    @{ $again->integration_plugins }
                ),
                'list settings are also detached per request'
            );
            is( $built, 1, 'the same revision is validated once' );
            my $changed = {
                available => 1,
                revision  => $NEXT_REVISION,
                settings  =>
                  { general => { GPFORUM_SITE_NAME => 'Changed forum' } }
            };
            is(
                $make->($changed)->effective_config->site_name,
                'Changed forum',
                'a newer durable revision takes effect immediately'
            );
            is( $built, 2, 'the new revision is validated' );
            my $other = GPForum::Test::MigrationSchema->new;
            is(
                $make->( $state, schema => $other )
                  ->effective_config->site_name,
                'First forum',
                'a shared slot never confuses database instances'
            );
            is(
                $built,
                $NEXT_REVISION + 1,
                'another schema cannot use the cached result'
            );
            is(
                $make->( { available => 0, revision => 1, settings => {} } )
                  ->effective_config->site_name,
                $base->site_name,
                'database failure cannot serve cached administrative overrides'
            );
            is_deeply( $cache, {},
                'failure also discards the saved cache entry' );
            is( $make->($state)->effective_config->site_name,
                'First forum',
                'recovery reads and rebuilds the configuration' );
            my $replacement = GPForum::Config->from_environment(
                {
                    GPFORUM_ENV            => 'test',
                    GPFORUM_DEFAULT_LOCALE => 'it',
                    GPFORUM_SESSION_SECRET => 'b' x $KEY_LENGTH,
                }
            );
            my $changed_installation =
              $make->( $state, base_config => $replacement )->effective_config;
            is( $changed_installation->default_locale,
                'it',
                'a replacement installation cannot inherit cached defaults' );
            is(
                $changed_installation->session_secret,
                'b' x $KEY_LENGTH,
                'a replacement key set cannot inherit cached signing material'
            );
            my $bad = {
                available => 1,
                revision  => $NEXT_REVISION,
                settings  =>
                  { general => { GPFORUM_DEFAULT_LOCALE => 'not-a-locale' } }
            };
            ok(
                exception { $make->($bad)->effective_config },
                'an invalid new configuration still fails validation'
            );
            is_deeply( $cache, {},
                'a failed build cannot leave a stale fallback' );
        }
    );
    my $secret_store = $make->($state);
    my ($sealed) = $secret_store->box->seal( 'fixture-smtp-secret',
        'admin-setting:GPFORUM_SMTP_PASSWORD' );
    my $secrets = {
        available => 1,
        revision  => 1,
        settings  => { general => { GPFORUM_SMTP_PASSWORD => $sealed } }
    };
    is( $make->($secrets)->effective_config->smtp_password,
        'fixture-smtp-secret',
        'saved secrets can be opened under the installation key' );
    is_deeply( $cache, {},
        'saved credentials never leave decrypted values in the reusable slot' );
    my $rotated = GPForum::Config->from_environment(
        {
            GPFORUM_ENV            => 'test',
            GPFORUM_SESSION_SECRET => 'b' x $KEY_LENGTH
        }
    );
    is(
        $make->( $secrets, base_config => $rotated )
          ->effective_config->smtp_password,
        q{},
        'a changed key set cannot reuse a decrypted cached secret'
    );
  };

# The home answers its data only: runtime diagnostics stay on /health
# behind the operations token, and no home request probes the OS (ADR 0026).
subtest 'neither home HTML nor JSON probes the operating system' => sub {
    my $calls = 0;
    with_replaced_subs(
        'GPForum::Runtime',
        {
            as_hash   => sub { ++$calls; return { web_processes => 1 }; },
            as_hash_p => sub {
                ++$calls;
                return Mojo::Promise->resolve( { web_processes => 1 } );
            },
        },
        sub {
            my $test = Test::Mojo->new('GPForum');
            $test->app->helper(
                gp_home_page_reader => sub {
                    return GPForum::Test::ForumWebServices->new;
                }
            );
            $calls = 0;
            $test->get_ok(q{/})->status_is($HTTP_OK);
            $test->get_ok('/?format=json')->status_is($HTTP_OK);
            $test->json_has('/home')->json_hasnt('/runtime');
            $test->get_ok( q{/} => { Accept => 'application/json' } )
              ->status_is($HTTP_OK)
              ->json_hasnt('/runtime');
            is( $calls, 0, 'no home request probes the operating system' );
        }
    );
};

done_testing();
1;
