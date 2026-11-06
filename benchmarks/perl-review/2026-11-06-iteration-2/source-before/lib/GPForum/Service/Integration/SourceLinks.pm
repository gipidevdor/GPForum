# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::SourceLinks;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';
const my $MAX_SOURCE     => 50_000;
const my $MAX_ENTRIES    => 512;
const my $MAX_CHARACTERS => 1_048_576;

has max_entries     => $MAX_ENTRIES;
has max_characters  => $MAX_CHARACTERS;
has entries         => sub { return {}; };
has held_characters => 0;

sub urls ( $self, $source ) {
    my $key     = substr $source // q{}, 0, $MAX_SOURCE;
    my $entries = $self->entries;
    if ( exists $entries->{$key} ) {
        return [ @{ $entries->{$key} } ];
    }
    my $urls = _extract($key);
    my $size = length $key;
    for my $url ( @{$urls} ) { $size += length $url; }
    if ( keys %{$entries} >= $self->max_entries
        || $self->held_characters + $size > $self->max_characters )
    {
        %{$entries} = ();
        $self->held_characters(0);
    }
    if ( $self->max_entries > 0 && $size <= $self->max_characters ) {
        $entries->{$key} = $urls;
        $self->held_characters( $self->held_characters + $size );
    }
    return [ @{$urls} ];
}

sub _extract ($source) {
    my @urls;
    my $fenced = 0;
    for my $line ( split /\r?\n/msx, $source ) {
        if ($fenced) {
            if ( $line =~ /\A [ ]{0,3} ``` [ ]* \z/msx ) { $fenced = 0; }
            next;
        }
        if ( $line =~ /\A [ ]{0,3} ``` [^`]* \z/msx ) {
            $fenced = 1;
            next;
        }
        my ($raw) = $line =~ m{\A [ \t]* (https://\S+) [ \t]* \z}msxi;
        if ( !defined $raw ) {
            ($raw) = $line =~
              m{\A [ \t]* [[] [^]\n]+ []] [(] (https://\S+) [)] [ \t]* \z}msxi;
        }
        if ( defined $raw ) { push @urls, $raw; }
    }
    return \@urls;
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::SourceLinks - Bounded standalone URL extraction cache.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $urls = $links->urls($authorized_post_source);

=head1 DESCRIPTION

Extracts standalone HTTPS URLs and Markdown links outside fenced code from
the first 50,000 source characters. Keeps source prefixes and candidate URLs
in application-owned process memory, bounded by 512 entries and 1,048,576
characters of keys and URLs. Character accounting excludes Perl overhead.
The cache clears when full; oversized entries are not kept. Empty results
are cached too. No providers, policy decisions or resolved cards are stored.

Only already-authorized source may be passed in. Entries cannot be retrieved
by post id. Source edits change the key; deployment clears parser results.

=head1 SUBROUTINES/METHODS

=head2 urls

Returns a fresh array of extracted candidates in source order, including
duplicates. Candidates remain untrusted; callers must validate those they resolve.

=head1 DIAGNOSTICS

Extraction does not validate URLs or log source data.

=head1 CONFIGURATION AND ENVIRONMENT

C<max_entries> and C<max_characters> bound storage. C<entries> and
C<held_characters> expose the stored candidates and character count.

=head1 DEPENDENCIES

L<Const::Fast>, L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

This is a syntax scanner, not a Markdown parser or an authorization boundary.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
