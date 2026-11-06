# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunctionCatalogue;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

# What a function body calls of api, to follow from the entry points.
const my $CALLED => qr/\b api [.] (\w+) \b/msx;

const my $FUNCTIONS_SQL => join q{ },
  'SELECT p.proname AS name,',
  'pg_get_function_identity_arguments(p.oid) AS arguments,',
  'p.prosecdef AS definer, p.proconfig AS config, p.prosrc AS body,',
  'coalesce(p.proacl::text[], ARRAY[]::text[]) AS acl,',
  'p.proacl IS NULL AS default_acl',
  'FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace',
  q{WHERE n.nspname = 'api' ORDER BY p.proname};

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to check the function catalogue';
}

# ADR 0126, section 8: the catalogue names every function the release
# calls, its version and its parameters; the database the migrations made
# must have each, with those parameters in that order, and nothing in api
# that its entry points do not reach through the bodies they run (ADR
# 0150: the fresh baseline keeps nothing for an earlier release). Sections 1 and 7:
# api holds functions and row types only, and neither it nor any of its
# functions is open to PUBLIC; implementations run with their caller's
# rights, only API boundaries acquire owner rights, and all functions pin
# their search_path and plan mode.
my $database  = GPForum::Test::PgDatabase->fresh;
my $dbh       = $database->dbh;
my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new;
my %function =
  map { $_->{name} => $_ }
  @{ $dbh->selectall_arrayref( $FUNCTIONS_SQL, { Slice => {} } ) };
ok( scalar keys %function, 'api holds functions' );

for my $name ( @{ $catalogue->names } ) {
    my $entry     = $catalogue->function($name);
    my ($proname) = $entry->{function} =~ /\A api [.] (\w+) \z/msx;
    my $found     = $function{$proname};
    ok( $found, "$entry->{function} exists" ) or next;
    is(
        $found->{arguments},
        join(
            q{, },
            map { "p_$entry->{names}[$_] " . _type_name( $entry->{types}[$_] ) }
              0 .. $#{ $entry->{names} }
        ),
        "$entry->{function} takes the catalogue's parameters, in its order"
    );
}

_check_live_invariants( $catalogue, \%function );

is(
    scalar $dbh->selectrow_array(
            q{SELECT count(*) FROM pg_class c JOIN pg_namespace n}
          . q{ ON n.oid = c.relnamespace WHERE n.nspname = 'api'}
          . q{ AND c.relkind <> 'c'}
    ),
    0,
    'api holds no table, view, sequence or index'
);
is(
    scalar $dbh->selectrow_array(
        q{SELECT has_schema_privilege('public', 'api', 'USAGE')}),
    0,
    'and PUBLIC may not use it'
);

done_testing();

