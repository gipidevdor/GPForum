# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::YouTube;

use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::URL;

our $VERSION = '0.001';

sub manifest_v1 ($self) {
    return {
        id          => 'youtube',
        name        => 'YouTube',
        version     => $VERSION,
        api_version => 1,
        url_hosts   => [qw(youtube.com www.youtube.com m.youtube.com youtu.be)],
        frame_hosts => [qw(www.youtube-nocookie.com)],
        capabilities => [qw(link.resolve.v1 media.embed.v1)],
    };
}

sub resolve_link_v1 ( $self, $request ) {
    my $url  = Mojo::URL->new( $request->{url} );
    my $host = lc $url->host;
    my $path = $url->path->to_string;
    my $id;
    if ( $host eq 'youtu.be' ) {
        ($id) = $path =~ m{\A / ([[:alnum:]_-]{11}) /? \z}amsx;
    }
    elsif ($host eq 'youtube.com'
        || $host eq 'www.youtube.com'
        || $host eq 'm.youtube.com' )
    {
        if ( $path eq '/watch' ) {
            $id = $url->query->param('v');
        }
        else {
            ($id) = $path =~
              m{\A / (?:shorts|live|embed) / ([[:alnum:]_-]{11}) /? \z}amsx;
        }
    }
    return undef if !defined $id || $id !~ /\A [[:alnum:]_-]{11} \z/amsx;

    return {
        api_version => 1,
        provider    => 'youtube',
        kind        => 'video',
        label       => $id,
        url         => "https://www.youtube.com/watch?v=$id",
        embed       => {
            kind => 'video',
            url  => "https://www.youtube-nocookie.com/embed/$id"
        },
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::YouTube - Recognize public YouTube video links.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $descriptor = $provider->resolve_link_v1({api_version => 1, url => $https_url});

=head1 DESCRIPTION

C<manifest_v1> declares version and contract 1 capabilities. C<resolve_link_v1> takes
a validated plain API v1 request and returns a data-only video descriptor, or
undef. Watch, short, live and embed links are normalized to a watch URL.
No network requests, credentials, thumbnails or HTML are involved.

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
