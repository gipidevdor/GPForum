# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::Facebook;

use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;
use Mojo::URL;

our $VERSION = '0.001';
const my $ACCOUNT => qr/[[:alnum:].]{1,128}/amsx;
const my $ITEM    => qr/[[:alnum:]]{1,128}/amsx;
const my $CONTENT_PATH =>
  qr{\A / (?: $ACCOUNT / (?:posts|videos) | reel ) / $ITEM /? \z}amsx;

sub manifest_v1 ($self) {
    return {
        id           => 'facebook',
        name         => 'Facebook',
        version      => $VERSION,
        api_version  => 1,
        url_hosts    => [qw(facebook.com www.facebook.com m.facebook.com)],
        frame_hosts  => [qw()],
        capabilities => ['link.resolve.v1'],
    };
}

sub resolve_link_v1 ( $self, $request ) {
    my $url  = Mojo::URL->new( $request->{url} );
    my $host = lc $url->host;
    return undef
      if $host ne 'facebook.com'
      && $host ne 'www.facebook.com'
      && $host ne 'm.facebook.com';

    my $path      = $url->path->to_string;
    my $canonical = "https://www.facebook.com$path";
    if ( $path eq '/permalink.php' || $path eq '/story.php' ) {
        my $story = $url->query->param('story_fbid') // q{};
        my $id    = $url->query->param('id')         // q{};
        return undef
          if $story !~ /\A [[:alnum:]]{1,128} \z/amsx
          || $id !~ /\A [[:digit:]]{1,32} \z/amsx;
        $canonical .= "?story_fbid=$story&id=$id";
    }
    elsif ( $path eq '/watch/' || $path eq '/watch' ) {
        my $id = $url->query->param('v') // q{};
        return undef if $id !~ /\A [[:digit:]]{1,32} \z/amsx;
        $canonical .= "?v=$id";
    }
    elsif ( $path !~ $CONTENT_PATH ) {
        return undef;
    }

    return {
        api_version => 1,
        provider    => 'facebook',
        kind        => 'post',
        label       => 'Facebook',
        url         => $canonical,
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::Facebook - Recognize Facebook post and video links.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $descriptor = $provider->resolve_link_v1({api_version => 1, url => $https_url});

=head1 DESCRIPTION

C<manifest_v1> declares version and contract 1 capabilities. C<resolve_link_v1> takes
a validated plain API v1 request and returns a data-only link descriptor, or
undef. Public availability is not inferred from a URL. Redirect endpoints
are not supported. Tracking parameters are removed. No SDK, oEmbed call,
external script or automatic content fetch runs.

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

L<Mojo::Base> and L<Const::Fast>. L<Mojo::URL> is internal to the adapter; the API accepts plain data.

=head1 INCOMPATIBILITIES

Supports integration contract 1 only.

=head1 BUGS AND LIMITATIONS

Only the documented URL forms are supported. No network or account access.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
