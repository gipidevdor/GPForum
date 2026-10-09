# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use English qw(-no_match_vars);
use Test::Exception;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::SqlFunctionCatalogue;
use GPForum::Schema;
use GPForum::Service::Operations::DbQueryStats;
use GPForum::Test::SqlFunctionHandle;

our $VERSION = '0.001';

# ADR 0126, section 8: the one layer that sends SQL. It takes a function's
# catalogue name and its parameters by name, makes one statement of the
# catalogue's, binds the values in the function's order with their types,
# counts the call as one statement, and hands back plain rows.
my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new(
    entries => {
        probe_lookup => {
            version    => 3,
            parameters => [
                item_id  => 'uuid',
                label    => 'text',
                active   => 'boolean',
                metadata => 'jsonb',
                tags     => 'text[]',
            ],
            json => ['document'],
        },
    },
);
my $id = '018f1004-0001-7000-8000-000000000001';

subtest 'the catalogue names the version and builds the statement' => sub {
    my $entry = $catalogue->function('probe_lookup');
    is( $entry->{function}, 'api.probe_lookup_v3', 'the versioned name' );
    is(
        $entry->{sql},
        'SELECT * FROM api.probe_lookup_v3(?::uuid, ?::text, ?::boolean,'
          . ' ?::jsonb, ?::text[])',
        'one statement, each value cast to its type'
    );
    is( $catalogue->function('probe_lookup'),
        $entry, 'built once per catalogue' );
    is_deeply( $catalogue->names, ['probe_lookup'], 'the names listed' );
    throws_ok { $catalogue->function('missing') }
    'GPForum::X::Argument', 'an unlisted name is the caller\'s mistake';
    my $release = GPForum::Infrastructure::SqlFunctionCatalogue->new;

    for my $name ( @{ $release->names } ) {
        my $listed = $release->function($name);
        like(
            $listed->{function},
            qr/\A api [.] \Q$name\E _v [1-9]\d* \z/msx,
            "the release's $name is a version of it"
        );
        is(
            scalar @{ $listed->{names} },
            scalar @{ $listed->{types} },
            'and names each of its parameters'
        );
    }
};

subtest 'values are bound by name, in order, with their types' => sub {
    my $handle =
      GPForum::Test::SqlFunctionHandle->new(
        rows => [ { document => '{"b":[1],"a":null}', item_id => $id } ] );
    my $rows = _layer($handle)->rows(
        'probe_lookup',
        {
            active   => q{},
            item_id  => $id,
            label    => undef,
            metadata => { z => 1, a => [ 'x', undef ] },
            tags     => [qw(a b)],
        }
    );
    is_deeply(
        $handle->executed,
        [ [ $id, undef, 0, '{"a":["x",null],"z":1}', [qw(a b)] ] ],
        'NULL for undef, 0 for a false boolean, canonical JSON for a hash'
    );
    is_deeply(
        $handle->prepared,
        [ $catalogue->function('probe_lookup')->{sql} ],
        'the catalogue\'s statement, prepared through the cache'
    );
    is_deeply(
        $rows,
        [ { document => { a => undef, b => [1] }, item_id => $id } ],
        'plain rows, with the json column decoded'
    );
};

subtest 'the statement a call would send, without sending it' => sub {
    my $handle = GPForum::Test::SqlFunctionHandle->new;
    is_deeply(
        _layer($handle)->statement( 'probe_lookup', _values() ),
        [
            $catalogue->function('probe_lookup')->{sql},
            $id, 'probe', 1, '{}', [],
        ],
        'the catalogue\'s statement and the values as rows binds them'
    );
    is_deeply( $handle->executed, [], 'and nothing is sent' );
};

subtest 'a parameter left out or unknown is refused before any call' => sub {
    my $handle = GPForum::Test::SqlFunctionHandle->new;
    my $layer  = _layer($handle);
    throws_ok {
        $layer->rows( 'probe_lookup', { item_id => $id } )
    }
    qr/api[.]probe_lookup_v3 [ ] needs [ ] label/msx, 'a missing parameter';
    throws_ok {
        $layer->rows( 'probe_lookup', { %{ _values() }, itemid => $id } )
    }
    qr/has [ ] no [ ] itemid/msx, 'an unknown one';
    is_deeply( $handle->executed, [], 'and nothing was sent' );
};

