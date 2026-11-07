# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::Instagram;

use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::URL;

our $VERSION = '0.001';

sub manifest_v1 ($self) {
    return {
        api_version  => 1,
        id           => 'instagram',
        name         => 'Instagram',
        version      => $VERSION,
        capabilities => ['link.resolve.v1'],
        url_hosts    => [qw(instagram.com www.instagram.com instagr.am)],
        frame_hosts  => [],
    };
}

sub resolve_link_v1 ( $self, $request ) {
    my $url = Mojo::URL->new( $request->{url} );
    return undef
      if lc( $url->host ) !~
      /\A (?: (?:www[.])? instagram[.]com | instagr[.]am ) \z/msx;
    my ( $type, $id ) = $url->path->to_string =~
      m{\A / (p|reel|tv) / ([[:alnum:]_-]{1,64}) /? \z}amsx;
    return undef if !defined $id;
    return {
        api_version => 1,
        provider    => 'instagram',
        kind        => 'post',
        label       => "Instagram $id",
        url         => "https://www.instagram.com/$type/$id/",
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::Instagram - Independent Instagram integration plugin.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $descriptor = $provider->resolve_link_v1({api_version => 1, url => $https_url});

=head1 DESCRIPTION

Recognizes public post and reel URL forms without loading Meta scripts or fetching remote content.

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
