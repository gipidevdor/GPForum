# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Theme::Registry;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my $FALLBACK_THEME => 'auto';
const my @THEME_NAMES    => qw(auto default dark high_contrast);
const my $PREFERS_LIGHT  => '(prefers-color-scheme: light)';
const my $PREFERS_DARK   => '(prefers-color-scheme: dark)';
const my %SUPPORTED      => map { $_ => 1 } @THEME_NAMES;
const my @TOKEN_NAMES => qw(
  background foreground muted surface surface_alt primary secondary accent
  border danger success focus_ring info warning icon_accent surface_warning surface_danger
  surface_success text_on_primary text_on_accent text_on_danger text_on_success
  text_on_warning
);

has configured_default_theme => sub { return $FALLBACK_THEME; };

sub default_theme ($self) {
    return $self->safe_theme_name( $self->configured_default_theme );
}

sub supported_themes {
    return [@THEME_NAMES];
}

sub token_names {
    return [@TOKEN_NAMES];
}

sub supported ( $self, $name ) {
    return 0 if !defined $name || !length $name;

    return exists $SUPPORTED{$name} ? 1 : 0;
}

sub safe_theme_name ( $self, $name ) {
    return $self->supported($name) ? $name : $FALLBACK_THEME;
}

sub theme ( $self, $name ) {
    my $theme  = $self->_shared($name);
    my %tokens = %{ $theme->{tokens} };

    return { %{$theme}, %tokens, tokens => \%tokens };
}

sub tokens ( $self, $name ) {
    return { %{ $self->theme($name)->{tokens} } };
}

sub token ( $self, $theme_name, $token_name ) {
    return $self->tokens($theme_name)->{$token_name};
}

sub theme_color ( $self, $name ) {
    return $self->_shared($name)->{theme_color};
}

# The colour of the browser's own chrome around the page, as the meta tags
# that state it: one for a theme with one palette, and for the automatic
# theme one for each setting of the device.
sub theme_colors ( $self, $name ) {
    my $theme = $self->_shared($name);

    return [ { color => $theme->{theme_color} } ] if $theme->{name} ne 'auto';

    return [
        { color => $theme->{theme_color},      media => $PREFERS_LIGHT },
        { color => $self->theme_color('dark'), media => $PREFERS_DARK },
    ];
}

sub color_scheme ( $self, $name ) {
    return $self->_shared($name)->{color_scheme};
}

sub theme_options ( $self, $current_theme ) {
    my $safe_current = $self->safe_theme_name($current_theme);
    my @options;
    for my $name ( @{ $self->supported_themes } ) {
        my $theme = $self->_shared($name);
        push @options,
          {
            current      => $name eq $safe_current ? 1 : 0,
            label_key    => $theme->{label_key},
            name         => $name,
            color_scheme => $theme->{color_scheme},
          };
    }

    return \@options;
}

sub css_variables ( $self, $name ) {
    my $tokens = $self->tokens($name);
    return [ map { [ _css_token_name($_), $tokens->{$_} ] }
          @{ $self->token_names } ];
}

# The shared contract a theme name stands for, to read and never to hand
# out: theme and tokens copy it.
sub _shared ( $self, $name ) {
    return _theme_contracts()->{ $self->safe_theme_name($name) };
}

sub _css_token_name ($name) {
    $name =~ s/_/-/gmsx;

    return 'color-' . $name;
}

# The automatic theme has no palette of its own: it is the light one until
# the device asks for dark, and the stylesheet makes it the dark one then.
# Its tokens here are the light theme's, which is what a server that cannot
# see the device has to assume.
#
# The contracts are built once per process: every page asks for its theme
# half a dozen times (its colour scheme, its theme colours, the selector's
# options), and building all four palettes for each answer was 15
# microseconds a time. Callers get copies (theme, tokens), as before.
sub _theme_contracts {
    state $contracts = _built_contracts();

    return $contracts;
}

sub _built_contracts {
    my $contracts = _palettes();
    $contracts->{auto} = {
        %{ $contracts->{default} },
        color_scheme => 'light dark',
        label_key    => 'theme.auto',
        name         => 'auto',
    };

    return $contracts;
}

sub _palettes {
    return {
        default => _contract(
            'default',
            'theme.default',
            'light',
            '#f2f2f7',
            {
                background      => '#f2f2f7',
                foreground      => '#1d1d1f',
                muted           => '#3a3a3c',
                surface         => '#ffffff',
                surface_alt     => '#f5f5f7',
                primary         => '#00509e',
                secondary       => '#515154',
                accent          => '#0071e3',
                border          => '#86868b',
                danger          => '#b0000e',
                success         => '#1b7a34',
                focus_ring      => '#0071e3',
                info            => '#00509e',
                warning         => '#9a5600',
                icon_accent     => '#9b6d32',
                surface_warning => '#fff6e5',
                surface_danger  => '#fff1f0',
                surface_success => '#ecf8ef',
                text_on_primary => '#ffffff',
                text_on_accent  => '#ffffff',
                text_on_danger  => '#ffffff',
                text_on_success => '#ffffff',
                text_on_warning => '#1d1d1f',
            }
        ),
        dark => _contract(
            'dark',
            'theme.dark',
            'dark',
            '#000000',
            {
                background      => '#000000',
                foreground      => '#f5f5f7',
                muted           => '#d1d1d6',
                surface         => '#1c1c1e',
                surface_alt     => '#2c2c2e',
                primary         => '#4da3ff',
                secondary       => '#aeaeb2',
                accent          => '#4da3ff',
                border          => '#7c7c80',
                danger          => '#ff6961',
                success         => '#30d158',
                focus_ring      => '#4da3ff',
                info            => '#64d2ff',
                warning         => '#ffb340',
                icon_accent     => '#c69955',
                surface_warning => '#33240a',
                surface_danger  => '#3b1412',
                surface_success => '#0f2e18',
                text_on_primary => '#000000',
                text_on_accent  => '#000000',
                text_on_danger  => '#000000',
                text_on_success => '#000000',
                text_on_warning => '#000000',
            }
        ),
        high_contrast => _contract(
            'high_contrast',
            'theme.high_contrast',
            'light',
            '#ffffff',
            {
                background      => '#ffffff',
                foreground      => '#000000',
                muted           => '#101010',
                surface         => '#ffffff',
                surface_alt     => '#f2f2f2',
                primary         => '#003e7e',
                secondary       => '#00324d',
                accent          => '#003e7e',
                border          => '#000000',
                danger          => '#8b0000',
                success         => '#005c2f',
                focus_ring      => '#003e7e',
                info            => '#00324d',
                warning         => '#5a3a00',
                icon_accent     => '#000000',
                surface_warning => '#fff8cc',
                surface_danger  => '#fff0f0',
                surface_success => '#ecfff3',
                text_on_primary => '#ffffff',
                text_on_accent  => '#ffffff',
                text_on_danger  => '#ffffff',
                text_on_success => '#ffffff',
                text_on_warning => '#000000',
            }
        ),
    };
}

sub _contract ( $name, $label_key, $color_scheme, $theme_color, $tokens ) {
    return {
        color_scheme => $color_scheme,
        label_key    => $label_key,
        name         => $name,
        theme_color  => $theme_color,
        tokens       => $tokens,
    };
}

1;
