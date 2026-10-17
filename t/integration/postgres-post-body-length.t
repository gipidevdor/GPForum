# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use English qw(-no_match_vars);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Forum::BodyLength;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

# ADR 0140: the database holds every stored body to the limit Perl checks,
# so a writer that skips the composers cannot store one the renderer was not
# bounded for.

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the post body constraints';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh      = $database->dbh;
my $maximum  = GPForum::Service::Forum::BodyLength->maximum;

my %limits = map { $_->[0] => $_->[1] } @{
    $dbh->selectall_arrayref(
            'SELECT conrelid::regclass::text, '
          . q{(regexp_match(pg_get_constraintdef(oid), '<= (\d+)'))[1] }
          . 'FROM pg_catalog.pg_constraint '
          . q{WHERE contype = 'c' AND conrelid IN ('public.post_bodies'::regclass, }
          . q{'public.held_posts'::regclass, 'public.forum_drafts'::regclass) }
          . q{AND pg_get_constraintdef(oid) LIKE '%length(body_source)%'}
    )
};
is_deeply(
    \%limits,
    {
        forum_drafts => $maximum,
        held_posts   => $maximum,
        post_bodies  => $maximum,
    },
    'every table that keeps a body checks the one limit'
);

my ($body_id) = $dbh->selectrow_array(
    'SELECT body_id FROM public.post_bodies ORDER BY body_id LIMIT 1');
ok( $body_id, 'a seeded body' );
ok(
    $dbh->do(
        'UPDATE public.post_bodies SET body_source = repeat(?, ?) '
          . 'WHERE body_id = ?',
        undef,
        'x',
        $maximum,
        $body_id
    ),
    'a body at the limit is stored'
);
my $stored = eval {
    $dbh->do(
        'UPDATE public.post_bodies SET body_source = repeat(?, ?) '
          . 'WHERE body_id = ?',
        undef, 'x', $maximum + 1, $body_id
    );
};
like(
    $EVAL_ERROR,
    qr/post_bodies_body_source_length_check/msx,
    'one character more is refused'
);
ok( !$stored, 'and nothing is stored' );

done_testing();

1;
