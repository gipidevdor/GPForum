# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use SQL::Abstract;
use SQL::Abstract::Tree;
use Test::More;

our $VERSION = '0.001';

# These upstream fixes postdate the latest published CPANSA database. Keep
# executable regression cases until advisory scanning can enforce them too.
const my $PAYLOAD   => 'display_name, is_staff = 1';
const my $MEMBER_ID => 7;

my $builder = SQL::Abstract->new;
is_deeply(
    [
        $builder->update(
            'members',
            { display_name => [$PAYLOAD] },
            { id           => $MEMBER_ID }
        )
    ],
    [
        'UPDATE members SET display_name = ? WHERE id = ?', [$PAYLOAD],
        $MEMBER_ID
    ],
    'CVE-2026-121265: repeated field values stay bound during updates'
);
is_deeply(
    [ $builder->generate( 'update members', { display_name => [$PAYLOAD] } ) ],
    [ 'UPDATE MEMBERS SET display_name = ?', [$PAYLOAD] ],
    'CVE-2026-121265: generate also binds array values (fixed in 2.000003)'
);

const my $CONDITION => '1 OR 1=1';
is_deeply(
    [
        $builder->select(
            'posts',
            [
                {
                    -select => {
                        select => 'display_name',
                        from   => 'members',
                        where  => { id => $CONDITION },
                    }
                }
            ]
        )
    ],
    [
        'SELECT (SELECT display_name FROM members WHERE id = ?) FROM posts',
        $CONDITION
    ],
    'CVE-2026-121007: nested statements keep condition values bound'
);

my $error;
try {
    $builder->select( 'members',
        [ { -func => [ 'count; DROP TABLE members', 'id' ] } ] );
}
catch ($exception) {
    $error = $exception;
};
like(
    $error // q{},
    qr/Possible [ ] SQL [ ] injection [ ] attempt/msx,
    'CVE-2026-121009: explicit function names pass the injection guard'
);

my $tree = SQL::Abstract::Tree->new( { profile => 'html' } );
my $html = $tree->format( 'SELECT id FROM members WHERE display_name = ?',
    ['<script>alert(1)</script>'] );
unlike( $html, qr/<script>/msx,
    'CVE-2026-121008: SQL diagnostics contain no live script' );
like( $html, qr/&lt;script&gt;/msx,
    'SQL diagnostics preserve the escaped value' );

done_testing();

1;
