# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::Registry;

use Const::Fast;
use Digest::SHA qw(sha256_hex);
use Hash::Util  qw(lock_hashref);
use List::Util  qw(any);
use GPForum::Service::Integration::Facebook;
use GPForum::Service::Integration::Instagram;
use GPForum::Service::Integration::Spotify;
use GPForum::Service::Integration::SourceLinks;
use GPForum::Service::Integration::AppleMusic;
use GPForum::Service::Plugin::Contract;
use GPForum::Service::Integration::GitHub;
use GPForum::Service::Integration::YouTube;
use GPForum::Service::Integration::Vimeo;
use GPForum::Service::Integration::GitLab;
use GPForum::Service::Integration::Codeberg;
use GPForum::Service::Integration::Mastodon;
use GPForum::Service::Integration::PeerTube;

use GPForum::Service::Integration::Wikipedia;
use GPForum::Service::Integration::Mathematics;
use GPForum::X::Argument;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my $MAX_CARDS => 5;

has enabled                => sub { return []; };
has modes                  => sub { return {}; };
has configuration_revision => 0;
has logger         => undef; # optional: direct offline callers may omit logging
has mastodon_hosts => sub { return []; };
has peertube_hosts => sub { return []; };
has providers      => sub ($self) {
    return [
        GPForum::Service::Integration::YouTube->new,
        GPForum::Service::Integration::Vimeo->new,
        GPForum::Service::Integration::GitLab->new,
        GPForum::Service::Integration::Codeberg->new,
        (
            @{ $self->mastodon_hosts }
            ? (
                GPForum::Service::Integration::Mastodon->new(
                    hosts => $self->mastodon_hosts
                )
              )
            : ()
        ),
        (
            @{ $self->peertube_hosts }
            ? (
                GPForum::Service::Integration::PeerTube->new(
                    hosts => $self->peertube_hosts
                )
              )
            : ()
        ),
        GPForum::Service::Integration::GitHub->new,
        GPForum::Service::Integration::Facebook->new,
        GPForum::Service::Integration::Instagram->new,
        GPForum::Service::Integration::Spotify->new,
        GPForum::Service::Integration::AppleMusic->new,
        GPForum::Service::Integration::Wikipedia->new,
        GPForum::Service::Integration::Mathematics->new,
    ];
};
has contract  => sub { return GPForum::Service::Plugin::Contract->new; };
has manifests => sub ($self) { return $self->_manifests; };
has _source_links =>
  sub { return GPForum::Service::Integration::SourceLinks->new; };
has _variant  => sub ($self) { return $self->_variant_value; };
has _has_math => sub ($self) {
    return any {
        my $provider = $_;
        any { $_ eq 'math.render.v1' }
          @{ $self->manifests->{ ref $provider }{capabilities} }
    } @{ $self->active };
};

sub active ($self) {
    $self->{active} //= $self->_activate;
    return $self->{active};
}

# A request gets a new selection from its freshly read configuration. Only
# the validated provider catalogue and policy-independent source scanner are shared.
sub configured ( $self, $input ) {
    my %options = %{$input};
    my %allowed = map { $_ => 1 } qw(enabled modes configuration_revision);
    if ( any { !$allowed{$_} } keys %options ) {
        GPForum::X::Argument->throw(
            message => 'unknown integration selection field' );
    }
    return ref($self)->new(
        %options,
        providers     => $self->providers,
        manifests     => $self->manifests,
        contract      => $self->contract,
        logger        => $self->logger,
        _source_links => $self->_source_links,
    );
}

