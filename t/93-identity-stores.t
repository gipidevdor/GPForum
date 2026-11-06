# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Identity::Support;
use Test::More;

our $VERSION = '0.001';

my $support = GPForum::Service::Identity::Support->new;
is(
    $support->normalize_identifier('GPForum_Contributors@Example.TEST'),
    'gpforum_contributors@example.test',
    'support normalizes identifiers'
);
is( $support->column( { id => 'user-1' }, 'id' ),
    'user-1', 'support reads hash columns' );
ok( !defined $support->hash_value(undef), 'empty hashes are not stored' );
my $hash = $support->hash_value('198.51.100.10');
ok( $hash && $hash ne '198.51.100.10',
    'support hashes identifiers before persistence' );

done_testing();

1;
