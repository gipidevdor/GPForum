# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Admin::Configuration;

use Const::Fast;
use List::Util  qw(any);
use Digest::SHA qw(hmac_sha256_hex);
use JSON::MaybeXS;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Mojo::Promise;
use GPForum::Config;
use Mojo::Util qw(encode decode);
use GPForum::X::Config;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Identity::SecretBox;

our $VERSION = '0.001';
const my @GENERAL => qw(
  site_name site_description default_locale default_theme default_timezone
  public_base_url media_max_mib attachment_owner_max_mib attachment_owner_max_pending
  media_source_hosts websub_hub_url mastodon_hosts peertube_hosts discord_webhook syndication_sources
  oidc_issuer oidc_authorization_endpoint oidc_token_endpoint oidc_jwks_uri oidc_client_id oidc_client_secret oidc_signing_algorithm
  operator_name operator_address operator_email operator_vat_number operator_register
  privacy_officer_email security_contact mail_reply_address mail_transport mail_from
  dkim_domain dkim_selector dkim_key_file smtp_host smtp_port smtp_username smtp_password smtp_tls
);
const my %SECRET => map { $_ => 1 }
  qw(smtp_username smtp_password discord_webhook oidc_client_secret);
const my @SECRET_ENV => map { $_->{env} }
  grep { exists $SECRET{ $_->{name} } } @{ GPForum::Config->settings };
const my %LIVE => map { $_ => 1 }
  qw(site_name site_description default_locale default_theme default_timezone
  operator_name operator_address operator_email operator_vat_number operator_register privacy_officer_email security_contact
  mastodon_hosts peertube_hosts discord_webhook syndication_sources
  oidc_issuer oidc_authorization_endpoint oidc_token_endpoint oidc_jwks_uri oidc_client_id oidc_client_secret oidc_signing_algorithm);
const my $SECRET_LIMIT => 128;
const my %NETWORK_SECRET_LIMIT =>
  ( discord_webhook => 192, oidc_client_secret => 192 );
my $JSON = JSON::MaybeXS->new( canonical => 1, utf8 => 0 );

__PACKAGE__->requires(qw(schema base_config));
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};
has state => sub ($self) { return $self->load; };

# One replacement slot owned by the application, never a global revision
# cache. The durable state is still read once on every request.
has effective_cache => undef;       # optional: offline callers validate per use
has box             => sub ($self) {
    return GPForum::Service::Identity::SecretBox->new(
        keys => $self->base_config->signing_secrets );
};

sub load ($self) {
    my $row;
    try { $row = $self->functions->row( 'admin_configuration_state', {} ); }
    catch ($error) {
        return {
            available => 0,
            revision  => 0,
            settings  => { plugins => {}, general => {} }
        };
    };
    return {
        available          => $row ? 1 : 0,
        revision           => $row->{revision} // 0,
        public_cache_epoch => $row->{public_cache_epoch},
        settings => $row->{settings} // { plugins => {}, general => {} }
    };
}

sub load_p ( $self, $context = undef ) {
    return Mojo::Promise->resolve->then( sub { return $self->load; } )
      if !$self->functions;
    return $self->functions->row_p( 'admin_configuration_state', {}, $context )
      ->then(
        sub ($row) {
            return {
                available          => $row ? 1 : 0,
                revision           => $row->{revision} // 0,
                public_cache_epoch => $row->{public_cache_epoch},
                settings => $row->{settings} // { plugins => {}, general => {} }
            };
        }
      )->catch(
        sub {
            return {
                available => 0,
                revision  => 0,
                settings  => { plugins => {}, general => {} }
            };
        }
      );
}

sub environment ($self) {
    my %environment;
    for my $setting ( @{ GPForum::Config->settings } ) {
        my $name  = $setting->{name};
        my $value = $self->base_config->$name;
        $environment{ $setting->{env} } =
          ref $value eq 'ARRAY'
          ? join( $setting->{type} eq 'words' ? q{ } : q{,}, @{$value} )
          : $value // q{};
    }
    return \%environment;
}

