# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::Partials;

use Carp qw(croak);
use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Mojo::ByteStream;
use Mojo::File;
use Mojo::Template;
use List::Util qw(any);
use Mojo::Util qw(decode md5_sum monkey_patch xml_escape);
use Symbol     qw(delete_package);

our $VERSION = '0.001';

# The controller of the partial being rendered -- the templates' $c and
# $self, and the one every helper they call is called on -- and the plain
# messages of its locale, escaped.
our $CONTROLLER;
our $TEXT;

# An argument that changes what the renderer looks up or how it wraps the
# output: such an include is the renderer's.
const my %RENDERER_ARGUMENT => map { $_ => 1 }
  qw(extends format handler inline layout template variant);

# A translation written on its own, <%= t('key') %>, with nothing to
# interpolate.
const my $TRANSLATION =>
  qr{<%= \s* t[(] \s* '([[:alnum:]_.-]+)' \s* [)] \s* %>}msx;

__PACKAGE__->requires(qw(renderer fallback));

has messages  => undef;    # optional: without it every t() stays a call
has templates => sub { return {}; };
has texts     => sub { return {}; };
has namespace => sub ($self) {
    return 'GPForum::Web::Partials::Sandbox::' . md5_sum("$self");
};
has exported => 0;

# Mojolicious renders an include as it renders a page: the before_render
# hook, a stash copy of the options, the template's name hashed to find its
# compiled form, the handler, a trace line built for the log, a glob
# assigned for the template's controller. On a list page that was most of
# the rendering: 43 microseconds an include, 62 of them on the home page. A
# partial is an EP template with no layout, rendered in the current format;
# it is compiled once per process and run directly, with the stash localized
# as include localizes it. Any other include -- a format, a handler, a
# layout, a template that is not an EP file on the renderer's paths -- is
# the renderer's, through the fallback.
sub include ( $self, $controller, @arguments ) {
    return $self->fallback->( $controller, @arguments ) if !( @arguments % 2 );

    my ( $name, %values ) = @arguments;
    my $stash = $controller->stash;
    if (
           defined $stash->{handler}
        || defined $stash->{variant}
        || any { exists $RENDERER_ARGUMENT{$_} || index( $_, 'mojo.' ) == 0 }
        keys %values
      )
    {
        return $self->fallback->( $controller, @arguments );
    }

    my $format = $stash->{format} || $self->renderer->default_format;
    my $found  = $self->templates->{"$name.$format"} //=
      $self->_template( $name, $format );
    return $self->fallback->( $controller, @arguments ) if !$found;

    my ( $template, $source ) = @{$found};
    local @{$stash}{ keys %values } = values %values;
    delete local $stash->{layout};
    delete local $stash->{extends};

    # The template's controller and messages for the time of its render: an
    # include inside it sets its own and gives these back when it is done.
    ## no critic (Variables::ProhibitLocalVars)
    local $CONTROLLER = $controller;
    local $TEXT =
        $self->messages
      ? $self->_text( $stash->{ui_locale} || $controller->ui_locale )
      : undef;
    ## use critic
    my $output =
        $template->compiled
      ? $template->process($stash)
      : $template->render( $source, $stash );
    croak $output if ref $output;

    return Mojo::ByteStream->new($output);
}

# True once the partial has been compiled for the format, HTML by default.
sub is_compiled ( $self, $name, $format = 'html' ) {
    my $found = $self->templates->{"$name.$format"};

    return $found && $found->[0]->compiled ? 1 : 0;
}

# Removes the partials' own package, with the helpers exported into it and
# the code of every template compiled there, as Mojolicious's EP renderer
# removes its own.
sub DESTROY ($self) {
    if ( $self->{namespace} ) {
        delete_package( $self->{namespace} );
    }

    return;
}