sub frame_origins ($self) {
    my %origins;
    for my $provider ( @{ $self->active } ) {
        next
          if ( $self->modes->{ $self->manifests->{ ref $provider }{id} }
            // q{} ) eq 'link';
        for my $host ( @{ $self->manifests->{ ref $provider }{frame_hosts} } ) {
            $origins{"https://$host"} = 1;
        }
    }
    return [ sort keys %origins ];
}

sub cache_variant ($self) {
    return $self->_variant;
}

sub _variant_value ($self) {
    my @versions;
    for my $provider ( @{ $self->active } ) {
        my $manifest     = $self->manifests->{ ref $provider };
        my $url_policy   = join q{,}, @{ $manifest->{url_hosts} };
        my $frame_policy = join q{,}, @{ $manifest->{frame_hosts} };
        my $policy       = sha256_hex( $url_policy . q{|} . $frame_policy );
        push @versions,
            $manifest->{id} . q{=}
          . $manifest->{version} . q{@}
          . ( $self->modes->{ $manifest->{id} } // 'embed' ) . q{#}
          . $policy;
    }
    return join q{:}, 'integrations-v1', $self->configuration_revision,
      @versions;
}

sub catalogue ($self) {
    my %enabled = map { $_ => 1 } @{ $self->enabled };
    my @catalogue;
    for my $provider ( @{ $self->providers } ) {
        my $manifest = $self->manifests->{ ref $provider };
        my $copy     = $self->contract->manifest_v1($manifest);
        push @catalogue,
          {
            %{$copy},
            enabled        => $enabled{ $manifest->{id} }   ? 1 : 0,
            supports_embed => @{ $manifest->{frame_hosts} } ? 1 : 0,
            supports_math  =>
              ( any { $_ eq 'math.render.v1' } @{ $manifest->{capabilities} } )
            ? 1
            : 0,
            mode => $self->modes->{ $manifest->{id} }
              // ( @{ $manifest->{frame_hosts} } ? 'embed' : 'link' )
          };
    }
    return \@catalogue;
}

sub _manifests ($self) {
    my ( %manifests, %ids );
    for my $provider ( @{ $self->providers } ) {
        if ( !$provider->can('manifest_v1') ) {
            GPForum::X::Argument->throw(
                message => 'incompatible integration plugin API' );
        }
        my $manifest = $self->contract->manifest_v1( $provider->manifest_v1 );
        my $method =
          ( any { $_ eq 'math.render.v1' } @{ $manifest->{capabilities} } )
          ? 'prepare_math_v1'
          : 'resolve_link_v1';
        if ( !$provider->can($method) ) {
            GPForum::X::Argument->throw(
                message => 'incompatible integration plugin API' );
        }
        if ( $ids{ $manifest->{id} }++ ) {
            GPForum::X::Argument->throw(
                message => 'duplicate integration plugin id' );
        }
        for my $name (qw(capabilities url_hosts frame_hosts)) {
            _readonly_array( $manifest->{$name} );
        }
        lock_hashref($manifest);
        $manifests{ ref $provider } = $manifest;
    }
    lock_hashref( \%manifests );
    return \%manifests;
}

sub math_enabled ($self) {
    return $self->_has_math;
}

sub math_spans ( $self, $source ) {
    for my $provider ( @{ $self->active } ) {
        my $manifest = $self->manifests->{ ref $provider };
        next if !any { $_ eq 'math.render.v1' } @{ $manifest->{capabilities} };
        try {
            my $request = $self->contract->math_request_v1(
                { api_version => 1, source => $source } );
            return $self->contract->math_response_v1( $manifest, $request,
                $provider->prepare_math_v1($request) )->{spans};
        }
        catch ($error) {
            if ( $self->logger ) {
                $self->logger->warn(
                    'integration plugin failed: ' . $manifest->{id} );
            }
        };
    }
    return [];
}

sub _activate ($self) {

    # Detach caller-owned arrays/hashes, then lock the selection so its CSP,
    # body-cache key and active providers cannot diverge after memoization.
    $self->{enabled}   = _readonly_array( [ @{ $self->enabled } ] );
    $self->{providers} = _readonly_array( [ @{ $self->providers } ] );
    $self->{modes}     = {
        ( map { $_->{id} => undef } values %{ $self->manifests } ),
        %{ $self->modes }
    };
    lock_hashref( $self->{modes} );
    $self->configuration_revision;
    for my $key (qw(enabled modes configuration_revision providers manifests)) {
        Internals::SvREADONLY( $self->{$key}, 1 );
    }
    my %available;
    for my $provider ( @{ $self->providers } ) {
        $available{ $self->manifests->{ ref $provider }{id} } = $provider;
    }
    my @active;
    my %seen;
    for my $id ( @{ $self->enabled } ) {
        next if $id eq 'none';
        next if $seen{$id}++;
        my $provider = $available{$id};
        next if !$provider && ( $id eq 'mastodon' || $id eq 'peertube' );
        if ( !$provider ) {
            GPForum::X::Argument->throw(
                message => "unknown integration plugin: $id" );
        }
        push @active, $provider;
    }
    return _readonly_array( \@active );
}

sub _readonly_array ($values) {
    for my $value ( @{$values} ) {
        Internals::SvREADONLY( $value, 1 );
    }
    Internals::SvREADONLY( @{$values}, 1 );
    return $values;
}

sub resolve ( $self, $raw ) {
    my ( $request, $url );
    try {
        $request =
          $self->contract->request_v1( { api_version => 1, url => $raw } );
        $url = $self->contract->https_url( $request->{url} );
    }
    catch ($error) { return undef; };
    for my $provider ( @{ $self->active } ) {
        my $manifest = $self->manifests->{ ref $provider };
        next if !any { $_ eq lc( $url->host ) } @{ $manifest->{url_hosts} };
        my $result;
        try {
            $result = $self->contract->response_v1( $manifest,
                $provider->resolve_link_v1($request) );
        }
        catch ($error) {

            # Neither the submitted URL nor provider exception may expose
            # a private post or credentials to the operational log.
            if ( $self->logger ) {
                $self->logger->warn(
                    'integration plugin failed: ' . $manifest->{id} );
            }
        };
        if ($result) {
            if ( ( $self->modes->{ $manifest->{id} } // q{} ) eq 'link' ) {
                delete $result->{embed};
            }
            if ( $result->{embed} ) {
                my $embed_url =
                  $self->contract->https_url( $result->{embed}{url} );
                $result->{embed}{origin} = 'https://' . lc( $embed_url->host );
            }
            return { %{$result}, name => $manifest->{name} };
        }
    }
    return undef;
}

sub for_source ( $self, $source ) {
    return [] if !defined $source || !@{ $self->active };
    my @cards;
    my %seen;
    for my $raw ( @{ $self->_source_links->urls($source) } ) {
        my $card = $self->resolve($raw);
        next if !$card || $seen{ $card->{url} }++;
        push @cards, $card;
        last if @cards >= $MAX_CARDS;
    }
    return \@cards;
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::Registry - Optional versioned link integration plugins.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $plugins = GPForum::Service::Integration::Registry->new(
        enabled => [qw(youtube github facebook)]);
    my $cards = $plugins->for_source($authorized_post_source);

=head1 DESCRIPTION

C<active> validates the packaged providers against contract 1 and locks the
metadata and selection. A configured request shares this validated catalogue,
not another request's enabled state, modes or revision. Cache variants and the
math capability are computed once per immutable selection.
C<catalogue> lists their version, capabilities and enabled state. C<resolve>
accepts only HTTPS URLs without credentials, on port 443, at most 2,048
characters. Each provider recognizes exact hosts and returns plain data.
Failures are logged without source data and leave the original post intact.

C<for_source> scans up to 50,000 characters of already-authorized post
source, recognizing standalone URLs and standalone Markdown links outside
code fences. It returns at most five distinct cards. Code, quotes, list
items and links embedded in a sentence do not generate cards. With every
provider disabled it returns immediately. An application-owned bounded cache
keeps only source prefixes and extracted URL candidates, including empty
results. No rendered cards or provider decisions are stored; candidates still
pass through C<resolve> on every call. Administrator changes apply on the next
request;
only deployment of new module code requires a process restart.

These are trusted, reviewed Perl modules deployed with the application,
not downloaded code or a sandbox. Providers must do bounded local parsing
only, return contract data, and perform no I/O or core state mutation.
Network-backed integrations require a separate asynchronous contract.

=head1 SUBROUTINES/METHODS

=head2 active

Returns the read-only active provider list, validating metadata and freezing
the selection on its first read. Use C<configured> for a different selection.

=head2 configured

Builds a fresh selection from C<enabled>, C<modes> and
C<configuration_revision>, sharing this registry's validated provider metadata.
Other fields are refused. A selection cannot be changed after activation;
make another selection from the next request's durable configuration instead.
Provider requests and responses are still validated on every invocation.

=head2 catalogue

Returns packaged manifests with the configured enabled state.

=head2 math_enabled

Reports whether an active module declares the fixed math.render.v1 capability.

=head2 math_spans

Validates a locked plain source request and the module's bounded, ordered
source spans. Returns an empty list on failure, logging only the provider id.

=head2 frame_origins

Returns the declared frame origins of active plugins for the core CSP policy.

=head2 cache_variant

Returns a deterministic public page cache variant naming active provider
ids and versions. Reconfiguration and upgrades cannot reuse old markup.

=head2 resolve

Returns a descriptor for a supported safe HTTPS URL, or undef. A provider
exception is logged by id and does not prevent later providers from resolving.

=head2 for_source

Returns up to five distinct cards from standalone links in authorized source.

=head1 DIAGNOSTICS

Unknown plugin ids and incompatible contracts throw L<GPForum::X::Argument>
on activation. Provider failures log only the provider id when a logger is set.

=head1 CONFIGURATION AND ENVIRONMENT

C<enabled> holds ids selected by the application's GPFORUM_INTEGRATION_PLUGINS.
C<providers> holds trusted packaged modules; C<logger> is optional.
No providers are enabled by default for direct registry construction.

=head1 DEPENDENCIES

L<Const::Fast>, L<Mojo::Base>, L<Mojo::URL>, L<GPForum::X::Argument>
and the packaged provider modules.

=head1 INCOMPATIBILITIES

Only integration contract 1 is accepted.

=head1 BUGS AND LIMITATIONS

Providers must perform bounded local parsing only. This is not a code sandbox
or a network integration dispatcher. Source matching is intentionally narrow.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
