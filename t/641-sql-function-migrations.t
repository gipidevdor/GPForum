# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use English    qw(-no_match_vars);
use Mojo::File qw(path);
use Test::More;

use lib 'lib';

use GPForum::Migration::Plan;

use GPForum::Infrastructure::SqlFunctionCatalogue;

our $VERSION = '0.001';

# ADR 0126, sections 2, 4, 7 and 11, held for every function in schema api,
# in the 1.0 baseline and in every migration after it (ADR 0150): a version
# suffix and an area, CREATE FUNCTION and never CREATE OR REPLACE (a shipped
# version never changes under the previous release's workers), a pinned
# search_path and plan mode, the invoker implementations and narrow definer
# boundaries, EXECUTE revoked from PUBLIC, no dynamic SQL, the tables of
# public written with their schema, and a transactional migration that sets
# lock_timeout. A function the catalogue calls is created by a migration and
# never dropped, and every function is one the catalogue reaches: nothing in
# api is left that nothing calls.
const my @AREAS => qw(
  admin attachment community core forum identity moderation notification ops
  outbox partition portability privacy projection search session worker plugin
);
const my $AREA   => join q{|}, @AREAS;
const my $WORD   => qr/[[:lower:]] [[:lower:][:digit:]_]*/msx;
const my $SUFFIX => qr/_v [1-9] [[:digit:]]*/msx;
const my $NAME   => qr/\A (?:$AREA) _ $WORD $SUFFIX \z/msx;
const my $CREATE => qr/CREATE \s+ (?<replace>OR \s+ REPLACE \s+)? FUNCTION/imsx;
const my $CREATE_TABLE  => qr/CREATE \s+ TABLE \s+/imsx;
const my $IF_NOT_EXISTS => qr/IF \s+ NOT \s+ EXISTS \s+/imsx;
const my $TABLE_NAME    => qr/(?:public[.])? (\w+)/imsx;
const my $OPENING       => qr/$CREATE \s+ api [.] (?<name>\w+) \s* [(]/imsx;
const my $QUOTED   => qr/(?<quote> [\$] \w* [\$] ) (?<body> .*? ) \k<quote>/msx;
const my $FUNCTION => qr/$OPENING (?<head> .*? ) AS \s+ $QUOTED [^;]* ;/imsx;
const my $REVOKE => qr/REVOKE \s+ EXECUTE \s+ ON \s+ FUNCTION \s+ api [.]/imsx;
const my $FROM_PUBLIC => qr/\s* [(] [^)]* [)] \s+ FROM \s+ PUBLIC/imsx;
const my $SEARCH_PATH =>
  qr/SET \s+ search_path \s* = \s* pg_catalog, \s* pg_temp/imsx;
const my $PLAN_MODE =>
  qr/SET \s+ plan_cache_mode \s* = \s* force_(?:generic|custom)_plan/imsx;
const my $DROP =>
  qr/DROP \s+ FUNCTION \s+ (?:IF \s+ EXISTS \s+)? (?<dropped>api [.] \w+)/imsx;
const my $CALLED => qr/\b api [.] (\w+) \b/msx;

# ADR 0126, section 2, amended 2026-10-22: a shipped version never changes
# its result type, and a function that RETURNS SETOF public.<table> changes
# it whenever the table gains a column -- a prepared call of it on a live
# worker is then refused, "cached plan must not change result type". Every
# function names its columns instead: RETURNS TABLE, or a row type of api
# (ADR 0150).
const my $RETURNED => qr/(?:public [.])? (?<returned>\w+) \b (?! \s* [.])/msx;
const my $RETURNS  => qr/RETURNS \s+ (?:SETOF \s+)? $RETURNED/imsx;
const my $SEARCH_VERSION       => 10;
const my $LEGACY_REPLY_VERSION => 4;

# The boundaries a release keeps for the previous one's workers until a
# contract migration drops them (ADR 0126, section 2). Migration 1024 keeps
# the 1.0 suspension boundaries for workers that have not restarted yet.
# ADR 0156 amends ADR 0126, section 2: a chain discipline must change for
# every writer at once, the previous release's workers included, or two
# disciplines fork the chain, so migration 1035 replaces the four audit
# functions in place, signatures and result types unchanged. Nothing else
# may.
const my %REPLACED_IN_PLACE => (
    '1035_audit_chain_per_aggregate.sql' => {
        map { $_ => 1 }
          qw(core_append_audit_v1 core_shared_append_audit_v1
          core_record_audit_v1 ops_record_audit_v1)
    },
);

