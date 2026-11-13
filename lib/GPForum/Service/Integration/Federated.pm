# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::Federated;

use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;
use Mojo::URL;

our $VERSION = '0.001';
const my $LABEL_LENGTH => 200;

use List::Util qw(any);
const my $POST_USER   => qr{[[:alnum:]_.-]{1,64}}amsx;
const my $POST_NUMBER => qr{[[:digit:]]{1,24}}amsx;
const my $UUID_WORD   => qr{[[:xdigit:]]{4}}amsx;
const my $VIDEO_ID =>
qr{[[:alnum:]]{22}|${UUID_WORD}${UUID_WORD}-$UUID_WORD-$UUID_WORD-$UUID_WORD-${UUID_WORD}${UUID_WORD}${UUID_WORD}}amsx;
has hosts => sub { return []; };
has [qw(provider_id provider_name video)];
has provider_version => sub { return $VERSION; };

sub manifest_v1 ($self) {
    return {
        api_version  => 1,
        id           => $self->provider_id,
        name         => $self->provider_name,
        version      => $self->provider_version,
        url_hosts    => [ @{ $self->hosts } ],
        frame_hosts  => $self->video ? [ @{ $self->hosts } ] : [],
        capabilities => $self->video
        ? [qw(link.resolve.v1 media.embed.v1)]
        : ['link.resolve.v1']
    };
}

sub resolve_link_v1 ( $self, $request ) {
    my $url  = Mojo::URL->new( $request->{url} );
    my $host = lc $url->host;
    return undef if !any { $_ eq $host } @{ $self->hosts };
    my $path = $url->path->to_string;
    if ( !$self->video ) {
        return undef
          if $path !~
m{\A / (?:[@]$POST_USER/$POST_NUMBER|users/$POST_USER/statuses/$POST_NUMBER) /? \z}amsx;
        return {
            api_version => 1,
            provider    => $self->provider_id,
            kind        => 'post',
            label       => substr( $host . $path, 0, $LABEL_LENGTH ),
            url         => "https://$host$path"
        };
    }
    my ($id) =
      $path =~ m{\A /(?:w/|videos/(?:watch|embed)/)($VIDEO_ID) /? \z}amsx;
    return undef if !defined $id;
    return {
        api_version => 1,
        provider    => $self->provider_id,
        kind        => 'video',
        label       => "$host $id",
        url         => "https://$host/w/$id",
        embed => { kind => 'video', url => "https://$host/videos/embed/$id" }
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::Federated - Recognize federated content only on explicitly authorized instances.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $provider = GPForum::Service::Integration::Federated->new;

=head1 DESCRIPTION

Recognize federated content only on explicitly authorized instances. No remote requests or untrusted HTML cross the plugin boundary.

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