# Every installed function is one an entry point reaches, and keeps its
# security invariants.
sub _check_live_invariants ( $catalogue, $functions ) {
    my %called =
      map {
        ( $catalogue->function($_)->{function} =~ /\A api [.] (\w+)/msx )[0] =>
          1
      } @{ $catalogue->names };

    # Exact previous-release signatures remain supported during rolling deploys.
    my %previous = (
        moderation_transfer_picker_v2 => [
            [ actor          => 'uuid' ],
            [ source_id      => 'uuid' ],
            [ query          => 'text' ],
            [ after_position => 'bigint' ],
        ],
        admin_configuration_state_v2  => [],
        admin_configuration_change_v2 => [
            [ actor        => 'uuid' ],
            [ command      => 'uuid' ],
            [ expected     => 'bigint' ],
            [ section      => 'text' ],
            [ key          => 'text' ],
            [ operation    => 'text' ],
            [ value        => 'jsonb' ],
            [ request_hash => 'text' ],
        ],
        community_follow_feed_v2 => [
            [ actor        => 'uuid' ],
            [ member       => 'boolean' ],
            [ global_read  => 'boolean' ],
            [ category_ids => 'uuid[]' ],
            [ space_ids    => 'uuid[]' ],
            [ after_at     => 'timestamptz' ],
            [ after_id     => 'uuid' ],
            [ row_limit    => 'integer' ],
        ],
    );
    $previous{portability_export_parts_v32} = [ [ user_id => 'uuid' ] ];
    $previous{portability_export_parts_v30} = [ [ user_id => 'uuid' ] ];
    $previous{notification_delivery_plan_v4} =
      [ [ user_id => 'uuid' ], [ notification_type => 'text' ] ];
    $previous{notification_fanout_candidates_v4} = [
        [ target_type       => 'text' ],
        [ target_id         => 'uuid' ],
        [ notification_type => 'text' ],
        [ actor_id          => 'uuid' ],
        [ excluded_user_id  => 'uuid' ]
    ];
    $previous{notification_fanout_deliver_v2} = [ [ recipients => 'jsonb' ] ];
    $previous{admin_configuration_change_v4} =
      $previous{admin_configuration_change_v2};

    for my $name ( sort keys %previous ) {
        my $found = $functions->{$name};
        ok( $found, "previous boundary $name exists" ) or next;
        is(
            $found->{arguments},
            join( q{, },
                map { "p_$_->[0] " . _type_name( $_->[1] ) }
                  @{ $previous{$name} } ),
            "$name retains its exact shipped signature"
        );
        my ($version) = $name =~ /_v([[:digit:]]+)\z/msx;
        my $implementation =
          $name =~ s/_v[[:digit:]]+\z/'_v' . ($version - 1)/ermsx;
        my $arguments = join q{\s*,\s*},
          map { quotemeta "p_$_->[0]" } @{ $previous{$name} };
        my $opening =
          qr/\A\s*SELECT\s+[*]\s+FROM\s+api[.]\Q$implementation\E\s*[(]\s*/imsx;
        my $closing = qr/[)]\s*;?\s*\z/msx;
        like(
            $found->{body},
            qr/$opening$arguments\s*$closing/imsx,
            "$name forwards only to its shipped implementation"
        );
        $called{$name} = 1;
    }
    _check_implementation_calls( {%called}, $functions );
    my %reached;
    my @next      = grep { $functions->{$_} } sort keys %called;
    my $hooks_sql = <<'SQL';
SELECT DISTINCT p.proname FROM pg_trigger t
JOIN pg_proc p ON p.oid=t.tgfoid
JOIN pg_namespace n ON n.oid=p.pronamespace
JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace tables ON tables.oid=c.relnamespace
WHERE NOT t.tgisinternal AND n.nspname='api'
    AND tables.nspname='public' AND p.proname LIKE 'core_%'
SQL
    my $hooks = $dbh->selectcol_arrayref($hooks_sql);
    push @next, @{$hooks};

    while ( my $name = shift @next ) {
        next if $reached{$name}++;
        push @next,
          grep { $functions->{$_} && !$reached{$_} }
          $functions->{$name}{body} =~ /$CALLED/gmsx;
    }
    for my $name ( sort keys %{$functions} ) {
        ok( $reached{$name}, "api.$name is reached from an entry point" );
        my $found = $functions->{$name};
        is(
            $found->{definer} ? 1 : 0,
            $called{$name}    ? 1 : 0,
            "api.$name acquires owner rights only at the public entry point"
        );
        my %config = map { split /=/msx, $_, 2 } @{ $found->{config} // [] };
        is(
            $config{search_path},
            'pg_catalog, pg_temp',
            "api.$name pins its search_path"
        );
        like(
            $config{plan_cache_mode} // q{},
            qr/\A force_(?:generic|custom)_plan \z/msx,
            "api.$name pins its plan mode"
        );
        ok(
            !$found->{default_acl}
              && !grep( { /\A = /msx } @{ $found->{acl} } ),
            "api.$name is not open to PUBLIC"
        );
    }
    return;
}

# An implementation the current entry points reach calls implementations
# only: the boundaries kept for the previous release's workers go with a
# contract migration (ADR 0126, section 2), and one an implementation
# called would take that implementation with it.
sub _check_implementation_calls ( $current, $functions ) {
    my ( %reached, @calls );
    my @next = grep { $functions->{$_} } sort keys %{$current};
    while ( my $name = shift @next ) {
        next if $reached{$name}++;
        my @called =
          grep { $functions->{$_} } $functions->{$name}{body} =~ /$CALLED/gmsx;
        push @next, grep { !$reached{$_} } @called;
        next if $functions->{$name}{definer};
        push @calls, map { "$name calls $_" }
          grep { $functions->{$_}{definer} } @called;
    }
    is_deeply( \@calls, [],
        'no implementation the release reaches calls a boundary' );

    return;
}

sub _type_name ($type) {
    return
      scalar $dbh->selectrow_array( 'SELECT ?::regtype::text', undef, $type );
}

1;