sub effective_config ($self) {
    my $state = $self->state;
    my $saved = $state->{settings}{general} // {};
    my $cache = $self->_cache_slot( $state, $saved );
    if ( !keys %{$saved} || !$state->{available} ) {
        return $self->base_config;
    }
    my $cached = $self->_cached_config( $cache, $state );
    return _config_copy($cached) if $cached;
    if ($cache) { %{$cache} = (); }
    my $config = $self->_effective_config($saved);
    if ($cache) {
        %{$cache} = (
            base_config => $self->base_config,
            schema      => $self->schema,
            revision    => $state->{revision},
            config      => _config_copy($config),
        );
    }
    return $config;
}

sub _cache_slot ( $self, $state, $saved ) {
    my $cache = $self->effective_cache;
    return undef if !$cache;

    # Saved credentials keep their original per-request opening/lifetime.
    # Never retain their decrypted values in a worker's reusable prototype.
    if (   !$state->{available}
        || !keys %{$saved}
        || !defined $state->{revision}
        || any { exists $saved->{$_} } @SECRET_ENV )
    {
        %{$cache} = ();
        return undef;
    }
    return $cache;
}

sub _cached_config ( $self, $cache, $state ) {
    return undef if !$cache || !$cache->{config};
    return undef
      if refaddr( $cache->{base_config} ) != refaddr( $self->base_config )
      || refaddr( $cache->{schema} ) != refaddr( $self->schema )
      || $cache->{revision} ne $state->{revision};
    return $cache->{config};
}

# Controllers get their own object and list values. A request must not be
# able to alter the validated prototype used by the following request.
sub _config_copy ($config) {
    return ref($config)->new(
        map {
            $_ => ref $config->{$_} eq 'ARRAY'
              ? [ @{ $config->{$_} } ]
              : $config->{$_}
        } keys %{$config}
    );
}

sub _effective_config ( $self, $saved ) {
    my $environment           = $self->environment;
    my $network_secret_failed = 0;
    for my $setting ( @{ $self->fields } ) {
        my $env = $setting->{env};
        next if !exists $saved->{$env};
        my $value = $saved->{$env};
        if ( $setting->{secret} ) {
            $value = $self->_open_secret( $value, $env );
            if ( !defined $value ) {
                if ( exists $NETWORK_SECRET_LIMIT{ $setting->{name} } ) {
                    $network_secret_failed = 1;
                }
                next;
            }
        }
        $environment->{$env} = $value;
    }
    if ($network_secret_failed) {
        $environment->{GPFORUM_DISCORD_WEBHOOK}    = q{};
        $environment->{GPFORUM_OIDC_ISSUER}        = q{};
        $environment->{GPFORUM_OIDC_CLIENT_SECRET} = q{};
    }
    return GPForum::Config->from_environment($environment);
}

sub fields ($self) {
    my %settings = map { $_->{name} => $_ } @{ GPForum::Config->settings };
    my @fields;
    for my $name (@GENERAL) {
        push @fields,
          {
            %{ $settings{$name} },
            secret            => exists $SECRET{$name} ? 1 : 0,
            secret_max_length => exists $NETWORK_SECRET_LIMIT{$name}
            ? $NETWORK_SECRET_LIMIT{$name}
            : $SECRET_LIMIT,
            live => exists $LIVE{$name} ? 1 : 0
          };
    }
    return \@fields;
}

sub general_page ($self) {
    my $effective = $self->effective_config;
    my %groups;
    for my $field ( @{ $self->fields } ) {
        my $name  = $field->{name};
        my $value = $effective->$name;
        my $text =
          ref $value eq 'ARRAY'
          ? join( $field->{type} eq 'words' ? q{ } : q{,}, @{$value} )
          : $value // q{};
        my $saved = $self->state->{settings}{general};
        push @{ $groups{ $field->{section} } },
          {
            %{$field},
            value => $field->{secret} ? q{} : $text,
            configured => length($text) ? 1 : 0,
            overridden => exists $saved->{ $field->{env} } ? 1 : 0,
            input_type => $field->{type} eq 'integer' ? 'number'
            : $name =~ /email\z/msx                                   ? 'email'
            : $name eq 'public_base_url' || $name eq 'websub_hub_url' ? 'url'
            :                                                           'text',
          };
    }
    return {
        revision  => $self->state->{revision},
        available => $self->state->{available},
        groups    =>
          [ map { +{ name => $_, fields => $groups{$_} } } sort keys %groups ]
    };
}

