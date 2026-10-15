# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
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

# Shipped search versions remain installed during an upgrade (ADR 0126,
# section 2). The runtime role receives only the current catalogue versions.
const my %RETAINED => (
    forum_write_command_v1      => 0,
    forum_write_command_v2      => 1,
    forum_create_reply_v1       => 0,
    forum_create_reply_v2       => 1,
    forum_list_categories_v1    => 0,
    forum_list_categories_v2    => 1,
    forum_resolve_viewer_v1     => 0,
    forum_resolve_viewer_v2     => 1,
    moderation_target_v1        => 0,
    moderation_target_v2        => 1,
    moderation_target_update_v1 => 0,
    moderation_target_update_v2 => 1,
    portability_export_parts_v1 => 0,
    portability_export_parts_v2 => 1,
    portability_export_parts_v3 => 0,
    portability_export_parts_v4 => 1,
    portability_export_parts_v5 => 0,
    portability_export_parts_v6 => 1,
    identity_update_user_v1     => 0,
    identity_update_user_v2     => 1,
    privacy_update_v1           => 0,
    privacy_update_v2           => 1,
    privacy_revoke_user_v1      => 0,
    privacy_revoke_user_v2      => 1,
    privacy_revoke_user_v3      => 0,
    privacy_revoke_user_v4      => 1,
    search_ranked_v1            => 0,
    search_ranked_v2            => 1,
    search_ranked_v3            => 0,
    search_ranked_v4            => 1,
    search_ranked_v5            => 0,
    search_ranked_v6            => 1,
    search_autocomplete_v1      => 0,
    search_autocomplete_v2      => 1,
    search_autocomplete_v3      => 0,
    search_autocomplete_v4      => 1,
);

const my $FUNCTIONS_SQL => join q{ },
  'SELECT p.proname AS name,',
  'pg_get_function_identity_arguments(p.oid) AS arguments,',
  'p.prosecdef AS definer, p.proconfig AS config,',
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
# that the catalogue does not call, apart from the core_ helpers the
# functions share and explicitly retained older versions. Sections 1 and 7:
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

# Every installed function remains classified and keeps its security invariants.
sub _check_live_invariants ( $catalogue, $functions ) {
    my %called =
      map {
        ( $catalogue->function($_)->{function} =~ /\A api [.] (\w+)/msx )[0] =>
          1
      } @{ $catalogue->names };
    my %implementations;
    for my $name ( @{ $catalogue->names } ) {
        my $entry = $catalogue->function($name);
        $implementations{ $name . '_v' . ( $entry->{version} - 1 ) } = 1;
    }
    for my $name ( sort keys %{$functions} ) {
        ok(
            $called{$name}
              || $implementations{$name}
              || $name =~ /\A core_/msx
              || exists $RETAINED{$name},
            "api.$name is called, shared or retiring"
        );
        my $found = $functions->{$name};
        is(
            $found->{definer} ? 1 : 0,
            $called{$name}
              || ( exists $RETAINED{$name} && $RETAINED{$name} ) ? 1 : 0,
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

sub _type_name ($type) {
    return
      scalar $dbh->selectrow_array( 'SELECT ?::regtype::text', undef, $type );
}

1;
