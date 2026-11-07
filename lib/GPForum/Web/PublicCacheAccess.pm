# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::PublicCacheAccess;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::Date;

use GPForum::Infrastructure::Text qw(has_text);
use GPForum::Web::Access;

our $VERSION = '0.001';

# RFC 9110: the opaque value permits commas and literal backslashes, but
# excludes double quotes, spaces and control characters.
const my $OPAQUE_TAG => qr{" [\x21\x23-\x7e\x80-\xff]* "}msx;

has access => sub { return GPForum::Web::Access->new; };

sub is_cacheable ( $self, $controller ) {
    if ( !$self->_cacheable_method($controller) ) {
        return 0;
    }
    if ( $self->access->user_id($controller) ) {
        return 0;
    }

    # A flash message says what this visitor just did (ADR 0141): the page
    # that shows it is theirs, neither served from the cache nor stored.
    my $flash = $controller->session('flash');
    if ( ref $flash eq 'HASH' && %{$flash} ) {
        return 0;
    }

    return 1;
}

sub client_has_fresh_copy ( $self, $controller, $entry ) {
    my $headers   = $controller->req->headers;
    my $candidate = $headers->header('If-None-Match');
    if ( defined $candidate ) {

        # A differing ETag cannot be overridden by a date, even a future one.
        return $self->etag_matches( $candidate, $entry->{etag} );
    }
    if (
        $self->modified_since_matches(
            $headers->header('If-Modified-Since'),
            $entry->{last_modified_epoch}
        )
      )
    {
        return 1;
    }

    return 0;
}

sub etag_matches ( $self, $candidate, $etag ) {
    if ( !has_text($candidate) ) {
        return 0;
    }
    if ( !has_text($etag) ) {
        return 0;
    }

    return $self->_etag_token_matches( $candidate, $etag );
}

sub modified_since_matches ( $self, $candidate, $last_modified_epoch ) {
    if ( !has_text($candidate) ) {
        return 0;
    }
    if ( !defined $last_modified_epoch ) {
        return 0;
    }

    return $self->_epoch_not_after( $candidate, $last_modified_epoch );
}

sub revalidated_state ( $, $cache_state ) {
    if ( $cache_state eq 'hit' ) {
        return 'revalidated';
    }

    return 'miss-revalidated';
}

sub _cacheable_method ( $, $controller ) {
    my $method = $controller->req->method || q{};
    if ( $method eq 'GET' ) {
        return 1;
    }
    if ( $method eq 'HEAD' ) {
        return 1;
    }

    return 0;
}

sub _etag_token_matches ( $, $candidate, $etag ) {
    my ($opaque) = $etag =~ /\A (?: W\/ )? ($OPAQUE_TAG) \z/msx;
    return 0 if !defined $opaque;
    return 1 if $candidate eq $etag || $candidate eq $opaque;
    return 1 if $candidate =~ /\A [\t ]* [*] [\t ]* \z/msx;

    # Parse quoted members without splitting an opaque value's commas.
    # Consume the complete list before accepting a match: malformed trailing
    # input must not accidentally validate a stale representation.
    my $matched = 0;
    pos $candidate = 0;
    while ( $candidate =~
        /\G [\t ,]* (?: W\/ )? ($OPAQUE_TAG) [\t ]* (?: , | \z )/gcmsx )
    {
        if ( $1 eq $opaque ) { $matched = 1; }
    }
    return $candidate =~ /\G [\t ,]* \z/gcmsx ? $matched : 0;
}

sub _epoch_not_after ( $, $candidate, $last_modified_epoch ) {

    # Mojo::Date answers undef, without dying, for a date it cannot parse and
    # for one out of range ("Day '32'"): either validator is unusable.
    my $epoch = Mojo::Date->new($candidate)->epoch;
    if ( !defined $epoch ) {
        return 0;
    }

    return $epoch >= $last_modified_epoch ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Web::PublicCacheAccess - Public HTTP cache decisions.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $access = GPForum::Web::PublicCacheAccess->new;
    if ( $access->is_cacheable($controller) ) {
        return $cache->render(%input);
    }

=head1 DESCRIPTION

Owns anonymous GET/HEAD cacheability, ETag and Last-Modified freshness, and
revalidation header labels for public SSR. It does not store entries, render
bodies, or talk to PostgreSQL. L<GPForum::Web::PublicHttpCache> keeps those
responsibilities.

=head1 SUBROUTINES/METHODS

=head2 is_cacheable

True for anonymous GET or HEAD requests whose session carries no flash
message: the page that shows one is the visitor's own.

=head2 client_has_fresh_copy

True when the applicable request validator matches the cached representation.

If C<If-None-Match> is present, only that validator decides freshness;
C<If-Modified-Since> is ignored, including when the entity tag differs.

=head2 etag_matches

True when the candidate lists the entry ETag or C<*>.

Uses weak comparison for C<If-None-Match>: matching quoted opaque values
are equivalent with or without C<W/>. Commas inside a quoted value remain
part of that value; a malformed list cannot produce a match.

=head2 modified_since_matches

True when If-Modified-Since parses and is not before the entry epoch.

=head2 revalidated_state

Returns C<revalidated> for hits and C<miss-revalidated> for stored misses.

=head1 DIAGNOSTICS

These methods return booleans or header labels. HTTP 304 rendering stays in
L<GPForum::Web::PublicHttpCache>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Uses L<GPForum::Web::Access> and L<Mojo::Date>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Does not decide whether a cache backend is configured; the public HTTP cache
still requires a cache object before consulting this helper.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
