# SPDX-FileCopyrightText: 2026 GPForum Contributors
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
# in the fresh-database baseline and in every migration after it (ADR 0150): a version
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
  outbox partition portability privacy projection search session worker plugin integration
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
const my $TRIGGER_TARGET =>
  qr/EXECUTE \s+ FUNCTION \s+ (api[.]core_\w+_v[[:digit:]]+) \s* [(]/imsx;
const my $SCHEMA_TRIGGER =>
  qr/CREATE \s+ TRIGGER \s+ \w+ \s+ .*? $TRIGGER_TARGET/imsx;

# ADR 0126, section 2, amended 2026-10-22: a shipped version never changes
# its result type, and a function that RETURNS SETOF public.<table> changes
# it whenever the table gains a column -- a prepared call of it on a live
# worker is then refused, "cached plan must not change result type". Every
# function names its columns instead: RETURNS TABLE, or a row type of api
# (ADR 0150).
const my $RETURNED => qr/(?:public [.])? (?<returned>\w+) \b (?! \s* [.])/msx;
const my $RETURNS  => qr/RETURNS \s+ (?:SETOF \s+)? $RETURNED/imsx;
const my $SEARCH_VERSION => 16;

# The advisory lock classes, each for one purpose, and the functions that
# take each (migration 1047 lists them): a class two purposes share
# serialises them against each other for nothing, as a member's digest and
# their first message to someone did. A function the release reaches takes
# only a class listed here for it.
const my $SETTINGS_WRITERS =>
  qr/automod_settings_set|review_settings_set|watched_word_add/msx;
const my %ADVISORY_CLASSES => (
    '2026100310' => qr/\A api[.]ops_record_event_v\d+ \z/msx,
    '2026100311' => qr/\A api[.]ops_record_audit_v\d+ \z/msx,
    '2026101501' => qr/\A api[.]moderation_ (?:$SETTINGS_WRITERS) _v\d+ \z/msx,
    '2026101502' => qr/\A api[.]moderation_automod_record_v\d+ \z/msx,
    '2026101701' => qr/\A api[.]community_message_start_v\d+ \z/msx,
    '2026102401' => qr/\A api[.]core_shared_append_audit_v\d+ \z/msx,
    '2026103101' => qr/\A api[.]notification_digest_record_v\d+ \z/msx,
    '2026110101' => qr/\A api[.]attachment_review_decide_v\d+ \z/msx,
    '2026110201' => qr/\A api[.]attachment_upload_quota_v\d+ \z/msx,
);
const my $ADVISORY_LOCK =>
  qr/pg_advisory (?:_xact)? _lock \s* [(] \s* (\d+)/msx;

my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new;
my %catalogued =
  map { $catalogue->function($_)->{function} => 1 } @{ $catalogue->names };
my %boundaries;
for my $name ( @{ $catalogue->names } ) {
    my $entry = $catalogue->function($name);
    $boundaries{ $name . '_v' . $entry->{version} } = {
        implementation => $name . '_v' . ( $entry->{version} - 1 ),
        arguments      => join( q{, }, map { "p_$_" } @{ $entry->{names} } ),
    };
}
my @tables = _tables();

# Keep exactly these shipped forwarding boundaries for rolling deployments.
# Their arguments stay fixed even as the current catalogue moves forward.
my %previous_arguments = (
    attachment_review_submit   => [qw(attachment_id source_kind source_url)],
    moderation_transfer_picker => [qw(actor source_id query after_position)],
    admin_configuration_state  => [],
    admin_request_context      => [
        qw(known_revision session_id user_id token_hash now touch_interval_seconds resolve_viewer)
    ],
    admin_configuration_change =>
      [qw(actor command expected section key operation value request_hash)],
    community_follow_feed => [
        qw(actor member global_read category_ids space_ids after_at after_id row_limit)
    ],
    ops_event_claim => [qw(operation key event_id now expired_before)],
);
for my $name ( sort keys %previous_arguments ) {
    $boundaries{ $name . '_v2' } = {
        implementation => $name . '_v1',
        arguments      =>
          join( q{, }, map { "p_$_" } @{ $previous_arguments{$name} } ),
    };
}

# Shipped Push predecessors remain callable during rolling upgrades.
$boundaries{portability_export_parts_v32} = {
    implementation => 'portability_export_parts_v31',
    arguments      => 'p_user_id'
};
$boundaries{portability_export_parts_v30} = {
    implementation => 'portability_export_parts_v29',
    arguments      => 'p_user_id'
};
$boundaries{notification_delivery_plan_v4} = {
    implementation => 'notification_delivery_plan_v3',
    arguments      => 'p_user_id, p_notification_type',
};
$boundaries{notification_fanout_candidates_v4} = {
    implementation => 'notification_fanout_candidates_v3',
    arguments      =>
'p_target_type, p_target_id, p_notification_type, p_actor_id, p_excluded_user_id',
};
$boundaries{notification_fanout_deliver_v2} = {
    implementation => 'notification_fanout_deliver_v1',
    arguments      => 'p_recipients',
};

$boundaries{admin_configuration_change_v4} = {
    implementation => 'admin_configuration_change_v3',
    arguments      => $boundaries{admin_configuration_change_v2}{arguments},
};

# The functions a later migration drops: a boundary among them was its
# release's (ADR 0126, section 2), which the catalogue no longer names and
# nothing calls any more.
my %dropped = map { ( _dropped( path($_)->slurp ) ) }
  @{ GPForum::Migration::Plan->new->files };
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

subtest 'the fresh baseline never replaces a function in place' => sub {
    my $replaced = join "\n", 'BEGIN;', q{SET LOCAL lock_timeout = '1s';},
'CREATE OR REPLACE FUNCTION api.core_append_audit_v1(p text) RETURNS jsonb',
      'LANGUAGE sql SET search_path = pg_catalog, pg_temp',
      'SET plan_cache_mode = force_generic_plan AS $$ SELECT NULL::jsonb $$;',
      'REVOKE EXECUTE ON FUNCTION api.core_append_audit_v1(text) FROM PUBLIC;',
      'COMMIT;';
    my ($problems) = _problems( 'baseline.sql', $replaced );
    is_deeply(
        $problems,
        ['baseline.sql: api.core_append_audit_v1: CREATE OR REPLACE'],
        'even the audit chain has one final definition'
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

subtest 'an advisory lock class taken for another purpose is seen' => sub {
    my $created = {
        'api.notification_digest_record_v9' =>
          'PERFORM pg_advisory_xact_lock(2026103101, 1)',
        'api.community_message_start_v9' =>
          'PERFORM pg_advisory_xact_lock(2026103101, 1)',
        'api.forum_other_v1' => 'PERFORM pg_advisory_lock(1)',
    };
    is_deeply(
        [ _advisory_misuse( $created, { map { $_ => 1 } keys %{$created} } ) ],
        [
            'api.community_message_start_v9 takes class 2026103101',
            'api.forum_other_v1 takes class 1',
        ],
        'a class another purpose holds, and one no purpose does'
    );
};

subtest 'an implementation that calls a boundary is seen' => sub {
    my $created = {
        'api.forum_page_v4' => 'SELECT * FROM api.forum_page_v3()',
        'api.forum_page_v3' => 'SELECT * FROM api.forum_page_v2()',
        'api.forum_page_v2' => 'SELECT * FROM api.forum_page_v1()',
        'api.forum_page_v1' => 'SELECT 1',
    };
    my $definer = { 'api.forum_page_v4' => 1, 'api.forum_page_v2' => 1 };
    is_deeply(
        [ _definer_calls( $created, $definer, { 'api.forum_page_v4' => 1 } ) ],
        ['api.forum_page_v3 calls api.forum_page_v2'],
        'the previous release\'s boundary, under the current implementation'
    );
    is_deeply(
        [ _definer_calls( $created, $definer, { 'api.forum_page_v2' => 1 } ) ],
        [],
        'and nothing from the boundary it forwards to'
    );
};

my ( @problems, %created, %definer, %schema_hooks );
for my $file ( @{ GPForum::Migration::Plan->new->files } ) {
    my ( $found, $created, $definer ) = _problems( $file, path($file)->slurp );
    push @problems, @{$found};
    my $migration = path($file)->slurp;
    while ( $migration =~ /$SCHEMA_TRIGGER/gimsx ) {
        $schema_hooks{$1} = 1;
    }
    %created = ( %created, %{$created} );
    %definer = ( %definer, %{$definer} );
}
delete @created{ keys %dropped };
delete @definer{ keys %dropped };
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
@entry_points{ keys %schema_hooks } = (1) x keys %schema_hooks;
is_deeply( [ _unreached( \%created, \%entry_points ) ],
    [], 'and every api function is one the catalogue reaches' );
is_deeply( [ _definer_calls( \%created, \%definer, \%catalogued ) ],
    [], 'and what the release reaches calls no boundary but its own' );
is_deeply( [ _advisory_misuse( \%created, \%catalogued ) ],
    [], 'and each advisory lock class is taken for its one purpose' );

done_testing();

# A migration's problems, the functions it creates with their bodies, and
# those of them that acquire owner rights.
sub _problems ( $file, $sql ) {
    my $code = join "\n", grep { !/\A \s* --/msx } split /\n/msx, $sql;
    my ( @found, %made, %elevated );
    if ( $code =~ $CREATE ) {
        if ( $sql =~ /\A -- [ ] gpforum:no-transaction \b/msx ) {
            push @found, "$file: a function in a no-transaction migration";
        }
        if ( $code !~ /SET \s+ LOCAL \s+ lock_timeout/imsx ) {
            push @found, "$file: no lock_timeout";
        }
    }
    while ( $code =~ /$FUNCTION/gmsx ) {
        my %function = %LAST_PAREN_MATCH;
        push @found,
          _function_problems( "$file: api.$function{name}", \%function, $code );
        $made{"api.$function{name}"} = $function{body};
        if ( $function{head} =~ /SECURITY \s+ DEFINER/imsx ) {
            $elevated{"api.$function{name}"} = 1;
        }
    }
    while ( $code =~ /$DROP/gmsx ) {
        my $dropped = $LAST_PAREN_MATCH{dropped};
        if ( $catalogued{$dropped} ) {
            push @found, "$file: drops $dropped, which the catalogue calls";
        }
    }

    return ( \@found, \%made, \%elevated );
}

# The functions a migration drops, each mapped to 1.
sub _dropped ($sql) {
    my $code = join "\n", grep { !/\A \s* --/msx } split /\n/msx, $sql;
    my @dropped;
    while ( $code =~ /$DROP/gmsx ) {
        push @dropped, $LAST_PAREN_MATCH{dropped} => 1;
    }

    return @dropped;
}

sub _function_problems ( $label, $function, $code ) {
    my ( $name, $head, $body ) = @{$function}{qw(name head body)};
    my $revoked = qr/$REVOKE \Q$name\E $FROM_PUBLIC/imsx;
    my %rule    = (
        'CREATE OR REPLACE'                   => defined $function->{replace},
        'EXECUTE revoked from PUBLIC nowhere' => $code !~ $revoked,
        'SECURITY DEFINER' => ( $head =~ /SECURITY \s+ DEFINER/imsx )
          && !_boundary( $name, $head, $body )
          && !$dropped{"api.$name"} ? 1 : 0,
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

# The functions the bodies lead to from the entry points: what the catalogue
# calls, then whatever their bodies call, and so on.
sub _reached ( $created, $entry_points ) {
    my %reached;
    my @next = grep { exists $created->{$_} } sort keys %{$entry_points};
    while ( my $function = shift @next ) {
        next if $reached{$function}++;
        push @next, grep { exists $created->{$_} && !$reached{$_} }
          map { "api.$_" } $created->{$function} =~ /$CALLED/gmsx;
    }

    return \%reached;
}

# The functions no body leads to from the entry points.
sub _unreached ( $created, $entry_points ) {
    my $reached   = _reached( $created, $entry_points );
    my @unreached = sort grep { !$reached->{$_} } keys %{$created};

    return @unreached;
}

# The advisory lock classes the functions the entry points reach take for
# something other than what %ADVISORY_CLASSES lists them for.
sub _advisory_misuse ( $created, $entry_points ) {
    my $reached = _reached( $created, $entry_points );
    my @misused;
    for my $function ( sort keys %{$reached} ) {
        for my $class ( $created->{$function} =~ /$ADVISORY_LOCK/gmsx ) {
            next
              if exists $ADVISORY_CLASSES{$class}
              && $function =~ $ADVISORY_CLASSES{$class};
            push @misused, "$function takes class $class";
        }
    }

    return @misused;
}

# The calls of an owner-rights boundary from an implementation the entry
# points reach. A boundary is kept for the previous release's workers only
# until a contract migration drops it (ADR 0126, section 2); an
# implementation that called one would break then.
sub _definer_calls ( $created, $definer, $entry_points ) {
    my $reached = _reached( $created, $entry_points );
    my @calls;
    for my $function ( sort grep { !$definer->{$_} } keys %{$reached} ) {
        my %seen;
        push @calls, map { "$function calls $_" }
          grep { $definer->{$_} && !$seen{$_}++ }
          map { "api.$_" } $created->{$function} =~ /$CALLED/gmsx;
    }

    return @calls;
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
