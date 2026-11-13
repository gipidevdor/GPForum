# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::Mathematics;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';
const my $FORMULA_LIMIT => 4_096;
const my $SPAN_LIMIT    => 50;
const my $ATTEMPT_LIMIT => 100;
const my %CLOSE =>
  ( q{$$} => q{$$}, q{\[} => q{\]}, q{\(} => q{\)}, q{$} => q{$} );

sub manifest_v1 ($self) {
    return {
        api_version  => 1,
        id           => 'mathematics',
        name         => 'LaTeX / KaTeX',
        version      => $VERSION,
        capabilities => ['math.render.v1'],
        url_hosts    => [],
        frame_hosts  => [],
    };
}

sub prepare_math_v1 ( $self, $request ) {
    my $source = $request->{source};
    my @spans;
    my $attempts = 0;
    while ( $source =~ /(\$\$ | \\[[(] | \$)/gmsx ) {
        last if ++$attempts > $ATTEMPT_LIMIT || @spans >= $SPAN_LIMIT;
        my $open  = $1;
        my $start = ( pos $source ) - length $open;
        next if _escaped( $source, $start );
        my $content = pos $source;
        my $span    = _candidate( $source, $open, $content );
        next if !$span;
        push @spans, $span;
        pos($source) = $start + $span->{length};
    }
    return { api_version => 1, provider => 'mathematics', spans => \@spans };
}

sub _candidate ( $source, $open, $content ) {
    my $end = _closing( $source, $CLOSE{$open}, $content );
    return undef if $end < 0;
    my $tex = substr $source, $content, $end - $content;
    return undef if !length($tex) || length($tex) > $FORMULA_LIMIT;
    return undef if $open eq q{$}  && $tex =~ /(?:\A\s|\s\z|\n)/msx;
    return undef if $open eq q{\(} && $tex =~ /\n/msx;
    my $start = $content - length $open;
    return {
        start   => $start,
        length  => $end + length( $CLOSE{$open} ) - $start,
        source  => $tex,
        display => $open eq q{$$} || $open eq q{\[} ? 'block' : 'inline'
    };
}

sub _closing ( $source, $delimiter, $start ) {
    my $end = index $source, $delimiter, $start;
    while ( $end >= 0 && _escaped( $source, $end ) ) {
        $end = index $source, $delimiter, $end + length $delimiter;
    }
    return $end;
}

sub _escaped ( $source, $offset ) {
    my $slashes = 0;
    while ( $offset > 0 && substr( $source, --$offset, 1 ) eq q{\\} ) {
        ++$slashes;
    }
    return $slashes % 2;
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::Mathematics - Local LaTeX equation plugin.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = $plugin->prepare_math_v1({api_version=>1,source=>$prose});

=head1 DESCRIPTION

Declares math.render.v1 without any remote origins. Recognizes inline dollar
or parenthesized LaTeX and display double-dollar or bracketed LaTeX. Returns
only bounded source spans. Core owns code exclusion, escaping, rendering
containers and the locally packaged, untrusted-input KaTeX MathML renderer.

=head1 SUBROUTINES/METHODS

=head2 manifest_v1

Returns the fixed API v1 mathematics manifest.

=head2 prepare_math_v1

Accepts a locked plain source request and returns at most 50 equation spans,
each at most 4,096 characters. Attempts are bounded to avoid repeatedly
searching large malformed input. Unmatched delimiters remain ordinary text.

=head1 DIAGNOSTICS

None. Unsupported expressions remain readable source in the browser.

=head1 CONFIGURATION AND ENVIRONMENT

Enabled independently in Admin Plugins. No account or external service needed.

=head1 DEPENDENCIES

L<Const::Fast>, L<Mojo::Base>. KaTeX is pinned and served locally by core.

=head1 INCOMPATIBILITIES

Supports API v1 math.render.v1; it is not a link or media provider.

=head1 BUGS AND LIMITATIONS

Supports KaTeX's LaTeX subset, not arbitrary TeX packages or document execution.
Formulas cannot cross paragraphs or code boundaries. Dollar delimiters must
not enclose leading or trailing whitespace. No user-supplied global macros.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