subtest 'a uuid PostgreSQL would refuse is not sent' => sub {
    my $handle =
      GPForum::Test::SqlFunctionHandle->new( rows => [ { item_id => $id } ] );
    is_deeply(
        _layer($handle)
          ->rows( 'probe_lookup', { %{ _values() }, item_id => 'not-a-uuid' } ),
        [],
        'no rows'
    );
    is_deeply( $handle->executed, [], 'and no call' );
    is(
        _layer($handle)
          ->row( 'probe_lookup', { %{ _values() }, item_id => uc "{$id}" } )
          ->{item_id},
        $id,
        'a spelling PostgreSQL reads is sent'
    );
};

subtest 'each call is one statement to the statistics' => sub {
    my $stats  = GPForum::Service::Operations::DbQueryStats->new;
    my $handle = GPForum::Test::SqlFunctionHandle->new( debugobj => $stats );
    my $layer  = _layer($handle);
    for ( 1 .. 2 ) {
        $layer->rows( 'probe_lookup', _values() );
    }
    is( $stats->{total_queries}, 2, 'two calls, two statements' );
};

subtest 'SQLSTATEs map to the exceptions of ADR 0118' => sub {
    my %raised = (
        '22023' => [
            'ERROR:  item_id is required [for Statement "SELECT"]',
            'GPForum::X::Argument'
        ],
        '23505' => [
            'ERROR:  duplicate key value violates unique constraint "x_pkey"',
            'GPForum::X::Conflict'
        ],
    );
    for my $state ( sort keys %raised ) {
        my ( $message, $class ) = @{ $raised{$state} };
        my $handle = GPForum::Test::SqlFunctionHandle->new(
            error       => $message,
            error_state => $state,
        );
        throws_ok { _layer($handle)->rows( 'probe_lookup', _values() ) }
        $class, "$state is $class";
    }
    my $argument = GPForum::Test::SqlFunctionHandle->new(
        error       => "ERROR:  item_id is required\n[for Statement \"x\"]",
        error_state => '22023',
    );
    throws_ok { _layer($argument)->rows( 'probe_lookup', _values() ) }
    qr/\A ERROR: [ ]+ item_id [ ] is [ ] required \z/msx,
      'with the server\'s own sentence';
    my $timeout = GPForum::Test::SqlFunctionHandle->new(
        error       => 'ERROR:  canceling statement due to lock timeout',
        error_state => '55P03',
    );
    throws_ok { _layer($timeout)->rows( 'probe_lookup', _values() ) }
    qr/lock [ ] timeout/msx, 'any other error as DBI raised it';
    ok(
        !GPForum::X::Conflict->caught($EVAL_ERROR)
          && !GPForum::X::Argument->caught($EVAL_ERROR),
        'not wrapped'
    );
};

subtest 'only a DBIx::Class schema on PostgreSQL has a layer' => sub {
    ok(
        GPForum::Infrastructure::SqlFunction->for_schema(
            GPForum::Schema->connect('dbi:Pg:dbname=gpforum_never_connected')
        ),
        'a PostgreSQL schema has one, before it connects'
    );
    is(
        GPForum::Infrastructure::SqlFunction->for_schema(
            GPForum::Schema->connect('dbi:SQLite:dbname=:memory:')
        ),
        undef,
        'another driver has none'
    );
    is(
        GPForum::Infrastructure::SqlFunction->for_schema(
            GPForum::Test::SqlFunctionHandle->new
        ),
        undef,
        'nor has a test double'
    );
    is( GPForum::Infrastructure::SqlFunction->for_schema(undef),
        undef, 'nor nothing' );
    throws_ok { GPForum::Infrastructure::SqlFunction->new }
    'GPForum::X::Argument', 'the layer needs its schema';
};

subtest 'a function\'s row reads as the DBIx::Class row it replaces' => sub {
    my $row = GPForum::Infrastructure::ResultRow->from(
        { title => 'Hello', locked_at => undef } );
    is( $row->get_column('title'), 'Hello', 'get_column' );
    is_deeply(
        { $row->get_columns },
        { title => 'Hello', locked_at => undef },
        'get_columns'
    );
    is( $row->has_column_loaded('locked_at'), 1, 'a NULL column is loaded' );
    is( $row->has_column_loaded('slug'),      0, 'an absent one is not' );
    is( $row->get_column('slug'),             undef, 'and reads as undef' );
    is( GPForum::Infrastructure::ResultRow->from(undef),
        undef, 'no row is undef' );
};

done_testing();

sub _layer ($handle) {
    return GPForum::Infrastructure::SqlFunction->new(
        catalogue => $catalogue,
        schema    => $handle,
    );
}

sub _values {
    return {
        active   => 1,
        item_id  => $id,
        label    => 'probe',
        metadata => '{}',
        tags     => [],
    };
}

1;
