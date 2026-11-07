# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::GitHub;

use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::URL;

our $VERSION = '0.001';

sub manifest_v1 ($self) {
    return {
        id           => 'github',
        name         => 'GitHub',
        version      => $VERSION,
        api_version  => 1,
        url_hosts    => [qw(github.com www.github.com)],
        frame_hosts  => [qw()],
        capabilities => ['link.resolve.v1'],
    };
}

sub resolve_link_v1 ( $self, $request ) {
    my $url = Mojo::URL->new( $request->{url} );
    return undef if lc( $url->host ) !~ /\A (?:www[.])? github[.]com \z/amsx;
    my $path = $url->path->to_string;
    my ( $owner, $repo, $tail ) = $path =~ m{
        \A / ([[:alnum:]-]{1,39}) / ([[:alnum:]_.-]{1,100})
        ( /.* )? \z
    }amsx;
    return undef if !defined $repo || $repo eq q{.} || $repo eq q{..};

    my $kind  = 'repository';
    my $label = "$owner/$repo";
    if ( defined $tail && $tail ne q{/} ) {
        if ( $tail =~ m{\A / (issues|pull) / ([[:digit:]]{1,12}) /? \z}amsx ) {
            $kind = $1 eq 'issues' ? 'issue' : 'pull_request';
            $label .= " #$2";
        }
        elsif ( $tail =~ m{\A / commit / ([[:xdigit:]]{7,40}) /? \z}amsx ) {
            $kind = 'commit';
            $label .= " $1";
        }
        elsif ( $tail =~
            m{\A / releases (?: /tag/ [[:alnum:]_.+-]{1,128} )? /? \z}amsx )
        {
            $kind = 'release';
            $label .= $tail;
        }
        else { return undef; }
    }

    return {
        api_version => 1,
        provider    => 'github',
        kind        => $kind,
        label       => $label,
        url         => "https://github.com$path",
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::GitHub - Recognize GitHub resource links.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $descriptor = $provider->resolve_link_v1({api_version => 1, url => $https_url});

=head1 DESCRIPTION

C<manifest_v1> declares version and contract 1 capabilities. C<resolve_link_v1> takes
a validated plain API v1 request and returns a data-only repository, issue,
pull request, commit or release descriptor, or undef. No API requests are
made; the card does not claim to know a resource's visibility or live state.

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
