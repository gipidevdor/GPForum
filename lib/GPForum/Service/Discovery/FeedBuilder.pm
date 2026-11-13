# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Discovery::FeedBuilder;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::Text qw(plain_excerpt);
use GPForum::Service::Discovery::VisibilityPolicy;

our $VERSION = '0.001';

# What XML 1.0 lets a document carry (section 2.2, Char), and its opposite.
const my $XML_WHITESPACE => qr/[\x{9}\x{A}\x{D}]/msx;
const my $XML_BASIC      => qr/[\x{20}-\x{D7FF}\x{E000}-\x{FFFD}]/msx;
const my $XML_ASTRAL     => qr/[\x{10000}-\x{10FFFF}]/msx;
const my $XML_CHAR       => qr/$XML_WHITESPACE|$XML_BASIC|$XML_ASTRAL/msx;
const my $NOT_XML        => qr/(?!$XML_CHAR)./msx;

const my $MAX_SUMMARY_LENGTH => 240;

__PACKAGE__->requires(qw(canonical_url));
has hub_url => q{};
has visibility_policy =>
  sub { return GPForum::Service::Discovery::VisibilityPolicy->new; };

# The entries of the public threads, each with its opening post's text as
# the summary when the row carries the post's excerpt (migration 1056).
sub thread_items ( $self, $threads ) {
    return [
        map {
            {
                id      => $_->{thread_id},
                title   => $_->{title},
                author  => $_->{author_display_name},
                url     => $self->canonical_url->thread_url($_),
                updated =>
                  _rfc3339( $_->{last_activity_at} || $_->{created_at} ),
                summary => plain_excerpt( $_->{excerpt}, $MAX_SUMMARY_LENGTH ),
                full_body => undef,
            }
        } grep { $self->visibility_policy->is_public($_) } @{$threads}
    ];
}

sub render_atom ( $self, $feed ) {
    my @entries = map { _atom_entry($_) } @{ $feed->{items} || [] };

    return join "\n",
      '<?xml version="1.0" encoding="UTF-8"?>',
      '<feed xmlns="http://www.w3.org/2005/Atom">',
      '  <id>' . _xml_escape( $feed->{id} ) . '</id>',
      '  <title>' . _xml_escape( $feed->{title} ) . '</title>',

      # RFC 4287, 4.1.1: a feed names an author unless every entry does; an
      # entry whose member is gone has none, so the forum is the feed's.
      '  <author><name>' . _xml_escape( $feed->{title} ) . '</name></author>',
      '  <link href="' . _xml_escape( $feed->{url} ) . '" rel="self" />',
      (
        length $self->hub_url
        ? '  <link href="' . _xml_escape( $self->hub_url ) . '" rel="hub" />'
        : ()
      ),
      '  <updated>' . _xml_escape( $feed->{updated} ) . '</updated>',
      @entries,
      '</feed>',
      q{};
}

# A time as PostgreSQL writes it ("2026-10-23 12:34:56.123456+00") as RFC
# 3339 wants it in an Atom feed: "T" between date and time, and a zone with
# its minutes. A time already in that shape is left as it is.
sub _rfc3339 ($value) {
    return $value if !defined $value;
    my $date = "$value";
    $date =~ s/[ ]/T/msx;
    if ( index( $date, 'T' ) >= 0 ) {
        $date =~ s/([+-][[:digit:]]{2})\z/$1:00/amsx;
    }

    return $date;
}

sub _atom_entry ($item) {
    return join "\n",
      '  <entry>',
      '    <id>' . _xml_escape( $item->{url} ) . '</id>',
      '    <title>' . _xml_escape( $item->{title} ) . '</title>',
      '    <link href="' . _xml_escape( $item->{url} ) . '" />',
      '    <updated>' . _xml_escape( $item->{updated} ) . '</updated>',
      (
        defined $item->{author}
        ? '    <author><name>'
          . _xml_escape( $item->{author} )
          . '</name></author>'
        : ()
      ),
      '    <summary>' . _xml_escape( $item->{summary} ) . '</summary>',
      '  </entry>';
}

# Escaped for XML 1.0 text and attributes, without the characters XML 1.0
# cannot carry at all: a thread title with a C0 control or a lone surrogate
# in it made the whole feed malformed for every reader.
sub _xml_escape ($value) {
    if ( !defined $value ) {
        $value = q{};
    }
    $value =~ s/$NOT_XML//gmsx;
    $value =~ s/&/&amp;/gmsx;
    $value =~ s/</&lt;/gmsx;
    $value =~ s/>/&gt;/gmsx;
    $value =~ s/"/&quot;/gmsx;

    return $value;
}

1;

__END__

=head1 NAME

GPForum::Service::Discovery::FeedBuilder - The public Atom feed of threads.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $builder = GPForum::Service::Discovery::FeedBuilder->new(
        canonical_url => GPForum::Service::Discovery::CanonicalUrl->new(
            base_url => 'https://forum.example',
        ),
    );

    my $items = $builder->thread_items($threads);
    my $atom  = $builder->render_atom(
        {
            id      => 'https://forum.example/feed.atom',
            title   => 'Public discussions',
            url     => 'https://forum.example/feed.atom',
            updated => '2026-05-23T12:00:00Z',
            items   => $items,
        }
    );

=head1 DESCRIPTION

Turns thread rows into feed items and feed items into an Atom document. Only
threads that L<GPForum::Service::Discovery::VisibilityPolicy> calls public
become items, and an item carries a summary built from the excerpt of its
opening post the thread list gives
(L<GPForum::Service::Forum::ThreadReader/list_public_threads>), never the
full body: its text, at most 240 characters
(L<GPForum::Infrastructure::Text/plain_excerpt>). Every value written into
the XML is escaped.

=head1 SUBROUTINES/METHODS

=head2 thread_items

Takes an array reference of thread hashes, each with the C<excerpt> of its
opening post's safe HTML when it has one. Returns an array
reference of items, one per public thread, each with C<id> (the thread id),
C<title>, C<author> (C<author_display_name>), C<url> (from
C<< canonical_url->thread_url >>), C<updated> (C<last_activity_at>, or
C<created_at>), C<summary> (the excerpt as text, at most 240 characters,
empty without one) and C<full_body>, which is always undef.

=head2 render_atom

Takes a hash reference with C<id>, C<title>, C<url>, C<updated> and
C<items>. Returns the Atom XML as a string: the feed header with a C<self>
link and the feed's title as its author, then one C<entry> per item using
its C<url> as id and link, its C<title>, C<updated>, C<author> when it has
one and C<summary>.

=head1 DIAGNOSTICS

None. Undefined values render as empty elements.

=head1 CONFIGURATION AND ENVIRONMENT

None here: C<canonical_url> carries the public base URL.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::Text>,
L<GPForum::Service::Discovery::VisibilityPolicy>,
L<GPForum::Service::Discovery::CanonicalUrl>.

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
