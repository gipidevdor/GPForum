# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::IconSet;

use Mojo::Base -strict, -signatures;
use v5.40;

use Const::Fast;
use GPForum::X::Argument;
use Mojo::ByteStream;
use Mojo::File qw(path);
use Mojo::Util qw(xml_escape);

our $VERSION = '0.001';

const my @NAMES => qw(
  orbit discussion reply quote search categories tag bookmark bell message
  compose feed settings user attachment image link copy check close more
  arrow-left arrow-right shield download upload warning poll
  emote-heart emote-laugh emote-celebrate emote-think emote-smile emote-wink
  emote-surprise emote-thanks
);
const my %KNOWN             => map { $_ => 1 } @NAMES;
const my $SOURCE_ROOT_DEPTH => 4;
const my $SPRITE_PATH       => _sprite_path();

sub _sprite_path {
    my $root = path(__FILE__)->to_abs;
    for ( 1 .. $SOURCE_ROOT_DEPTH ) {
        $root = $root->dirname;
    }
    return $root->child('assets/img/gpforum-icons.svg')->to_string;
}

sub _require_name ($name) {
    if ( !defined $name || !exists $KNOWN{$name} ) {
        GPForum::X::Argument->throw( message => 'Unknown UI icon' );
    }
    return;
}

sub names ($class) {
    return [@NAMES];
}

# Only names from the local sprite are accepted. A caller cannot supply a
# URL, markup, event handler, style or arbitrary class through this helper.
# Most icons accompany text and are decoration; a standalone informative
# image must explicitly receive its translated label.
sub render ( $class, $controller, $name, $label = undef ) {
    _require_name($name);

    my $decorative = !defined $label || !length $label;
    my $cache      = $decorative
      ? $controller->stash->{'gp.decorative_icons'} //= {}
      : undef;
    if ( $cache && exists $cache->{$name} ) {
        return Mojo::ByteStream->new( $cache->{$name} );
    }
    my $sprite = $controller->ui_asset_url('gpforum-icons.svg');
    my $url    = xml_escape( $sprite . q{#} . $name );
    my $semantics =
      defined $label && length $label
      ? q{role="img" aria-label="} . xml_escape($label) . q{"}
      : q{aria-hidden="true"};
    my $extra = $name =~ /\Aemote-/msx ? ' ui-icon--emote' : q{};

    my $html =
        q{<svg class="ui-icon}
      . $extra
      . q{" width="24" height="24" viewBox="0 0 24 24" focusable="false" }
      . $semantics
      . q{><use href="}
      . $url
      . q{"></use></svg>};
    if ($cache) { $cache->{$name} = $html; }
    return Mojo::ByteStream->new($html);
}

# Favicons need a complete SVG, rather than an external symbol reference.
sub document ( $class, $name, $label ) {
    _require_name($name);
    state $sprite = path($SPRITE_PATH)->slurp;
    my ($body) = $sprite =~ m{<symbol\s+id="\Q$name\E"[^>]*>(.*?)</symbol>}msx;
    if ( !defined $body ) {
        GPForum::X::Argument->throw( message => 'Missing approved symbol' );
    }
    $body =~ s/var[(]--color-icon-accent,\s*currentColor[)]/#9b6d32/gmsx;

    return
q{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" color="#373630" role="img" aria-labelledby="icon-title"><title id="icon-title">}
      . xml_escape( $label // q{} )
      . q{</title><rect width="24" height="24" rx="6" fill="#f8f6ef"/>}
      . $body
      . q{</svg>};
}

1;

__END__

=head1 NAME

GPForum::Web::IconSet - Local, labelled or decorative interface symbols

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $controller->ui_icon('reply');
    $controller->ui_icon('warning', $controller->t('common.warning'));

=head1 DESCRIPTION

Renders a reference to a whitelisted symbol in the fingerprinted local SVG
sprite. Decorative icons are hidden from assistive technology and never
focusable. An explicit label produces an informative image; labels and URLs
are XML-escaped. There is no icon font, external request or script.

=head1 SUBROUTINES/METHODS

=head2 names

Returns a fresh list of the supported symbol names.

=head2 render

Takes a controller, a symbol name and an optional translated image label.
Returns a trusted byte stream. Visible button text or a labelled parent
control is still required when an icon alone represents an action.
Decorative markup is reused by symbol within the request's asset context;
each result is a fresh byte stream. Explicit labels are never cached.

=head2 document

Returns a symbol as a self-contained SVG with an escaped title, for the
browser icon. The local sprite is read once per process. The paper ground
keeps its ink visible on both light and dark browser chrome.

=head1 DIAGNOSTICS

An unknown symbol raises L<GPForum::X::Argument>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Const::Fast>, L<Mojo::ByteStream>, L<Mojo::Util>.

=head1 INCOMPATIBILITIES

Requires SVG C<use> support. Control names do not depend on SVG rendering.

=head1 BUGS AND LIMITATIONS

Meaning must never depend on the decorative accent dot or colour alone.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

BSD-3-Clause.

=cut
