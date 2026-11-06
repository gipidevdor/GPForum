# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::Text;

use v5.40;

use Exporter   qw(import);
use Mojo::Util qw(html_unescape);

our $VERSION = '0.001';

our @EXPORT_OK = qw(has_text plain_excerpt trimmed);

# Whether a value is text with something in it: defined and not empty. There
# were thirty-five copies of this in lib/, seven public, in three spellings.
sub has_text ($value) {
    return defined $value && length $value ? 1 : 0;
}

# A value without the whitespace it starts and ends with; undef reads as
# the empty string.
sub trimmed ($value) {
    return ( $value // q{} ) =~ s/\A \s+ | \s+ \z//grmsx;
}

# The start of a body's safe HTML as one line of plain text, at most $length
# characters: each tag a space, each entity its character (whatever shows
# the text escapes it again), and a text cut short ends on a whole word and
# an ellipsis. A tag or an entity the HTML was cut through goes: the
# renderer escapes every & of the text, so a trailing one starts an entity.
# The feed and the thread page's description each kept a copy that left the
# entities escaped, so an "&" reached the reader as "&amp;".
sub plain_excerpt ( $html, $length ) {
    my $text = $html // q{};
    $text =~ s/<[^>]* \z//msx;
    $text =~ s/<[^>]*>/ /gmsx;
    $text =~ s/& [#[:alnum:]]* \z//msx;
    $text = trimmed( html_unescape($text) =~ s/\s+/ /grmsx );
    return $text if length $text <= $length;

    my $kept = substr $text, 0, $length - 1;
    my $word = rindex $kept, q{ };
    if ( substr( $text, $length - 1, 1 ) ne q{ } && $word * 2 >= $length ) {
        $kept = substr $kept, 0, $word;
    }
    $kept =~ s/[\s,;:]+ \z//msx;

    return $kept . "\N{HORIZONTAL ELLIPSIS}";
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::Text - The text helpers every layer asks for.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    use GPForum::Infrastructure::Text qw(has_text plain_excerpt trimmed);

    return if !has_text( $input->{user_id} );
    my $name    = trimmed( $input->{name} );
    my $summary = plain_excerpt( $post->{body}, 240 );

=head1 DESCRIPTION

One home for the text helpers the services, the controllers and the view
models each kept a copy of. Exported on request.

=head1 SUBROUTINES/METHODS

=head2 has_text

Takes a value and returns 1 when it is defined and not empty, 0 otherwise.

=head2 trimmed

Takes a value and returns it without leading and trailing whitespace; undef
returns the empty string.

=head2 plain_excerpt

Takes safe HTML, as L<GPForum::Service::Forum::BodyRenderer> writes it, and
a length of at least two. Returns its text on one line, at most that many
characters: tags become spaces, entities their characters, runs of
whitespace one space, and the ends are trimmed. A longer text is cut on
the last whole word, unless that leaves less than half, and ends with an
ellipsis. A tag or an entity left open where the HTML was cut is dropped.
undef returns the empty string. The text is not HTML: whatever shows it
escapes it.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Exporter>, L<Mojo::Util>.

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