const my %RETAINED_BOUNDARIES => (
    forum_resolve_viewer         => [6],
    outbox_claim_ready           => [2],
    forum_thread_page_reads      => [4],
    forum_create_reply           => [4],
    forum_store_write            => [2],
    forum_write_command          => [4],
    ops_retention_purge          => [2],
    notification_subscribers     => [2],
    notification_unread_count    => [6],
    notification_list_inbox      => [6],
    forum_find_listed_post       => [2],
    forum_poll_change            => [2],
    privacy_revoke_user          => [ 22, 24 ],
    portability_export_parts     => [22],
    identity_register_command    => [2],
    identity_update_user         => [4],
    moderation_active_suspension => [2],
    moderation_can_participate   => [2],
);

my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new;
my %catalogued =
  map { $catalogue->function($_)->{function} => 1 } @{ $catalogue->names };
my %boundaries;
for my $name ( @{ $catalogue->names } ) {
    my $entry = $catalogue->function($name);
    my $retained =
      exists $RETAINED_BOUNDARIES{$name} ? $RETAINED_BOUNDARIES{$name} : [];
    for my $version ( $entry->{version}, @{$retained} ) {
        my @parameters = @{ $entry->{names} };
        if (   $name eq 'forum_create_reply'
            && $version == $LEGACY_REPLY_VERSION )
        {
            pop @parameters;
        }
        if ( $name eq 'identity_register_command' && $version == 2 ) {
            pop @parameters;
        }
        $boundaries{"${name}_v$version"} = {
            implementation => $name . '_v' . ( $version - 1 ),
            arguments      => join( q{, }, map { "p_$_" } @parameters ),
        };
    }
}
my @tables   = _tables();
my %is_table = map { $_ => 1 } @tables;

