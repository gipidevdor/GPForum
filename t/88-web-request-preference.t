# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Test::RequestPreferenceController;
use GPForum::Web::RequestPreference;

our $VERSION = '0.001';

my $preference = GPForum::Web::RequestPreference->new;

is(
    $preference->wants_json(
        GPForum::Test::RequestPreferenceController->new( format => 'json' )
    ),
    1,
    'format=json requests JSON'
);

is(
    $preference->wants_json(
        GPForum::Test::RequestPreferenceController->new(
            accept_header => 'application/json'
        )
    ),
    1,
    'application/json accept requests JSON'
);

# RFC 9110 12.5.1: quality first, then the more specific range; the order
# of the list is no preference, so a tie answers the HTML page.
my @negotiated = (
    [ 'text/html, application/json',     0, 'a tie answers HTML' ],
    [ 'application/json, text/html',     0, 'whatever the order' ],
    [ 'text/html, application/json;q=0', 0, 'q=0 refuses JSON' ],
    [
        'text/html;q=0.9, application/json;q=0.01', 0,
        'the higher quality wins'
    ],
    [ 'text/html;q=0.5, application/json', 1, 'JSON preferred by quality' ],
    [ 'application/json, text/plain, */*', 1, 'the exact type beats */*' ],
    [ q{*/*},                              0, 'a bare */* answers HTML' ],
    [ 'application/*',                     1, 'application/* excludes HTML' ],
    [ 'application/jsonl',   0, 'a type containing json is not JSON' ],
    [ 'application/ld+json', 0, 'nor is a +json suffix' ],
    [ 'APPLICATION/JSON; Q=0.8, text/html;q=0.7', 1, 'case is ignored' ],
);
for my $case (@negotiated) {
    my ( $accept, $json, $name ) = @{$case};
    is(
        $preference->wants_json(
            GPForum::Test::RequestPreferenceController->new(
                accept_header => $accept
            )
        ),
        $json,
        "$name ($accept)"
    );
}

is(
    $preference->wants_json(
        GPForum::Test::RequestPreferenceController->new(
            format        => 'html',
            accept_header => 'text/html',
        )
    ),
    0,
    'HTML format and accept does not request JSON'
);

is(
    $preference->wants_json(
        GPForum::Test::RequestPreferenceController->new()
    ),
    0,
    'missing format and accept does not request JSON'
);

done_testing();

1;
