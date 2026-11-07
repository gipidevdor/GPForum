# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::AppleMusic;

use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::URL;
use Const::Fast;

our $VERSION = '0.001';
const my $COUNTRY       => qr/[[:lower:]]{2}/amsx;
const my $RESOURCE_TYPE => qr/(?:album|song|playlist)/msx;
const my $SLUG          => qr/[[:alnum:]%._~-]{1,256}/amsx;
const my $RESOURCE      => qr/[[:alnum:]_.-]{1,128}/amsx;

sub manifest_v1 ($self) {
    return {
        api_version  => 1,
        id           => 'apple_music',
        name         => 'Apple Music',
        version      => $VERSION,
        capabilities => [qw(link.resolve.v1 media.embed.v1)],
        url_hosts    => ['music.apple.com'],
        frame_hosts  => ['embed.music.apple.com'],
    };
}

sub resolve_link_v1 ( $self, $request ) {
    my $url = Mojo::URL->new( $request->{url} );
    return undef if lc( $url->host ) ne 'music.apple.com';
    my $path = $url->path->to_string;
    my ( $country, $type, $id ) = $path =~ m{
        \A / ($COUNTRY) / ($RESOURCE_TYPE) / (?: $SLUG / )? ($RESOURCE) /? \z
    }amsx;
    return undef if !defined $id;
    if ( $type eq 'playlist' ) {
        return undef if $id !~ /\A pl[.] [[:alnum:]_.-]+ \z/amsx;
    }
    else {
        return undef if $id !~ /\A [[:digit:]]{1,32} \z/amsx;
    }
    my $track = $url->query->param('i');
    my $query =
         defined $track
      && $track =~ /\A [[:digit:]]{1,32} \z/amsx
      && $type eq 'album' ? "?i=$track" : q{};
    return {
        api_version => 1,
        provider    => 'apple_music',
        kind        => 'audio',
        label       => "Apple Music $type $id",
        url         => "https://music.apple.com$path$query",
        embed       => {
            kind => 'audio',
            url  => "https://embed.music.apple.com$path$query"
        },
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::AppleMusic - Independent AppleMusic integration plugin.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $descriptor = $provider->resolve_link_v1({api_version => 1, url => $https_url});

=head1 DESCRIPTION

Recognizes Apple Music album, song and playlist links, preserving the selected track query. Returns a click-to-load player descriptor; no MusicKit token is used.

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