subtest 'the rules see what they are written for' => sub {
    my $bad = join "\n",
      'BEGIN;',
      'CREATE OR REPLACE FUNCTION api.forum_lookup(p uuid) RETURNS int',
      'LANGUAGE plpgsql SECURITY DEFINER AS $$',
      'BEGIN EXECUTE $q$SELECT 1$q$; PERFORM 1 FROM posts; RETURN 1; END;',
      '$$;', 'COMMIT;';
    my ( $problems, $created ) = _problems( 'bad.sql', $bad );
    is_deeply(
        $problems,
        [
            'bad.sql: no lock_timeout',
            'bad.sql: api.forum_lookup: CREATE OR REPLACE',
            'bad.sql: api.forum_lookup: EXECUTE revoked from PUBLIC nowhere',
            'bad.sql: api.forum_lookup: SECURITY DEFINER',
            'bad.sql: api.forum_lookup: dynamic SQL',
            'bad.sql: api.forum_lookup: no version suffix or area',
            'bad.sql: api.forum_lookup: plan_cache_mode not pinned',
            'bad.sql: api.forum_lookup: posts without its schema',
            'bad.sql: api.forum_lookup: search_path not pinned',
        ],
        'each rule, once'
    );
    is_deeply(
        [ sort keys %{$created} ],
        ['api.forum_lookup'],
        'and the function is seen'
    );

    for my $returns ( 'SETOF public.posts', 'SETOF posts', 'public.users' ) {
        my $rows = join "\n", 'BEGIN;', q{SET LOCAL lock_timeout = '1s';},
          "CREATE FUNCTION api.forum_rows_v1() RETURNS $returns",
          'LANGUAGE sql AS $$ SELECT * FROM public.posts $$;', 'COMMIT;';
        my ($refused) = _problems( 'rows.sql', $rows );
        ok( ( grep { /a [ ] table's [ ] row/msx } @{$refused} ),
            "RETURNS $returns is refused" );
    }
    for my $returns ( 'SETOF api.forum_row_v1', 'TABLE (a integer)', 'integer' )
    {
        my $rows = join "\n", 'BEGIN;',
          "CREATE FUNCTION api.forum_rows_v1() RETURNS $returns",
          'LANGUAGE sql AS $$ SELECT 1 $$;', 'COMMIT;';
        my ($named) = _problems( 'named.sql', $rows );
        ok(
            !( grep { /a [ ] table's [ ] row/msx } @{$named} ),
            "RETURNS $returns names its own columns"
        );
    }
};

subtest 'a shipped function is replaced in place only where ADR 0156 says' =>
  sub {
    my $replaced = join "\n", 'BEGIN;', q{SET LOCAL lock_timeout = '5s';},
'CREATE OR REPLACE FUNCTION api.core_append_audit_v1(p text) RETURNS jsonb',
      'LANGUAGE sql SET search_path = pg_catalog, pg_temp',
      'SET plan_cache_mode = force_generic_plan AS $$ SELECT NULL::jsonb $$;',
      'REVOKE EXECUTE ON FUNCTION api.core_append_audit_v1(text) FROM PUBLIC;',
      'COMMIT;';
    my ($allowed) =
      _problems( 'migrations/1035_audit_chain_per_aggregate.sql', $replaced );
    is_deeply( $allowed, [], 'the audit chain migration replaces its four' );
    my ($elsewhere) = _problems( 'migrations/1036_other.sql', $replaced );
    is_deeply(
        $elsewhere,
        [
'migrations/1036_other.sql: api.core_append_audit_v1: CREATE OR REPLACE'
        ],
        'another migration may not'
    );
    my ($other) = _problems(
        'migrations/1035_audit_chain_per_aggregate.sql',
        $replaced =~ s/core_append_audit_v1/core_other_step_v1/grmsx
    );
    is_deeply(
        $other,
        [
'migrations/1035_audit_chain_per_aggregate.sql: api.core_other_step_v1: CREATE OR REPLACE'
        ],
        'nor may it replace another function'
    );
  };

subtest 'only registered typed boundaries gain owner rights' => sub {
    my $head     = 'LANGUAGE sql SECURITY DEFINER';
    my $name     = "search_ranked_v$SEARCH_VERSION";
    my $boundary = $boundaries{$name};
    ok( $boundary, "the catalogue calls $name" );
    my $call =
        'SELECT * FROM api.'
      . $boundary->{implementation} . '('
      . $boundary->{arguments} . ');';
    ok( _boundary( $name, $head, $call ),
        'a registered boundary forwards all typed arguments' );
    ok( !_boundary( $name, $head, "$call SELECT 1;" ), 'extra SQL is refused' );
    my $other = $call =~ s/search_ranked/search_autocomplete/rmsx;
    ok(
        !_boundary( $name, $head, $other ),
        'a different implementation is refused'
    );
    my $missing = $call =~ s/p_permission_mode,\s*//rmsx;
    ok(
        !_boundary( $name, $head, $missing ),
        'dropping a typed argument is refused'
    );
    my $next = $SEARCH_VERSION + 2;
    ok(
        !_boundary(
            "search_ranked_v$next",
            $head,
            'SELECT * FROM api.search_ranked_v'
              . ( $next - 1 )
              . "($boundary->{arguments});"
        ),
        'an unregistered future version is refused'
    );
    ok(
        !_boundary(
            'core_helper_v2', $head, 'SELECT * FROM api.core_helper_v1();'
        ),
        'helpers cannot gain owner rights'
    );
};

subtest 'a function nothing calls is seen' => sub {
    my $created = {
        'api.forum_page_v2'   => 'SELECT * FROM api.forum_page_v1()',
        'api.forum_page_v1'   => 'SELECT * FROM api.core_rows_v1()',
        'api.core_rows_v1'    => 'SELECT 1',
        'api.forum_orphan_v1' => 'SELECT * FROM api.core_rows_v1()',
    };
    is_deeply(
        [ _unreached( $created, { 'api.forum_page_v2' => 1 } ) ],
        ['api.forum_orphan_v1'],
        'reached through the bodies, from what the catalogue calls'
    );
};

my ( @problems, %created );
for my $file ( @{ GPForum::Migration::Plan->new->files } ) {
    my ( $found, $created ) = _problems( $file, path($file)->slurp );
    push @problems, @{$found};
    %created = ( %created, %{$created} );
}
is_deeply( \@problems, [], 'every api function follows ADR 0126' );
ok(
    $created{'api.core_canonical_json_v1'},
    'the functions of the migrations are seen'
);
for my $function ( sort keys %catalogued ) {
    ok( exists $created{$function},
        "$function, which the catalogue calls, exists" );
}
my %entry_points = map { ( "api.$_" => 1 ) } keys %boundaries;
is_deeply( [ _unreached( \%created, \%entry_points ) ],
    [], 'and every api function is one the catalogue reaches' );

done_testing();

# A migration's problems, and the functions it creates with their bodies.
sub _problems ( $file, $sql ) {
    my $code = join "\n", grep { !/\A \s* --/msx } split /\n/msx, $sql;
    my ( @found, %made );
    if ( $code =~ $CREATE ) {
        if ( $sql =~ /\A -- [ ] gpforum:no-transaction \b/msx ) {
            push @found, "$file: a function in a no-transaction migration";
        }
        if ( $code !~ /SET \s+ LOCAL \s+ lock_timeout/imsx ) {
            push @found, "$file: no lock_timeout";
        }
    }
    my $base = path($file)->basename;
    my $allowed =
      exists $REPLACED_IN_PLACE{$base} ? $REPLACED_IN_PLACE{$base} : {};
    while ( $code =~ /$FUNCTION/gmsx ) {
        my %function = %LAST_PAREN_MATCH;
        if ( exists $allowed->{ $function{name} } ) {
            delete $function{replace};
        }
        push @found,
          _function_problems( "$file: api.$function{name}", \%function, $code );
        $made{"api.$function{name}"} = $function{body};
    }
    while ( $code =~ /$DROP/gmsx ) {
        my $dropped = $LAST_PAREN_MATCH{dropped};
        if ( $catalogued{$dropped} ) {
            push @found, "$file: drops $dropped, which the catalogue calls";
        }
    }

    return ( \@found, \%made );
}

sub _function_problems ( $label, $function, $code ) {
    my ( $name, $head, $body ) = @{$function}{qw(name head body)};
    my $revoked = qr/$REVOKE \Q$name\E $FROM_PUBLIC/imsx;
    my %rule    = (
        'CREATE OR REPLACE'                   => defined $function->{replace},
        'EXECUTE revoked from PUBLIC nowhere' => $code !~ $revoked,
        'SECURITY DEFINER' => ( $head =~ /SECURITY \s+ DEFINER/imsx )
          && !_boundary( $name, $head, $body ) ? 1 : 0,
        'dynamic SQL' => ( $body =~ /\b EXECUTE \b/imsx ) ? 1 : 0,
        'no version suffix or area'    => $name !~ $NAME,
        'plan_cache_mode not pinned'   => $head !~ $PLAN_MODE,
        'search_path not pinned'       => $head !~ $SEARCH_PATH,
        q{a table's row as its result} => _returns_table_row($head),
    );
    for my $table (@tables) {
        $rule{"$table without its schema"} =
          ( $body =~
              /\b (?:FROM|JOIN|UPDATE|INTO|TABLE) \s+ \Q$table\E \b/imsx )
          ? 1
          : 0;
    }

    return map { "$label: $_" } sort grep { $rule{$_} } keys %rule;
}

# A function that returns a table's row: RETURNS SETOF public.<table>,
# RETURNS <table>.
sub _returns_table_row ($head) {
    return 0 if $head !~ $RETURNS;

    return $is_table{ lc $LAST_PAREN_MATCH{returned} } ? 1 : 0;
}

# ADR 0127 allows only a typed, versioned forwarding boundary to acquire
# the owner's rights; helper bodies and arbitrary SQL remain INVOKER.
sub _boundary ( $name, $head, $body ) {
    return 0 if $name =~ /\A core_/msx || !exists $boundaries{$name};
    return 0 if $head !~ /LANGUAGE\s+sql\b/imsx;
    my $boundary       = $boundaries{$name};
    my $implementation = $boundary->{implementation};
    my $arguments      = join q{\s*,\s*},
      map { quotemeta } split /,\s*/msx, $boundary->{arguments};
    my $opening =
      qr/\A\s*SELECT\s+[*]\s+FROM\s+api[.]\Q$implementation\E\s*[(]\s*/imsx;
    my $closing = qr/[)]\s*;?\s*\z/msx;
    return $body =~ /$opening$arguments\s*$closing/imsx
      ? 1
      : 0;
}

# The functions no body leads to from the entry points: what the catalogue
# calls, then whatever their bodies call, and so on.
sub _unreached ( $created, $entry_points ) {
    my %reached;
    my @next = grep { exists $created->{$_} } sort keys %{$entry_points};
    while ( my $function = shift @next ) {
        next if $reached{$function}++;
        push @next, grep { exists $created->{$_} && !$reached{$_} }
          map { "api.$_" } $created->{$function} =~ /$CALLED/gmsx;
    }

    my @unreached = sort grep { !$reached{$_} } keys %{$created};

    return @unreached;
}

# The tables the migrations create, which a function names as public.NAME.
sub _tables {
    my %table;
    for my $file ( @{ GPForum::Migration::Plan->new->files } ) {
        my $sql = path($file)->slurp;
        while ( $sql =~ /$CREATE_TABLE (?:$IF_NOT_EXISTS)? $TABLE_NAME/gimsx ) {
            $table{ lc $1 } = 1;
        }
    }
    my @sorted = sort keys %table;

    return @sorted;
}

1;
