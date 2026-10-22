# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::Automod;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

our $VERSION = '0.001';

# ADR 0133: the bounds of a watched word and of the list, the actions, and
# how far a wildcard reaches. A phrase is plain words matched whole and
# without regard to case; a star at either end lets the word run on for at
# most $WILDCARD_SPAN word characters. Nothing else is a pattern, so every
# match is a literal search with bounded lookaround: no input can make it
# backtrack without end.
const my $MAXIMUM_PHRASE      => 100;
const my $MAXIMUM_REPLACEMENT => 100;
const my $MAXIMUM_WORDS       => 500;
const my $MAXIMUM_LINK_LIMIT  => 100;
const my $MAXIMUM_TRUST_LEVEL => 100;
const my $WILDCARD_SPAN       => 32;
const my $DEFAULT_REPLACEMENT => q{***};
const my $PATTERN_CACHE       => 2_048;
const my %ACTIONS             => ( block => 1, flag => 1, replace => 1 );
const my %LINK_ACTIONS        => ( block => 1, flag => 1 );

# A phrase: no control characters, a star only at its ends, and at least
# one word character.
const my $PHRASE_SHAPE => qr/\A [*]? [^*\s] (?: [^*]* [^*\s] )? [*]? \z/msx;
const my $CONTROL      => qr/\p{Cc}/msx;
const my $WORDISH      => qr/\p{Word}/msx;

