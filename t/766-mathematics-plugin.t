# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Test::More;
use Test::Fatal;
use Const::Fast;
use Mojo::DOM;
use lib 'lib';
use GPForum::Service::Integration::Registry;
use GPForum::Service::Integration::Mathematics;
use GPForum::Service::Plugin::Contract;
use GPForum::Service::Forum::BodyRenderer;

our $VERSION = '0.001';
const my $SPAN_LIMIT    => 50;
const my $MANY_FORMULAS => 60;
const my $FORMULA_LIMIT => 4_096;

my $plugins =
  GPForum::Service::Integration::Registry->new( enabled => ['mathematics'] );
my $renderer =
  GPForum::Service::Forum::BodyRenderer->new( math_plugins => $plugins );
ok( $plugins->math_enabled,
    'mathematics is an independent enabled capability' );
is_deeply( $plugins->frame_origins, [],
    'equations permit no external frame origins' );

for my $source ( q{$x_i^2$}, q{\(x_i^2\)}, q{$$x_i^2$$}, q{\[x_i^2\]} ) {
    my $dom = Mojo::DOM->new( $renderer->render_safe($source) );
    is( $dom->at('.math-expression code')->text,
        'x_i^2', 'LaTeX remains intact within each supported delimiter' );
}
my $dom = Mojo::DOM->new(
    $renderer->render_safe(
        "**Energy \$E=mc^2\$**\n\n\$\$\n\\frac{a_1}{b_2}\n\$\$")
);
is( $dom->at('strong .math-expression code')->text,
    'E=mc^2', 'ordinary emphasis can enclose a formula' );
is( $dom->at('[data-math-display="block"] code')->text,
    "\n\\frac{a_1}{b_2}\n",
    'display formulas preserve line breaks and underscores' );
for my $source (
    '`$x$`',  "```tex\n\$x\$\n```", q{\$x\$}, q{$5 and $10}, q{$ unfinished},
    q{$ x $}, q{\(unfinished}, q{$} . ( 'x' x ( $FORMULA_LIMIT + 1 ) ) . q{$},
  )
{
    is(
        Mojo::DOM->new( $renderer->render_safe($source) )
          ->find('.math-expression')
          ->size,
        0,
'code, escaped, currency, unmatched and oversized formulas remain ordinary source'
    );
}
my $html = $renderer->render_safe(q{$\text{<script>alert(1)</script>}$});
unlike( $html, qr/<script/msx, 'user LaTeX cannot become trusted HTML' );
like( $html, qr/&lt;script&gt;/msx, 'formula source is escaped by core' );
my $many = join "\n\n", (q{$x$}) x $MANY_FORMULAS;
is(
    Mojo::DOM->new( $renderer->render_safe($many) )
      ->find('.math-expression')
      ->size,
    $SPAN_LIMIT,
    'the formula bound applies to the entire post across paragraphs'
);
my $plain = GPForum::Service::Forum::BodyRenderer->new;
for my $prefix (qw(first second)) {
    my $body     = "$prefix\n\n$many";
    my $rendered = $renderer->render_safe($body);
    is( Mojo::DOM->new($rendered)->find('.math-expression')->size,
        $SPAN_LIMIT,
        'each distinct body receives its complete formula budget' );
    is( $renderer->render_safe($body),
        $rendered,
        'a warmed body preserves the bounded mathematical rendering' );
}
my $switch_body  = q{switch $x_i$};
my $enabled_html = $renderer->render_safe($switch_body);
$renderer->math_plugins(undef);
is(
    $renderer->render_safe($switch_body),
    $plain->render_safe($switch_body),
    'switching off selects the plain variant on the same renderer'
);
$renderer->math_plugins($plugins);
is( $renderer->render_safe($switch_body),
    $enabled_html,
    'switching back selects the previously rendered mathematical variant' );
is(
    $renderer->render_safe(q{[link](https://example.test/$x$)}),
    $plain->render_safe(q{[link](https://example.test/$x$)}),
    'dollar signs inside a Markdown link target never become markup in href'
);
unlike( $plain->render_safe(q{$x_i$}),
    qr/math-expression/msx,
    'disabling preserves plain source through the shared renderer cache' );
like( $renderer->render_safe(q{$x_i$}),
    qr/math-expression/msx,
    'an enabled renderer selects its own cache variant' );
my $collision = 'GPFORUMMATHPLACEHOLDER0END $x$';
like(
    $renderer->render_safe($collision),
    qr/GPFORUMMATHPLACEHOLDER0END/msx,
    'literal user text cannot collide with core placeholders'
);

my $api      = GPForum::Service::Plugin::Contract->new;
my $module   = GPForum::Service::Integration::Mathematics->new;
my $manifest = $api->manifest_v1( $module->manifest_v1 );
my $request  = $api->math_request_v1( { api_version => 1, source => q{$x$} } );
ok( exception { $request->{source} = 'changed' },
    'math requests are immutable' );
my $valid = $module->prepare_math_v1($request);
ok(
    $api->math_response_v1( $manifest, $request, $valid ),
    'math response uses validated source spans only'
);

for my $bad (
    +{ %{$valid}, html     => '<script>x</script>' },
    +{ %{$valid}, provider => 'youtube' },
    +{
        %{$valid},
        spans => [
            {
                start   => 0,
                length  => 3,
                source  => 'forged',
                display => 'inline'
            }
        ]
    },
    +{
        %{$valid},
        spans => [
            { start => 0, length => 3, source => 'x', display => 'arbitrary' }
        ]
    },
    +{
        %{$valid},
        spans =>
          [ { start => '0', length => 3, source => 'x', display => 'inline' } ]
    },
    +{
        %{$valid},
        spans =>
          [ { start => 0, length => 9, source => 'x', display => 'inline' } ]
    },
  )
{
    ok(
        exception { $api->math_response_v1( $manifest, $request, $bad ) },
'extra fields, forged sources, invalid ranges and string offsets are rejected'
    );
}
ok(
    exception {
        $api->math_request_v1(
            { api_version => 1, source => q{x}, controller => {} } )
    },
    'the mathematics API receives no core object'
);
ok(
    exception {
        $api->manifest_v1( { %{$manifest}, url_hosts => ['example.test'] } )
    },
    'a local math provider cannot request remote origins'
);

done_testing();

1;
