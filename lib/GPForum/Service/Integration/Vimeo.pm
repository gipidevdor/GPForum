# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::Vimeo;

use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::URL;
use Const::Fast;
const my $VIDEO_ID         => qr{[1-9][[:digit:]]{0,11}}amsx;
const my $GROUP_COLLECTION => qr{channels/[^/]+/|groups/[^/]+/videos/}amsx;
const my $CATALOG_COLLECTION =>
  qr{album/[[:digit:]]+/video/|ondemand/[^/]+/}amsx;
const my $COLLECTION => qr{$GROUP_COLLECTION|$CATALOG_COLLECTION}amsx;

our $VERSION = '0.001';

sub manifest_v1 ($self) {
    return {
        api_version  => 1,
        id           => 'vimeo',
        name         => 'Vimeo',
        version      => $VERSION,
        url_hosts    => [qw(vimeo.com www.vimeo.com player.vimeo.com)],
        frame_hosts  => ['player.vimeo.com'],
        capabilities => [qw(link.resolve.v1 media.embed.v1)]
    };
}

sub resolve_link_v1 ( $self, $request ) {
    my $url = Mojo::URL->new( $request->{url} );
    return undef
      if lc( $url->host ) !~ /\A (?:www[.]|player[.])? vimeo[.]com \z/amsx;
    my $path = $url->path->to_string;
    my ( $id, $hash );
    if ( lc( $url->host ) eq 'player.vimeo.com' ) {
        ($id) = $path =~ m{\A /video/ ([1-9][[:digit:]]{0,11}) /? \z}amsx;
        my @hashes = $url->query->every_param('h')->@*;
        return undef if @hashes > 1;
        $hash = $hashes[0];
    }
    else {
        ( $id, $hash ) = $path =~
          m{\A / ([1-9][[:digit:]]{0,11}) (?:/([[:xdigit:]]{10}))? /? \z}amsx;
        if ( !defined $id ) {
            ($id) = $path =~ m{\A / (?:$COLLECTION) ($VIDEO_ID) /? \z}amsx;
        }
    }
    return undef
      if !defined $id
      || ( defined $hash && $hash !~ /\A [[:xdigit:]]{10} \z/amsx );
    my $watch = "https://vimeo.com/$id" . ( defined $hash ? "/$hash" : q{} );
    my $embed = Mojo::URL->new("https://player.vimeo.com/video/$id");
    if ( defined $hash ) { $embed->query( h => $hash ); }

    return {
        api_version => 1,
        provider    => 'vimeo',
        kind        => 'video',
        label       => "Vimeo $id",
        url         => $watch,
        embed       => { kind => 'video', url => "$embed" }
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::Vimeo - Recognize Vimeo videos and preserve unlisted privacy hashes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $provider = GPForum::Service::Integration::Vimeo->new;

=head1 DESCRIPTION

Recognize Vimeo videos and preserve unlisted privacy hashes. No remote requests or untrusted HTML cross the plugin boundary.

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