# A link in a body's Markdown source: a URL with a scheme, or one that
# starts with www. A Markdown link or an autolink is one link.
const my $LINK => qr{
    (?: \b https?:// | (?<! [\w./@-] ) www[.] ) [^\s<>()\[\]]
}imsx;

my %pattern;

sub maximum_words ($self) { return $MAXIMUM_WORDS; }

sub actions ($self) { return [qw(block flag replace)]; }

sub link_actions ($self) { return [qw(block flag)]; }

sub default_replacement ($self) { return $DEFAULT_REPLACEMENT; }

# The phrase as the list keeps it -- whitespace collapsed, case folded --
# or undef when it is not one.
sub phrase ( $self, $raw ) {
    my $collapsed = ( $raw // q{} ) =~ s/\s+/ /grmsx;
    my $phrase    = fc $collapsed;
    $phrase =~ s/\A [ ] | [ ] \z//gmsx;

    return undef
      if !length $phrase
      || length $phrase > $MAXIMUM_PHRASE
      || $phrase =~ $CONTROL
      || $phrase !~ $PHRASE_SHAPE
      || $phrase !~ $WORDISH;

    return $phrase;
}

# The replacement as kept (whitespace collapsed; empty means the default),
# or undef when it is not one.
sub replacement ( $self, $raw ) {
    my $text = ( $raw // q{} ) =~ s/\s+/ /grmsx;
    $text =~ s/\A [ ] | [ ] \z//gmsx;

    return undef
      if length $text > $MAXIMUM_REPLACEMENT || $text =~ $CONTROL;

    return $text;
}

# A link limit (an integer 0..100, or undef for the rule off) and a trust
# level (0..100), or undef when the given text is not one.
sub link_limit ( $self, $raw ) {
    return q{} if !defined $raw || $raw eq q{};

    return _bounded( $raw, $MAXIMUM_LINK_LIMIT );
}

sub trust_level ( $self, $raw ) {
    return _bounded( $raw // q{}, $MAXIMUM_TRUST_LEVEL );
}

sub is_action ( $self, $action ) {
    return exists $ACTIONS{ $action // q{} } ? 1 : 0;
}

sub is_link_action ( $self, $action ) {
    return exists $LINK_ACTIONS{ $action // q{} } ? 1 : 0;
}

# The compiled match of a listed phrase.
sub pattern ( $self, $phrase ) {
    return $pattern{$phrase} if exists $pattern{$phrase};

    if ( keys %pattern >= $PATTERN_CACHE ) {
        %pattern = ();
    }
    my ( $lead, $core, $trail ) = $phrase =~ /\A ([*]?) (.*?) ([*]?) \z/msx;
    my $words = join q{\s+}, map { quotemeta } split /[ ]/msx, $core;
    my $span  = "\\p{Word}{0,$WILDCARD_SPAN}";
    my $body  = ( $lead ? $span : q{} ) . $words . ( $trail ? $span : q{} );

    return $pattern{$phrase} = qr/(?<!\p{Word})$body(?!\p{Word})/imsx;
}

sub count_links ( $self, $text ) {
    my $count = () = ( $text // q{} ) =~ /$LINK/gmsx;

    return $count;
}

# Screens the fields of a write (field => text) against the rules
# (api.moderation_automod_rules). Block and flag judge the text as written;
# replace rewrites it, and the link rule counts the rewritten body. The
# verdict: the fields as they are to be stored, the phrases that block
# (by field), flag and were replaced, the body's links, and the link
# rule's action when the body breaks it.
sub screen ( $self, $rules, $fields ) {
    my %text = %{$fields};
    my ( %blocked, %flagged, %replaced );
    for my $word ( @{ $rules->{words} // [] } ) {
        my $phrase = $word->{phrase} // next;
        my $match  = $self->pattern($phrase);
        my $action = $word->{action} // q{};
        for my $field ( sort keys %{$fields} ) {
            next if ( $fields->{$field} // q{} ) !~ $match;
            if ( $action eq 'block' ) {
                push @{ $blocked{$field} }, $phrase;
            }
            elsif ( $action eq 'flag' ) {
                $flagged{$phrase} = 1;
            }
            elsif ( $action eq 'replace' ) {
                my $with =
                  length( $word->{replacement} // q{} )
                  ? $word->{replacement}
                  : $DEFAULT_REPLACEMENT;
                $text{$field} =~ s/$match/$with/gmsx;
                $replaced{$phrase} = 1;
            }
        }
    }

    my $links = $self->count_links( $text{body_source} );
    my $limit = $rules->{link_limit};
    my $over =
         defined $limit
      && exists $text{body_source}
      && ( $rules->{trust_level} // 0 ) < ( $rules->{link_trust_below} // 1 )
      && $links > $limit;

    return {
        fields     => \%text,
        blocked    => \%blocked,
        flagged    => [ sort keys %flagged ],
        replaced   => [ sort keys %replaced ],
        links      => $links,
        link_limit => $limit,
        link_over  => $over ? ( $rules->{link_action} // 'block' ) : undef,
    };
}

# Whether a verdict refuses the write, and whether it has anything to
# record beside the write.
sub refuses ( $self, $verdict ) {
    return ( %{ $verdict->{blocked} }
          || ( $verdict->{link_over} // q{} ) eq 'block' ) ? 1 : 0;
}

sub flags ( $self, $verdict ) {
    return ( @{ $verdict->{flagged} }
          || ( $verdict->{link_over} // q{} ) eq 'flag' ) ? 1 : 0;
}

sub _bounded ( $raw, $maximum ) {
    return undef if $raw !~ /\A \d{1,3} \z/amsx || $raw > $maximum;

    return 0 + $raw;
}

1;

__END__

=head1 NAME

GPForum::Service::Moderation::Automod - Watched words and the link rule.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $automod = GPForum::Service::Moderation::Automod->new;
    my $phrase  = $automod->phrase('Spam*');      # 'spam*'
    my $verdict = $automod->screen( $rules, { body_source => $body } );
    return refused() if $automod->refuses($verdict);

=head1 DESCRIPTION

The matching of ADR 0133, with no storage: what a watched word may be,
the bounded literal pattern each one compiles to, and the verdict of a
write's fields against the rules C<api.moderation_automod_rules> returns.
A phrase is plain words matched whole and case-insensitively; a star at
either end lets the word run on for at most 32 word characters. Links are
counted in the Markdown source.

=head1 SUBROUTINES/METHODS

=head2 maximum_words

The most watched words the list holds (500).

=head2 actions

The actions of a watched word: block, flag, replace.

=head2 link_actions

The actions of the link rule: block, flag.

=head2 default_replacement

What a replace rule with no replacement writes.

=head2 phrase

The phrase as kept, or undef when the text is not one.

=head2 replacement

The replacement as kept, or undef when it is too long or holds control
characters.

=head2 link_limit

An integer from 0 to 100, the empty string for no limit, or undef when the
text is neither.

=head2 trust_level

An integer from 0 to 100, or undef.

=head2 is_action

Whether the action is one of a watched word.

=head2 is_link_action

Whether the action is one of the link rule.

=head2 pattern

The compiled match of a listed phrase, cached per process.

=head2 count_links

The links in a Markdown source.

=head2 screen

The verdict of the fields against the rules.

=head2 refuses

Whether the verdict refuses the write.

=head2 flags

Whether the verdict puts the content in the moderation queue.

=head1 DIAGNOSTICS

None: a value that is not valid is undef.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Const::Fast>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Word boundaries are Unicode word characters; a language written without
spaces matches a phrase inside a longer run of text only through a
wildcard.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
