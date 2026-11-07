# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Performance::HTTPIntegrations;
use v5.40;
use Const::Fast;
use Exporter qw(import);
use GPForum::Infrastructure::Id;
use GPForum::Performance::HTTPClient;
our $VERSION   = '0.001';
our @EXPORT_OK = qw(integration_journeys link_fixtures);
const my $PREVIEW_CARD_LIMIT => 5;

sub link_fixtures {
    return [
        [ youtube   => 'https://youtu.be/dQw4w9WgXcQ' ],
        [ vimeo     => 'https://vimeo.com/123456/abcdef1234' ],
        [ gitlab    => 'https://gitlab.com/group/project/-/issues/1' ],
        [ codeberg  => 'https://codeberg.org/team/project/pulls/12' ],
        [ github    => 'https://github.com/octocat/Hello-World/issues/42' ],
        [ facebook  => 'https://www.facebook.com/user/posts/pfbid123' ],
        [ instagram => 'https://www.instagram.com/reel/ABC123/' ],
        [ spotify => 'https://open.spotify.com/track/0Lr4kGOYn9l83EjuK6cZFQ' ],
        [
            apple_music =>
              'https://music.apple.com/it/album/example/12345?i=67890'
        ],
        [ wikipedia => 'https://it.wikipedia.org/wiki/Alan_Turing' ],
        [ mastodon  => 'https://social.example.org/@user/123456' ],
        [
            peertube =>
              'https://video.example.org/w/52a10666-3a18-4e73-93da-e8d3c12c305a'
        ],
    ];
}

sub integration_journeys {
    return [
        { name => 'plugin_probes', actor => 'admin', steps => _probes() },
        {
            name  => 'integrations_preview',
            actor => 'member',
            steps => _previews()
        },
        {
            name   => 'forum_configuration',
            actor  => 'admin',
            serial => 1,
            steps  => _configuration()
        },
    ];
}

sub _probes {
    my @steps = map {
        +{
            name     => 'plugin_resolve_' . $_->[0],
            method   => 'POST',
            path     => '/admin/plugins/probe/link',
            form     => { url => $_->[1] },
            contains => q{data-integration-provider="} . $_->[0] . q{"},
        }
    } @{ link_fixtures() };
    push @steps,
      {
        name   => 'plugin_math_probe',
        method => 'POST',
        path   => '/admin/plugins/probe/math',
        form   => {
            source =>
q{$$\begin{aligned}x&=\frac{-b\pm\sqrt{b^2-4ac}}{2a}\\A&=\begin{pmatrix}1&2\\3&4\end{pmatrix}\end{aligned}$$}
        },
        contains => 'class="math-expression"',
      };
    return \@steps;
}

sub _previews {
    my @steps = (
        {
            name => 'integration_preview_form',
            path => '/new-thread',
            save => sub ( $ctx, $res ) {
                $ctx->{integration_form} =
                  GPForum::Performance::HTTPClient::fields( $res,
                    'form[data-composer]' );
            },
        }
    );
    my @fixtures = @{ link_fixtures() };
    while (@fixtures) {
        my @group = splice @fixtures, 0, $PREVIEW_CARD_LIMIT;
        my $body  = join "\n\n", ( map { $_->[1] } @group ),
          q{$$\sum_{i=1}^{n}i=\frac{n(n+1)}{2}$$};
        my $id = $group[0][0];
        push @steps, {
            name   => "integration_preview_$id",
            method => 'POST',
            path   => '/composer/preview',
            json   => 1,
            ok     => 1,
            form   => sub ($ctx) {
                return { %{ $ctx->{integration_form} }, body_source => $body };
            },
            check => sub ( $ctx, $res ) {
                my $html = ( $res->json // {} )->{html} // q{};
                return 'preview lost equation or integration markup'
                  if index( $html, 'math-expression' ) < 0
                  || index( $html, 'data-integration-provider' ) < 0;
                return undef;
            },
        };
    }
    return \@steps;
}

sub _hidden ( $res, $selector ) {
    my $fields = GPForum::Performance::HTTPClient::fields( $res, $selector );
    return { map { $_ => $fields->{$_} } qw(csrf_token command_id revision) };
}

sub _configuration {
    my @steps = (
        {
            name => 'configuration_form',
            path => '/admin/configuration',
            save => sub ( $ctx, $res ) {
                $ctx->{configuration_form} =
                  _hidden( $res, 'form[data-admin-configuration]' );
            },
        },
        {
            name   => 'configuration_save',
            method => 'POST',
            path   => '/admin/configuration',
            json   => 1,
            status => 'ok',
            form   => sub ($ctx) {
                $ctx->{description} =
                  'HTTP benchmark ' . GPForum::Infrastructure::Id->new->uuid;
                return {
                    %{ $ctx->{configuration_form} },
                    GPFORUM_SITE_DESCRIPTION => $ctx->{description}
                };
            },
        },
        {
            name  => 'configuration_verify',
            path  => '/admin/configuration',
            check => sub ( $ctx, $res ) {
                my $field =
                  $res->dom->at('input[name="GPFORUM_SITE_DESCRIPTION"]');
                return 'saved configuration was not applied'
                  if !$field
                  || ( $field->attr('value') // q{} ) ne $ctx->{description};
                return undef;
            },
        },
        {
            name => 'plugin_policy_form',
            path => '/admin/plugins',
            save => sub ( $ctx, $res ) {
                $ctx->{plugin_form} =
                  _hidden( $res, 'form[action="/admin/plugins/wikipedia"]' );
            },
        },
    );
    for my $enabled ( 0, 1 ) {
        push @steps, {
            name   => $enabled ? 'plugin_enable' : 'plugin_disable',
            method => 'POST',
            path   => '/admin/plugins/wikipedia',
            json   => 1,
            status => 'ok',
            form   => sub ($ctx) {
                return {
                    %{ $ctx->{plugin_form} },
                    enabled => $enabled,
                    mode    => 'link'
                };
            },
          },
          {
            name => $enabled
            ? 'plugin_enabled_verify'
            : 'plugin_disabled_verify',
            path  => '/admin/plugins',
            check => sub ( $ctx, $res ) {
                my $field = $res->dom->at('input[id="enabled-wikipedia"]');
                my $checked =
                  $res->dom->at('input[id="enabled-wikipedia"][checked]')
                  ? 1
                  : 0;
                return 'plugin policy was not applied'
                  if !$field
                  || $checked != $enabled;
                return undef;
            },
            save => sub ( $ctx, $res ) {
                $ctx->{plugin_form} =
                  _hidden( $res, 'form[action="/admin/plugins/wikipedia"]' );
            },
          };
    }
    return \@steps;
}
1;
