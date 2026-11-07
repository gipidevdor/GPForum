# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'script/lib';
require GPForum::Tool::CartonHTTPS;

our $VERSION = '0.001';

const my $POLICY => 'GPForum::Tool::CartonHTTPS';
is_deeply(
    [
        $POLICY->arguments(
            '--mirror',      'https://mirror.example.test/',
            '--mirror',      'http://cpan.metacpan.org/',
            '--mirror',      'http://backpan.perl.org/',
            '--installdeps', q{.},
        )
    ],
    [
        '--mirror',      'https://mirror.example.test/',
        '--mirror',      'https://cpan.metacpan.org/',
        '--mirror',      'https://backpan.perl.org/',
        '--installdeps', q{.},
        '--mirror-only'
    ],
'a failed primary mirror can only fall back to HTTPS, with no HTTP metadata discovery'
);
is_deeply(
    [ $POLICY->arguments( '--mirror=/private/tmp/cache', '--no-mirror-only' ) ],
    [ '--mirror', '/private/tmp/cache', '--no-mirror-only', '--mirror-only' ],
'local bundles remain local and cannot enable the default HTTP metadata service'
);
is_deeply(
    [ $POLICY->arguments( '--mirror', 'file:///private/tmp/cache' ) ],
    [ '--mirror', 'file:///private/tmp/cache', '--mirror-only' ],
    'file mirrors remain supported'
);

for my $mirror ( 'http://mirror.example.test/', 'ftp://mirror.example.test/' ) {
    my $error;
    try { $POLICY->arguments( '--mirror', $mirror ); }
    catch ($caught) { $error = $caught; };
    like(
        $error // q{},
        qr/must [ ] use [ ] HTTPS/msx,
        'unprotected custom mirrors are refused'
    );
}
my $error;
try { $POLICY->arguments('--mirror'); }
catch ($caught) { $error = $caught; };
like(
    $error // q{},
    qr/needs [ ] a [ ] URL/msx,
    'a missing mirror URL fails closed'
);

done_testing();

1;
