# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Service::Integration::Readiness;
use v5.40;
use Carp qw(croak);
use GPForum::Service::Integration::HttpClient;
our $VERSION = '0.001';

# Field names only: no secret or URL value escapes this boundary.
sub missing ( $class, $kind, $config ) {
    my @fields;
    if    ( $kind eq 'discord' ) { @fields = qw(discord_webhook); }
    elsif ( $kind eq 'openid' ) {
        @fields =
          qw(oidc_issuer oidc_authorization_endpoint oidc_token_endpoint oidc_jwks_uri oidc_client_id oidc_client_secret);
    }
    elsif ( $kind eq 'feeds' ) {
        return @{ $config->syndication_sources } ? [] : ['syndication_sources'];
    }
    else { croak 'Unknown integration readiness kind'; }
    my @missing = grep { !length( $config->$_ // q{} ) } @fields;
    my $public  = 0;
    try {
        GPForum::Service::Integration::HttpClient->new->https_url(
            $config->public_base_url );
        $public = 1;
    }
    catch ($error) { $public = 0; };
    if ( !$public ) { push @missing, 'public_base_url'; }
    return \@missing;
}
1;
__END__

=head1 NAME

GPForum::Service::Integration::Readiness - Local prerequisites shared by integration GUI and runtime services.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $missing = $class->missing('discord',$config);

=head1 DESCRIPTION

Checks required settings and the existing outbound HTTPS hostname policy,
without DNS or HTTP. Only missing setting names are returned. This establishes
configuration readiness, not external availability.

=head1 SUBROUTINES/METHODS

=head2 missing

Returns missing field names for Discord, OpenID or authorized feeds. Discord
and OpenID also require a canonical public address accepted by the transport.

=head1 DIAGNOSTICS

An unknown service kind raises an exception.

=head1 CONFIGURATION AND ENVIRONMENT

Uses a validated effective configuration.

=head1 DEPENDENCIES

GPForum::Service::Integration::HttpClient.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

No provider connectivity check is performed.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