# The template an EP partial is compiled from, read as the renderer reads
# it (its paths, its encoding) and compiled with EP's options. False for a
# template that is not an EP file on the renderer's paths.
#
# A message is the same for the life of the process, so <%= t('key') %>
# reads it from the locale's table of escaped plain messages, which is what
# the call would write, and calls t only for a key the table lacks: one that
# falls back to English, is missing or interpolates, and logs as before.
sub _template ( $self, $name, $format ) {
    my $renderer = $self->renderer;
    my $options  = { template => $name, format => $format };
    my $handler  = $renderer->template_handler($options) // q{};
    return 0 if $handler ne 'ep';

    my $path = $renderer->template_path( { %{$options}, handler => 'ep' } );
    return 0 if !defined $path;

    my $source = decode( $renderer->encoding, Mojo::File->new($path)->slurp )
      // croak qq{Template "$path" has invalid encoding};
    if ( $self->messages ) {
        $source =~ s{$TRANSLATION}
          {<%= \$GPForum::Web::Partials::TEXT->{'$1'} // t('$1') %>}gmsx;
    }

    $self->_export_helpers;
    my $template = Mojo::Template->new(
        auto_escape => 1,
        namespace   => $self->namespace,
        prepend     => 'my $self = my $c = $' . __PACKAGE__ . '::CONTROLLER;',
        vars        => 1,
    )->name(qq{template "$name.$format.ep"});

    return [ $template, $source ];
}

# The locale's plain messages, escaped once, as the values an expression
# writes as they are.
sub _text ( $self, $locale ) {
    return $self->texts->{$locale} //= do {
        my $plain = $self->messages->($locale);
        +{
            map { $_ => Mojo::ByteStream->new( xml_escape( $plain->{$_} ) ) }
              keys %{$plain}
        };
    };
}

sub _export_helpers ($self) {
    return if $self->exported;

    my $helpers   = $self->renderer->helpers;
    my $namespace = $self->namespace;
    for my $method ( grep { /\A\w+\z/msx } keys %{$helpers} ) {
        my $helper = $helpers->{$method};
        monkey_patch $namespace, $method,
          sub { return $CONTROLLER->$helper(@_); };
    }
    $self->exported(1);

    return;
}

1;

__END__

=head1 NAME

GPForum::Web::Partials - Partial templates compiled once and run without a render per include.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $partials = GPForum::Web::Partials->new(
        renderer => $app->renderer,
        fallback => $app->renderer->helpers->{include},
        messages => sub ($locale) { return $i18n->plain_messages($locale) },
    );
    $app->helper( include => sub ( $c, @arguments ) {
        return $partials->include( $c, @arguments );
    } );

=head1 DESCRIPTION

Behind the C<include> helper. A partial -- C<include 'name', key =E<gt> value>
for an EP template on the renderer's paths -- is compiled once per process,
with the options Mojolicious's EP renderer uses (auto-escaping, the stash as
variables, C<$c> and C<$self> as the controller, every helper as a
function), and run with its values set on the stash for the time of the
render, and C<layout> and C<extends> removed, as Mojolicious's C<include>
does. The output is a L<Mojo::ByteStream>. A failing template dies with the
exception the renderer's would.

What differs is what an include does not do: it emits no C<before_render>
hook, writes no trace line to the log and does not look its template up
again. Any other include -- the C<include %options> form, a C<format>,
C<handler>, C<variant>, C<layout>, C<extends>, C<inline> or C<template>
argument, a stash C<handler> or C<variant>, a template the file system does
not hold as EP -- goes to C<fallback>, Mojolicious's own C<include>.

With C<messages>, each C<< <%= t('key') %> >> reads the key from a table of
the locale's plain messages, escaped once per process, and calls C<t> only
for a key the table lacks; the text written is the same.

=head1 SUBROUTINES/METHODS

=head2 include

Takes the controller, a partial's name and its values. Returns the rendered
partial as a L<Mojo::ByteStream>, or what the fallback returns.

=head2 is_compiled

Takes a partial's name and optionally a format (C<html>). True once that
partial has been compiled.

=head1 DIAGNOSTICS

A template that does not compile, or dies while rendering, dies with the
L<Mojo::Exception> Mojo::Template returns. A template file that is not valid
in the renderer's encoding croaks C<Template "PATH" has invalid encoding>.

=head1 CONFIGURATION AND ENVIRONMENT

C<renderer> and C<fallback> are required. C<messages>, optional, takes a
locale and returns a hash reference of its plain messages by key. The
compiled partials live in their own package (C<namespace>), removed with the
object.

=head1 DEPENDENCIES

L<Carp>, L<Const::Fast>, L<GPForum::Base>, L<Mojo::Base>,
L<Mojo::ByteStream>, L<Mojo::File>, L<Mojo::Template>, L<Mojo::Util>,
L<Symbol>.

=head1 INCOMPATIBILITIES

Helpers are exported into the partials' package when the first partial
compiles, as Mojolicious's EP renderer exports them at its first render: a
helper added later is not seen by templates.

=head1 BUGS AND LIMITATIONS

A partial's variables are the stash keys present when it first compiled, as
with the renderer: a value a partial may not be given is read with C<stash>.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause.

=cut
