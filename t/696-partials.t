# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use lib 'lib';
use Const::Fast;
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Mojolicious;
use Test::Fatal;
use Test::More;

use GPForum::Web::Partials;

our $VERSION = '0.001';

# GPForum::Web::Partials renders an include without a render of its own.
# Each partial here is rendered both ways -- through it and through
# Mojolicious's own include -- and must come out the same, with the stash as
# it was before, and without the work it is there to save.

const my $EVERY_TRANSLATION => 3;

my %MESSAGES = (
    en => {
        'demo.plain'  => 'Tom & "Jerry" <b>',
        'demo.placed' => 'Post {position}',
    },
    it => { 'demo.plain' => 'Tom & "Gerry"' },
);
my %PLAIN = (
    en => { 'demo.plain' => $MESSAGES{en}{'demo.plain'} },
    it => { 'demo.plain' => $MESSAGES{it}{'demo.plain'} },
);

my $templates = tempdir( CLEANUP => 1 );
_template( 'demo/_card', <<~'EP' );
  %# A card: its title, the translations, a block, a nested partial.
  % my $badge = begin
  %   my ($text) = @_;
    <span class="badge"><%= $text %></span>
  % end
  <article id="<%= $card_id %>">
    <h2><%= $title %></h2>
    <p><%= t('demo.plain') %> / <%= t('demo.missing') %> / <%= t('demo.placed', { position => 3 }) %></p>
    <%= $badge->(stash('label') // 'none') %>
    <%= include 'demo/_leaf', leaf => $title %>
  </article>
  EP
_template( 'demo/_leaf', <<~'EP' );
  <em data-layout="<%= stash('layout') // 'none' %>"><%= $leaf %></em>
  EP
_template( 'demo/_named', <<~'EP' );
  <b><%= application_name %></b>
  EP
_template( 'demo/_broken', <<~'EP' );
  % die "the partial broke\n";
  EP

my ( $app, $counts ) = _application('first');
my $partials = $app->build_controller->ui_partials;

subtest 'a partial renders as Mojolicious renders it' => sub {
    for my $locale (qw(en it)) {
        my %stash = (
            card_id   => 'card-1',
            label     => '<i>',
            layout    => 'default',
            title     => q{"Quoted" & <tagged>},
            ui_locale => $locale,
        );
        my $fast = _rendered(
            $app,
            \%stash,
            sub ($c) {
                return $c->include( 'demo/_card', title => $stash{title} );
            }
        );
        my $slow = _rendered(
            $app,
            \%stash,
            sub ($c) {
                return $partials->fallback->(
                    $c, 'demo/_card', title => $stash{title}
                );
            }
        );
        is( $fast->{output}, $slow->{output},
            "the same markup in $locale, escaped the same way" );
        like( $fast->{output}, qr/data-layout="none"/msx,
            'without the layout, as an include has none' );
        is_deeply( $fast->{stash}, $slow->{stash},
            'the stash is left as the renderer leaves it' );
    }
};

subtest 'the work an include no longer does' => sub {
    my %stash = ( card_id => 'card-2', title => 'Card', ui_locale => 'en' );
    my $partial =
      sub ($c) { return $c->include( 'demo/_card', title => 'Card' ) };
    %{$counts} = ();
    _rendered( $app, \%stash, $partial );
    is( $counts->{before_render} // 0,
        0, 'no before_render, for the partial or the one it includes' );
    is( $counts->{t}, 2,
        'only the missing and the interpolated message call t' );
    ok( $partials->is_compiled('demo/_card'), 'the partial is compiled' );
    ok( $partials->is_compiled('demo/_leaf'), 'and the one it includes' );
    ok( !$partials->is_compiled( 'demo/_card', 'txt' ), 'for its format' );

    %{$counts} = ();
    _rendered(
        $app,
        \%stash,
        sub ($c) {
            return $partials->fallback->( $c, 'demo/_card', title => 'Card' );
        }
    );
    is( $counts->{before_render}, 1, 'the renderer emits one for its render' );
    is( $counts->{t},             $EVERY_TRANSLATION, 'and every t is a call' );
};

subtest 'what is left to the renderer' => sub {
    for my $case (
        [ 'the options form',   template => 'demo/_leaf', leaf => 1 ],
        [ 'a format',           'demo/_leaf', leaf => 1, format => 'txt' ],
        [ 'a layout',           'demo/_leaf', leaf => 1, layout => 'x' ],
        [ 'a missing template', 'demo/_nowhere' ],
      )
    {
        my ( $label, @arguments ) = @{$case};
        %{$counts} = ();
        _rendered(
            $app,
            { ui_locale => 'en' },
            sub ($c) { return $c->include(@arguments) }
        );
        is( $counts->{fallback}, 1, "$label goes to Mojolicious's include" );
    }
    my $missing = _rendered(
        $app,
        { ui_locale => 'en' },
        sub ($c) { return $c->include('demo/_nowhere') }
    );
    ok( !defined $missing->{output},
        'which renders nothing for a template not there' );
};

subtest 'a failing partial fails the render' => sub {
    my $error = exception {
        _rendered(
            $app,
            { ui_locale => 'en' },
            sub ($c) { return $c->include('demo/_broken') }
        );
    };
    isa_ok( $error, 'Mojo::Exception' );
    like( "$error", qr/the[ ]partial[ ]broke/msx, 'with its own message' );
};

subtest 'each application keeps its own helpers' => sub {
    my ($other) = _application('second');
    my $named = sub ($c) { return $c->include('demo/_named') };
    like( _rendered( $app, { ui_locale => 'en' }, $named )->{output},
        qr{<b>first</b>}msx, 'the first application' );
    like( _rendered( $other, { ui_locale => 'en' }, $named )->{output},
        qr{<b>second</b>}msx, 'the second' );
    like( _rendered( $app, { ui_locale => 'en' }, $named )->{output},
        qr{<b>first</b>}msx, 'and the first again, after the second compiled' );
    isnt(
        $partials->namespace,
        $other->build_controller->ui_partials->namespace,
        'each in a package of its own'
    );
};

done_testing();

sub _template ( $name, $source ) {
    my $file = path( $templates, "$name.html.ep" );
    $file->dirname->make_path;
    $file->spew( $source, 'UTF-8' );

    return;
}

# An application wired as Bootstrap::UI wires GPForum's: its include is the
# partials', t answers from a table, and the hook and the helpers count.
sub _application ($name) {
    my %counts;
    my $application = Mojolicious->new;
    $application->log->level('fatal');
    $application->renderer->paths( [$templates] );
    my $include = $application->renderer->helpers->{include};
    my $own     = GPForum::Web::Partials->new(
        renderer => $application->renderer,
        fallback => sub (@arguments) {
            ++$counts{fallback};
            return $include->(@arguments);
        },
        messages => sub ($locale) { return $PLAIN{$locale} // {} },
    );
    $application->helper(
        include => sub ( $c, @arguments ) {
            return $own->include( $c, @arguments );
        }
    );
    $application->helper( ui_partials      => sub { return $own; } );
    $application->helper( ui_locale        => sub { return 'en'; } );
    $application->helper( application_name => sub { return $name; } );
    $application->helper(
        t => sub ( $c, $key, $variables = {} ) {
            ++$counts{t};
            my $message = $MESSAGES{ $c->stash->{ui_locale} }{$key} // $key;
            $message =~ s{[{](\w+)[}]}{$variables->{$1} // q{}}gemsx;
            return $message;
        }
    );
    $application->hook( before_render => sub (@) { ++$counts{before_render} } );

    return ( $application, \%counts );
}

# Renders through the code given, in a controller with the stash given, and
# returns the output and the stash as it is afterwards.
sub _rendered ( $application, $stash, $code ) {
    my $controller = $application->build_controller;
    $controller->stash( %{$stash} );
    my $output = $code->($controller);
    my %after  = %{ $controller->stash };
    delete @after{ grep { /\A mojo[.]/msx } keys %after };

    return { output => defined $output ? "$output" : undef, stash => \%after };
}

1;
