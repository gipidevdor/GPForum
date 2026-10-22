# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::BodyRenderer;

use Const::Fast;
use English    qw(-no_match_vars);
use List::Util qw(any);
use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::Util qw(xml_escape);

our $VERSION = '0.001';

const my $STRONG_MARK   => q{**};
const my $EMPHASIS_MARK => q{*};
const my $LINK_CLOSE    => q{](};
const my $KEEP_TRAILING => -1;
const my $INDEX_MISS    => -1;
const my $REL_SAFE      => 'nofollow noopener noreferrer';
const my @SAFE_SCHEMES  => ( 'https://', 'http://', 'mailto:' );

# Enough of a URL to tell whether it starts with an allowed scheme.
const my $SCHEME_PROBE => 8;

# A line, with or without its newline, that opens a fence (three backticks
# and an info string with no backtick) or closes one (three backticks and
# spaces), indented by at most three spaces.
const my $OPEN_FENCE  => qr/\A [ ]{0,3} ``` [^`\n]* \n? \z/msx;
const my $CLOSE_FENCE => qr/\A [ ]{0,3} ``` [ ]* \n? \z/msx;

# A code span: backticks around text on one line.
const my $CODE_SPAN => qr/( ` [^`\n]+ ` )/msx;

# Bodies kept rendered: a page's worth of hot threads, at a few KB each.
const my $RENDERED_LIMIT => 2048;

# What the memo may hold, in characters of source and HTML together: 4 MiB
# of them. A count alone let 2,048 bodies at the 50,000-character limit,
# each rendered up to six times as long, grow a worker by half a gigabyte.
const my $RENDERED_CHARACTERS => 4_194_304;

# A body renders to the same HTML every time, and a thread page renders its
# 25 bodies on every read, so the HTML is kept by source. The memo is
# cleared when full rather than kept in order: a bound is all it needs.
my %RENDERED;
my $HELD = 0;

sub render_safe ( $self, $source ) {
    if ( !defined $source || !length $source ) {
        return q{};
    }
    return $RENDERED{$source} if exists $RENDERED{$source};

    my $html = _render($source);
    my $size = length($source) + length $html;
    if ( keys %RENDERED >= $RENDERED_LIMIT
        || $HELD + $size > $RENDERED_CHARACTERS )
    {
        %RENDERED = ();
        $HELD     = 0;
    }
    if ( $size <= $RENDERED_CHARACTERS ) {
        $RENDERED{$source} = $html;
        $HELD += $size;
    }

    return $html;
}

sub memo_characters ($class) {
    return $RENDERED_CHARACTERS;
}

sub held_characters ($class) {
    return $HELD;
}

sub _render ($source) {
    my $text = $source =~ s/\r\n?/\n/gmsxr;

    return _joined(
        map {
            $_->{type} eq 'fence'
              ? '<pre>' . _code_html( $_->{text} ) . '</pre>'
              : _prose_html( $_->{text} )
        } @{ _tokens($text) }
    );
}

