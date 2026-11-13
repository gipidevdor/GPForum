# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::Spotify;

use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::URL;
use Const::Fast;

our $VERSION = '0.001';
const my $RESOURCE_TYPE => qr/(?:track|album|artist|playlist|episode|show)/msx;
const my $PREFIX        => qr/(?:intl-[[:lower:]]{2}\/|embed\/)?/amsx;

sub manifest_v1 ($self) {
    return {
        api_version  => 1,
        id           => 'spotify',
        name         => 'Spotify',
        version      => $VERSION,
        capabilities => [qw(link.resolve.v1 media.embed.v1)],
        url_hosts    => ['open.spotify.com'],
        frame_hosts  => ['open.spotify.com'],
    };
}

sub resolve_link_v1 ( $self, $request ) {
    my $url = Mojo::URL->new( $request->{url} );
    return undef if lc( $url->host ) ne 'open.spotify.com';
    my ( $type, $id ) = $url->path->to_string =~ m{
        \A /  $PREFIX
        ($RESOURCE_TYPE) / ([[:alnum:]]{22}) /? \z
    }amsx;
    return undef if !defined $id;
    return {
        api_version => 1,
        provider    => 'spotify',
        kind        => 'audio',
        label       => "Spotify $type $id",
        url         => "https://open.spotify.com/$type/$id",
        embed       => {
            kind => 'audio',
            url  => "https://open.spotify.com/embed/$type/$id"
        },
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::Spotify - Independent Spotify integration plugin.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $descriptor = $provider->resolve_link_v1({api_version => 1, url => $https_url});

=head1 DESCRIPTION

Recognizes Spotify track, album, artist, playlist, show and episode links. Returns a click-to-load player descriptor; no Web API or login scope is used.

=head1 SUBROUTINES/METHODS

=head2 manifest_v1

Returns a fresh manifest with provider id, name, version, contract version
and capabilities.

=head2 resolve_link_v1

Returns plain resource data for a supported validated API v1 URL request,
or undef for an unsupported host, path or resource identifier.

=head1 DIAGNOSTICS

None. Unsupported links return undef.

=head1 CONFIGURATION AND ENVIRONMENT

Enabled through GPFORUM_INTEGRATION_PLUGINS by the application registry.

=head1 DEPENDENCIES

L<Mojo::Base>. L<Mojo::URL> is internal to the adapter; the API accepts plain data.

=head1 INCOMPATIBILITIES

Supports integration contract 1 only.

=head1 BUGS AND LIMITATIONS

Only the documented URL forms are supported. No network or account access.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
