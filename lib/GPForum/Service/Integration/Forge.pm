# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::Forge;

use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;
use Mojo::URL;

our $VERSION = '0.001';
const my $LABEL_LENGTH => 200;

has [qw(provider_id provider_name host gitlab)];
has provider_version => sub { return $VERSION; };

sub manifest_v1 ($self) {
    return {
        api_version  => 1,
        id           => $self->provider_id,
        name         => $self->provider_name,
        version      => $self->provider_version,
        url_hosts    => [ $self->host ],
        frame_hosts  => [],
        capabilities => ['link.resolve.v1']
    };
}

sub resolve_link_v1 ( $self, $request ) {
    my $url = Mojo::URL->new( $request->{url} );
    return undef if lc( $url->host ) ne $self->host;
    my $path = $url->path->to_string;
    my ( $project, $tail );
    if ( $self->gitlab ) {
        ( $project, $tail ) = split m{/-/}msx, $path, 2;
    }
    else {
        ( $project, $tail ) = $path =~ m{\A (/[^/]+/[^/]+) (?:/(.*))? \z}msx;
    }
    return undef
      if !defined $project
      || $project !~ m{\A /[[:alnum:]_.-]+ (?:/[[:alnum:]_.-]+){1,7} /? \z}amsx;
    return undef if $project =~ m{(?:\A|/) [.] (?:[.]|) (?:/|\z)}msx;
    my $kind = $self->_resource_kind($tail);
    return undef if !defined $kind;
    return {
        api_version => 1,
        provider    => $self->provider_id,
        kind        => $kind,
        label       => substr( $project, 1, $LABEL_LENGTH ),
        url         => 'https://' . $self->host . $path
    };
}

sub _resource_kind ( $self, $tail ) {
    return 'repository' if !defined $tail || !length $tail;
    return 'issue' if $tail =~ m{\A issues/[1-9][[:digit:]]{0,11}/? \z}amsx;
    my $request = $self->gitlab ? 'merge_requests' : 'pulls';
    return 'pull_request'
      if $tail =~ m{\A $request/[1-9][[:digit:]]{0,11}/? \z}amsx;
    return 'commit'  if $tail =~ m{\A commit/[[:xdigit:]]{7,64}/? \z}amsx;
    return 'release' if $tail =~ m{\A releases/? \z}amsx;
    my $release = $self->gitlab ? 'releases/' : 'releases/tag/';
    return 'release'
      if $tail =~ m{\A ${release}[[:alnum:]_.+-]{1,100}/? \z}amsx;
    return undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::Forge - Recognize reviewed code-host resource URLs.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $provider = GPForum::Service::Integration::Forge->new;

=head1 DESCRIPTION

Recognize reviewed code-host resource URLs. No remote requests or untrusted HTML cross the plugin boundary.

=head1 SUBROUTINES/METHODS

=head2 manifest_v1

Returns the pinned API v1 origins and capabilities.

=head2 resolve_link_v1

Returns a plain descriptor for a validated supported URL, or undef.

=head1 DIAGNOSTICS

Unsupported URLs return undef.

=head1 CONFIGURATION AND ENVIRONMENT

Core supplies reviewed exact hostnames and plugin activation.

=head1 DEPENDENCIES

Mojo::Base and Mojo::URL.

=head1 INCOMPATIBILITIES

Only the documented URL forms and API v1 are supported.

=head1 BUGS AND LIMITATIONS

URL recognition does not establish remote existence, rights or visibility.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
