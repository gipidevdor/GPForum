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

# What a function body calls of api, to follow from the entry points.
const my $CALLED => qr/\b api [.] (\w+) \b/msx;

# Migration 1024 retains these shipped entry points for the previous workers.
const my @RETAINED => qw(
  moderation_active_suspension_v2 moderation_can_participate_v2
);

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
# 0150: the 1.0 baseline keeps nothing for an earlier release). Sections 1 and 7:
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

for my $retained (@RETAINED) {
    ok( $function{$retained},
        "api.$retained remains callable by older workers" );
    is(
        $function{$retained}{arguments},
        'p_user_id uuid, p_now text',
        "api.$retained retains its shipped argument types"
    );
}

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
    @called{@RETAINED} = (1) x @RETAINED;
    my %reached;
    my @next = grep { $functions->{$_} } sort keys %called;
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

sub _type_name ($type) {
    return
      scalar $dbh->selectrow_array( 'SELECT ?::regtype::text', undef, $type );
}

1;
