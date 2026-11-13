# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Discovery::CanonicalUrl;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use Mojo::Util qw(encode url_escape);

our $VERSION = '0.001';

const my %LEGAL_PATH => (
    cookies => '/legal/cookies',
    notice  => '/legal/notice',
    privacy => '/legal/privacy',
    terms   => '/legal/terms',
);

has base_url => 'https://gpforum.example';

# A category's page is /c/ID: the only category route. The sitemap wrote
# /c/SLUG, a 404 for every category.
sub category_url ( $self, $category ) {
    return $self->_absolute( '/c/' . $category->{category_id} );
}

sub thread_url ( $self, $thread ) {
    return $self->_absolute(
        '/t/' . $thread->{thread_id} . q{/} . _slug( $thread->{slug} ) );
}

sub legal_url ( $self, $page ) {
    my $path = _legal_path($page);
    if ( !$path ) {
        return undef;
    }

    return $self->_absolute($path);
}

sub _legal_path ($page) {
    if ( !defined $page ) {
        return undef;
    }
    if ( !exists $LEGAL_PATH{$page} ) {
        return undef;
    }

    return $LEGAL_PATH{$page};
}

sub _absolute ( $self, $path ) {
    return $self->base_url . $path;
}

# A slug keeps the letters of its title, an accented one too, and a URL
# carries them escaped: a sitemap's <loc> must be a URI, not an IRI.
sub _slug ($slug) {
    return 'untitled' if !defined $slug || !length $slug;

    return url_escape( encode( 'UTF-8', $slug ) );
}

1;

__END__

=head1 NAME

GPForum::Service::Discovery::CanonicalUrl - Absolute canonical URLs for spaces, categories, threads and legal pages.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $urls = GPForum::Service::Discovery::CanonicalUrl->new(
        base_url => 'https://forum.example.org',
    );

    my $url = $urls->thread_url( { slug => 'hello', thread_id => $thread_id } );
    # https://forum.example.org/t/<thread_id>/hello
    my $terms = $urls->legal_url('terms');

=head1 DESCRIPTION

The one place that knows the public URL shapes, so the sitemap, the feed
and the page metadata agree on them: C</c/CATEGORY_ID>,
C</t/THREAD_ID/SLUG> and C</legal/cookies>, C</legal/privacy> and
C</legal/terms>, each appended to C<base_url>. A thread's missing or
empty slug becomes C<untitled>.

=head1 SUBROUTINES/METHODS

=head2 category_url

Takes a hash reference with C<category_id>. Returns the category's
absolute URL.

=head2 thread_url

Takes a hash reference with C<thread_id> and C<slug>. Returns the thread's
absolute URL, the slug percent-encoded as UTF-8 (C<untitled> when there is
none).

=head2 legal_url

Takes C<cookies>, C<privacy> or C<terms>. Returns that page's absolute URL,
or undef for any other name or undef.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

C<base_url>, default C<https://gpforum.example>, which the bootstrap sets
from the configuration's C<public_base_url>. Paths are appended to it as it
is, so it should not end in a slash.

=head1 DEPENDENCIES

L<Mojo::Base>, L<Mojo::Util> and L<Const::Fast>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
