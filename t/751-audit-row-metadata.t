# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::ResultRow::Audit;
use Test::More;

our $VERSION = '0.001';

# An audit row's metadata, as the viewers and the diagnostics read it: the
# hash the call layer decoded is handed back as it is, and the jsonb's text,
# which the connection hands back as characters, is decoded as characters.
my $decoded = GPForum::Infrastructure::ResultRow::Audit->from(
    { audit_id => 'audit-1', metadata => { slug => 'news' } } );
is_deeply(
    $decoded->get_inflated_column('metadata'),
    { slug => 'news' },
    'a decoded hash is the metadata'
);

my $text = GPForum::Infrastructure::ResultRow::Audit->from(
    {
        audit_id => 'audit-2',
        metadata =>
qq({"reason": "perch\N{LATIN SMALL LETTER E WITH ACUTE} \N{EM DASH} no"}),
    }
);
is_deeply(
    $text->get_inflated_column('metadata'),
    { reason => "perch\N{LATIN SMALL LETTER E WITH ACUTE} \N{EM DASH} no" },
    'text beyond ASCII decodes as it was written'
);
is( $text->get_inflated_column('audit_id'),
    'audit-2', 'and another column is read as it is' );
is(
    GPForum::Infrastructure::ResultRow::Audit->from( { metadata => undef } )
      ->get_inflated_column('metadata'),
    undef,
    'no metadata is none'
);

done_testing();

1;