# The source cut into fences and the prose between them, in one pass over its
# lines. A fence is the lines between an opening line, newline included, and
# the first closing line below it; a prose run ends before any line that
# opens a fence. An opening line with no closing line below is prose: when
# the pass ends inside a fence, the lines held for it go back as prose. No
# line is read more than twice, whatever the body holds -- searching the rest
# of the body from each opening line made 4,000 of them take three seconds.
sub _tokens ($text) {
    my @tokens;
    my ( $fence, $prose );
    for my $line ( split /(?<=\n)/msx, $text ) {
        if ($fence) {
            if ( _closes($line) ) {
                my $body = join q{}, @{$fence}[ 1 .. $#{$fence} ];
                push @tokens,
                  { text => $body =~ s/\n\z//msxr, type => 'fence' };
                ( $fence, $prose ) = ();
                next;
            }
            push @{$fence}, $line;
            next;
        }
        my $opens = _opens($line);
        if ( $opens && $line =~ /\n\z/msx ) {
            $fence = [$line];
            next;
        }
        $prose = _prose_line( \@tokens, $opens ? undef : $prose, $line );
    }
    for my $line ( @{ $fence // [] } ) {
        $prose = _prose_line( \@tokens, _opens($line) ? undef : $prose, $line );
    }

    return \@tokens;
}

# $line added to the prose run $prose, or to a new one when there is none;
# the run it went to.
sub _prose_line ( $tokens, $prose, $line ) {
    if ( !$prose ) {
        $prose = { text => q{}, type => 'prose' };
        push @{$tokens}, $prose;
    }
    $prose->{text} .= $line;

    return $prose;
}

sub _opens ($line) {
    return $line =~ $OPEN_FENCE;
}

sub _closes ($line) {
    return $line =~ $CLOSE_FENCE;
}

# Prose is paragraphs, block quotes and flat lists. Each line is classified
# once; changing block kind or a blank line ends the current block. Quoted
# markers remain quote content rather than becoming nested lists.
sub _prose_html ($text) {
    if ( $text !~ /\S/msx ) {
        return q{};
    }

    my @blocks;
    my $current;
    for my $line ( split /\n/msx, $text, $KEEP_TRAILING ) {
        my $quoted =
            $line =~ /\A [ ]{0,3} > /msx
          ? $line =~ s/\A [ ]{0,3} > [ ]?//msxr
          : undef;
        if ( !defined $quoted && $line !~ /\S/msx ) {
            $current = undef;
            next;
        }

        my ( $type, $item, $start ) =
          defined $quoted
          ? ( 'quote', $quoted, undef )
          : _list_line($line);
        if ( !$current || $current->{type} ne $type ) {
            $current = { lines => [], type => $type, start => $start };
            push @blocks, $current;
        }
        push @{ $current->{lines} }, $item;
    }

    return _joined(
        map {
                $_->{type} eq 'ul' || $_->{type} eq 'ol' ? _list_html($_)
              : $_->{type} eq 'quote'                    ? '<blockquote>'
              . _paragraphs_html( $_->{lines} )
              . '</blockquote>'
              : _paragraphs_html( $_->{lines} )
        } @blocks
    );
}

sub _list_line ($line) {
    if ( $line =~ /\A [ ]{0,3} [-+*] [ \t]+ (\S.*) \z/msx ) {
        return ( 'ul', $1, undef );
    }
    if ( $line =~ /\A [ ]{0,3} (\d{1,9}) [.)] [ \t]+ (\S.*) \z/amsx ) {
        return ( 'ol', $2, 0 + $1 );
    }

    return ( 'paragraph', $line, undef );
}

# Tags are selected by the classifier; only a bounded numeric start enters
# an attribute. List content follows exactly the same escaping as paragraphs.
sub _list_html ($block) {
    my $tag = $block->{type};
    my $start =
      $tag eq 'ol' && $block->{start} != 1
      ? q{ start="} . $block->{start} . q{"}
      : q{};

    return
        '<'
      . $tag
      . $start . '>'
      . join( q{}, map { '<li>' . _inline($_) . '</li>' } @{ $block->{lines} } )
      . '</'
      . $tag . '>';
}

# One paragraph for each run of non-blank lines, its lines joined by <br>.
sub _paragraphs_html ($lines) {
    my @chunks = ( [] );
    for my $line ( @{$lines} ) {
        if ( $line !~ /\S/msx ) {
            push @chunks, [];
            next;
        }
        push @{ $chunks[-1] }, $line;
    }

    return _joined(
        map  { '<p>' . _inline( join "\n", @{$_} ) . '</p>' }
        grep { @{$_} } @chunks
    );
}

# A paragraph's text is its code spans and what lies between them. A span is
# only escaped, so what it holds is shown as typed; the rest goes on to links
# and emphasis. A backtick with no partner on its line stays a backtick.
sub _inline ($raw) {
    my $html = join q{}, map {
        /\A ` ( [^`\n]+ ) ` \z/msx
          ? _code_html($1)
          : _emphasis( _links( xml_escape($_) ) )
    } split $CODE_SPAN, $raw;

    return $html =~ s/\n/<br>/gmsxr;
}

# Links in escaped text: [label](url), not after a "!" (an image), with a
# URL _target accepts. Any other "[" stays as typed. The target found for
# one "[" is kept for the next while it still lies ahead, so a run of "["
# before one far "](" reads the text once, not once for each "[".
sub _links ($text) {
    my $out = q{};
    my $pos = 0;
    my %ahead;
    while ( !$ahead{exhausted}
        && ( my $open = _scan( $text, '[', $pos ) ) != $INDEX_MISS )
    {
        my $link = _link_at( $text, $open, \%ahead );
        if ( !$link ) {
            $out .= substr $text, $pos, $open - $pos + 1;
            $pos = $open + 1;
            next;
        }
        $out .= substr( $text, $pos, $open - $pos ) . $link->{html};
        $pos = $link->{end};
    }

    return $out . substr $text, $pos;
}

# The anchor for the link opening at $open, and where it ends; undef when
# the "[" follows a "!" or has no allowed target.
sub _link_at ( $text, $open, $ahead ) {
    if ( $open > 0 && substr( $text, $open - 1, 1 ) eq q{!} ) {
        return undef;
    }
    my $target = _target( $text, $open, $ahead );
    if ( !$target ) {
        return undef;
    }

    my $url_start = $target->{mid} + length $LINK_CLOSE;
    my $url       = substr $text, $url_start, $target->{end} - $url_start;
    my $label     = substr $text, $open + 1, $target->{mid} - $open - 1;
    return {
        end  => $target->{end} + 1,
        html => '<a href="'
          . $url
          . '" rel="'
          . $REL_SAFE . q{">}
          . $label . '</a>',
    };
}

# The "](" after $open, the first ")" after that, and the first flaw after
# that, in %{$ahead}; the target when its URL, already escaped, starts with an
# allowed scheme and holds no flaw before its ")". Each position is searched
# again only once $open has passed it: the next "](" lies after the last, so
# the ")" and flaw found for the last are still the first after it, if they
# lie beyond. Sets exhausted when no "](" or ")" is left, and so no link.
sub _target ( $text, $open, $ahead ) {
    if ( ( $ahead->{mid} // $INDEX_MISS ) <= $open ) {
        my $mid = _scan( $text, $LINK_CLOSE, $open + 1 );
        if ( $mid == $INDEX_MISS ) {
            $ahead->{exhausted} = 1;
            return undef;
        }
        my $url_start = $mid + length $LINK_CLOSE;
        my $end =
          ( $ahead->{end} // $INDEX_MISS ) >= $url_start
          ? $ahead->{end}
          : _scan( $text, ')', $url_start );
        if ( $end == $INDEX_MISS ) {
            $ahead->{exhausted} = 1;
            return undef;
        }
        my $flaw =
          ( $ahead->{flaw} // $INDEX_MISS ) >= $url_start
          ? $ahead->{flaw}
          : _flaw( $text, $url_start );
        my $scheme = lc substr $text, $url_start, $SCHEME_PROBE;
        %{$ahead} = (
            end  => $end,
            flaw => $flaw,
            mid  => $mid,
            safe => $flaw >= $end
              && ( any { index( $scheme, $_ ) == 0 } @SAFE_SCHEMES ),
        );
    }

    return $ahead->{safe} ? $ahead : undef;
}

# The first index at or after $from of whitespace or an entity but &amp;, or
# the length of $text when there is none.
sub _flaw ( $text, $from ) {
    pos $text = $from;
    if ( $text =~ / [[:space:]] | & (?! amp; ) /gmsx ) {
        return $LAST_MATCH_START[0];
    }

    return length $text;
}

# The index of $needle in $text at or after $from, or -1: every search the
# renderer makes goes through here, so a test can count what it reads.
sub _scan ( $text, $needle, $from ) {
    return index $text, $needle, $from;
}

# Emphasis runs after _links, so the string already contains the anchors that
# pass emitted -- and xml_escape ran before both, so any angle bracket left in
# it is a tag this renderer produced, not user text. Marking up across one
# rewrote the URL: [docs](https://example.com/a*b*c) came out as
# href="https://example.com/a<em>b</em>c", with HTML tags inside an attribute.
#
# Emphasis is applied to the text between tags instead, never inside one. The
# cost is that a pair cannot span a link -- `*before [x](y) after*` no longer
# emphasises -- which is a fair trade against corrupting the href, and keeps
# `[*text*](url)` working because the link text is its own segment.
sub _emphasis ($text) {
    return join q{}, map {
        substr( $_, 0, 1 ) eq q{<}
          ? $_
          : _wrap_pairs( _wrap_pairs( $_, $STRONG_MARK, 'strong' ),
            $EMPHASIS_MARK, 'em' )
    } split /(< [^>]* >)/msx, $text;
}

# Each pair of $mark around text on one line becomes that text in <$tag>; a
# mark with no partner, or around nothing, stays as typed.
sub _wrap_pairs ( $text, $mark, $tag ) {
    my $width = length $mark;
    my $out   = q{};
    my $pos   = 0;
    while ( $pos < length $text ) {
        my $start = index $text, $mark, $pos;
        if ( $start == $INDEX_MISS ) {
            last;
        }
        my $end = index $text, $mark, $start + $width;
        if ( $end == $INDEX_MISS ) {
            last;
        }

        my $inner = substr $text, $start + $width, $end - $start - $width;
        if ( !length $inner || index( $inner, "\n" ) != $INDEX_MISS ) {
            $out .= substr $text, $pos, $start + $width - $pos;
            $pos = $start + $width;
            next;
        }
        $out .= substr( $text, $pos, $start - $pos ) . "<$tag>$inner</$tag>";
        $pos = $end + $width;
    }

    return $out . substr $text, $pos;
}

sub _code_html ($text) {
    return '<code>' . xml_escape($text) . '</code>';
}

sub _joined (@parts) {
    return join "\n", grep { length } @parts;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::BodyRenderer - Safe markdown subset for post bodies.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $html = GPForum::Service::Forum::BodyRenderer->new->render_safe($source);

=head1 DESCRIPTION

Turns post C<body_source> into sanitized HTML for
C<post_bodies.body_rendered_safe> and forum post presenters. Input is escaped
before any markup is introduced. The allowed subset is emphasis, http/https/mailto
links, block quotes, flat bulleted and numbered lists, fenced code, and code spans between backticks on one
line. Raw HTML, inline images, and @mentions are not interpreted.

=head1 SUBROUTINES/METHODS

=head2 render_safe

Returns sanitized HTML for the supplied markdown source. Undefined or empty
source yields an empty string. The HTML is kept by source, in a memo of at
most 2,048 bodies and L</memo_characters> characters of source and HTML
together, cleared when either is reached.

=head2 memo_characters

Returns how many characters of source and HTML the memo may hold: 4,194,304.

=head2 held_characters

Returns how many characters of source and HTML the memo holds now.

=head1 DIAGNOSTICS

None. Invalid or unsafe constructs are escaped and left as text.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Uses L<Const::Fast>, L<List::Util>, L<Mojo::Base>, and L<Mojo::Util>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Inline images and @mention highlighting are intentionally left as literal
text. Lists are flat, with one item per marked line; nesting, continuation lines,
headings and raw-HTML markdown are not implemented. A code span is
read before links and emphasis, so neither can reach across one.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