sub save_general ( $self, $input ) {
    my @invalid;
    my $prepared = $self->_general_values( $input, \@invalid );
    return { status => 'invalid', error_fields => \@invalid } if !$prepared;
    my $candidate = $self->_candidate( $prepared, $input );
    try { GPForum::Config->from_environment($candidate); }
    catch ($error) {
        my $problems = GPForum::X::Config->caught($error);
        return {
            status       => 'invalid',
            error_fields => $problems
            ? [ map { $_->{variable} } @{ $problems->problems } ]
            : []
        };
    };
    my $sealed = $self->_seal_general( $prepared, $input );
    return { status => 'unavailable' } if !$sealed;
    return $self->_write(
        {
            %{$input},
            section      => 'general',
            key          => '__all__',
            operation    => 'set',
            value        => $sealed,
            request_hash => $self->_request_hash($input)
        }
    );
}

sub _general_values ( $self, $input, $invalid ) {
    my %allowed = map { $_->{env} => $_ } @{ $self->fields };
    return undef if ref $input->{values} ne 'HASH';
    return undef if any { !exists $allowed{$_} } keys %{ $input->{values} };
    my %saved = %{ $self->state->{settings}{general} // {} };
    for my $env ( keys %{ $input->{values} } ) {
        my $field = $allowed{$env};
        my $value = $input->{values}{$env};
        if ( !defined $value || ref $value ) {
            push @{$invalid}, $env;
            return undef;
        }
        if ( ( $field->{check} // q{} ) eq 'required' && $value !~ /\S/msx ) {
            push @{$invalid}, $env;
            return undef;
        }
        next if $field->{secret} && !length $value;
        if ( $field->{secret}
            && length( encode( 'UTF-8', $value ) ) >
            $field->{secret_max_length} )
        {
            push @{$invalid}, $env;
            return undef;
        }
        $saved{$env} = $value;
    }
    return \%saved;
}

sub _candidate ( $self, $saved, $input ) {
    my %allowed   = map { $_->{env} => $_ } @{ $self->fields };
    my $candidate = $self->environment;
    for my $env ( keys %{$saved} ) {
        if ( $allowed{$env}{secret}
            && !length( $input->{values}{$env} // q{} ) )
        {
            $candidate->{$env} = $self->_open_secret( $saved->{$env}, $env )
              // q{};
        }
        else { $candidate->{$env} = $saved->{$env}; }
    }
    return $candidate;
}

sub _seal_general ( $self, $saved, $input ) {
    my %sealed = %{$saved};
    for my $field ( @{ $self->fields } ) {
        my $env = $field->{env};
        next if !$field->{secret} || !length( $input->{values}{$env} // q{} );
        return undef if !$self->box->available;
        ( $sealed{$env} ) = $self->box->seal( encode( 'UTF-8', $saved->{$env} ),
            "admin-setting:$env" );
    }
    return \%sealed;
}

sub save_plugin ( $self, $input ) {
    return { status => 'invalid' }
      if ( $input->{enabled} // q{} ) !~ /\A [01] \z/msx;
    return { status => 'invalid' }
      if ( $input->{mode} // q{} ) ne 'link'
      && ( $input->{mode} // q{} ) ne 'embed';
    my $value = {
        enabled => $input->{enabled}
        ? $JSON->decode('true')
        : $JSON->decode('false'),
        mode => $input->{mode}
    };
    return $self->_write(
        {
            %{$input},
            section      => 'plugins',
            key          => $input->{plugin},
            operation    => 'set',
            value        => $value,
            request_hash => $self->_request_hash($input)
        }
    );
}

sub reset_general ( $self, $input ) {
    my %allowed = map { $_->{env} => 1 } @{ $self->fields };
    return { status => 'invalid' } if !exists $allowed{ $input->{key} // q{} };
    my %general = %{ $self->state->{settings}{general} // {} };
    delete $general{ $input->{key} };
    try {
        __PACKAGE__->new(
            schema      => $self->schema,
            base_config => $self->base_config,
            state       => {
                %{ $self->state },
                settings =>
                  { %{ $self->state->{settings} }, general => \%general }
            }
        )->effective_config;
    }
    catch ($error) { return { status => 'invalid' }; };
    return $self->_write(
        {
            %{$input},
            section      => 'general',
            operation    => 'reset',
            value        => q{},
            request_hash => $self->_request_hash($input)
        }
    );
}

sub _open_secret ( $self, $sealed, $env ) {
    my $bytes = $self->box->unseal( $sealed, "admin-setting:$env" );
    return defined $bytes ? decode( 'UTF-8', $bytes ) : undef;
}

sub _request_hash ( $self, $input ) {
    return hmac_sha256_hex( encode( 'UTF-8', $JSON->encode($input) ),
        encode( 'UTF-8', $self->base_config->session_secret ) );
}

sub _write ( $self, $input ) {
    return { status => 'invalid' }
      if !GPForum::Infrastructure::Id->is_uuid( $input->{command} );
    return { status => 'invalid' }
      if ( $input->{expected} // q{} ) !~ /\A [[:digit:]]{1,18} \z/amsx;
    my %values = map { $_ => $input->{$_} }
      qw(actor command expected section key operation request_hash);
    $values{value} =
      ref $input->{value} ? $input->{value} : $JSON->encode( $input->{value} );
    my $row;
    try {
        $row = $self->functions->row( 'admin_configuration_change', \%values );
    }
    catch ($error) { return { status => 'unavailable' }; };
    return $row ? $row->{result} : { status => 'unavailable' };
}

1;

__END__

=head1 NAME

GPForum::Service::Admin::Configuration - Administrator GUI configuration boundary.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Wired by GPForum bootstrap and the administrator routes.

=head1 DESCRIPTION

Implements core-owned GUI settings. Provider modules receive no access to
this service, its database or credentials. See docs/integrations.md.

=head1 SUBROUTINES/METHODS

=head2 load

Reads the durable configuration snapshot. An unavailable database yields an explicit unavailable state.

=head2 environment

Returns installation settings as raw environment values for complete validation.

=head2 effective_config

Applies validated saved forum settings to installation defaults, opening sealed
credentials server-side. Bootstrap may provide an application-owned
C<effective_cache>: one validated prototype, bound to this schema, installation
configuration and durable revision. Every request still loads durable state.
Unavailable state or a failed rebuild clears the prototype. Cached results
are returned as independent configuration objects and list values; without
available saved settings, the installation configuration is returned. No prior
revision or decrypted secret is reused for another installation or key set.
Saved sealed credentials bypass the cache entirely, preserving per-request
decryption and avoiding a long-lived plaintext copy in the worker.

=head2 fields

Returns the explicit editable forum settings catalogue, with types, secrecy and activation requirements.

=head2 general_page

Returns grouped, redacted presentation data; secret input values are always blank.

=head2 save_general

Validates related settings together, seals changed secrets and writes one revision-checked idempotent command.

=head2 save_plugin

Saves the enabled state and display mode of one independent plugin with a revision precondition.

=head2 reset_general

Restores one setting to the installation value after checking the resulting complete configuration.

=head2 load_p

Reads authoritative configuration with native SQL and returns the same state shape as C<load>. Unavailable configuration retains the existing degraded-state contract.

=head1 DIAGNOSTICS

Writes return explicit ok, invalid, conflict, forbidden or unavailable states.
Database errors follow the application's normal error boundary. Secrets and
submitted values are not included in diagnostics.

=head1 CONFIGURATION AND ENVIRONMENT

Installation configuration remains the bootstrap source. Durable overrides
are stored in PostgreSQL through versioned functions and administrator writes.

=head1 DEPENDENCIES

Uses the core configuration and authorization boundaries and PostgreSQL API.

=head1 INCOMPATIBILITIES

Requires the administrator configuration migration for editable settings.

=head1 BUGS AND LIMITATIONS

Host bootstrap settings remain deployment-owned; settings marked for restart
are read during service startup. A failed write never reports success.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
