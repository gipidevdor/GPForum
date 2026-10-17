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

# ADR 0126, sections 2, 4, 7 and 11, held for every function in schema api
# from migration 052 on: a version suffix and an area, CREATE FUNCTION and
# never CREATE OR REPLACE (a shipped version never changes under the
# previous release's workers), a pinned search_path and plan mode, the
# invoker implementations and narrow definer boundaries, EXECUTE revoked
# from PUBLIC, no dynamic SQL, the tables
# of public written with their schema, and a transactional migration that
# sets lock_timeout. A function the catalogue calls is created by a
# migration and never dropped.
const my $FIRST_API_MIGRATION  => '052';
const my $DRAFT_ARGUMENT_COUNT => 2;
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
const my @RETAINED_SEARCH_VERSIONS  => ( 2, 4, 6 );
const my @RETAINED_SUGGEST_VERSIONS => ( 2, 4 );
const my $CURRENT_SEARCH_VERSION    => 8;
const my %RETAINED_BOUNDARIES => (
    search_ranked            => [@RETAINED_SEARCH_VERSIONS],
    search_autocomplete      => [@RETAINED_SUGGEST_VERSIONS],
    forum_list_categories    => [2],
    community_list_bookmarks => [2],
    forum_resolve_viewer     => [ 2, 4 ],
    moderation_target        => [2],
    moderation_target_update => [2],
    forum_write_command      => [2],
    forum_create_reply       => [2],
    identity_update_user     => [2],
    portability_export_parts => [ 2, 4, 6, 8, 10, 12, 14 ],
    privacy_revoke_user      => [ 2, 4, 6, 8, 10, 12 ],
    privacy_update           => [2],

    # Migration 112 (member relations) moved these on.
    notification_list_inbox   => [ 2, 4 ],
    notification_unread_count => [ 2, 4 ],
    community_list_mentions   => [2],

    # Migration 116 (first-post review) moved this on.
    moderation_automod_rules => [2],

    # Migration 122 (digest windows) moved these on.
    notification_digest_due    => [2],
    notification_digest_items  => [2],
    notification_digest_record => [2],
    notification_digest_plan   => [2],

    # Migration 126 (the feed leaves out listed members) moved this on.
    community_list_feed => [2],

    # Migration 127 (held posts read as their author) moved this on.
    moderation_review_mine => [2],

    # Migration 128 (direct messages) moved these on.
    notification_type_preferences     => [2],
    notification_set_type_preferences => [2],
    notification_delivery_plan        => [2],
    notification_unsubscribe          => [2],
    moderation_automod_record         => [2],
);

# What each boundary's version 2 forwarded, from today's arguments: the
# draft's arguments came at v3 of the write commands; the bookmark list
# gained its folder (migration 121); the digest's due list its key and its
# plan the time (migration 122); the author's held posts the reader's
# scopes (migration 127).
my %VERSION_2_ARGUMENTS = (
    forum_write_command => sub (@names) {
        return @names[ 0 .. $#names - $DRAFT_ARGUMENT_COUNT ];
    },
    forum_create_reply => sub (@names) {
        return @names[ 0 .. $#names - $DRAFT_ARGUMENT_COUNT ];
    },
    community_list_bookmarks =>
      sub (@names) { return @names[ 0 .. $#names - 1 ]; },
    notification_digest_due => sub (@names) {
        return grep { !/\A after_/msx } @names;
    },
    notification_digest_plan =>
      sub (@names) { return @names[ 0 .. $#names - 1 ]; },
    moderation_review_mine => sub (@names) { return @names[ 0, 1 ]; },
);

my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new;
my %catalogued =
  map { $catalogue->function($_)->{function} => 1 } @{ $catalogue->names };
my %boundaries;
for my $name ( @{ $catalogue->names } ) {
    my $entry = $catalogue->function($name);
    my $retained =
      exists $RETAINED_BOUNDARIES{$name}
      ? $RETAINED_BOUNDARIES{$name}
      : [];
    for my $version ( $entry->{version}, @{$retained} ) {
        my @names = _boundary_arguments( $name, $version, $entry );
        $boundaries{"${name}_v$version"} = {
            implementation => $name . '_v' . ( $version - 1 ),
            arguments      => join( q{, }, map { "p_$_" } @names ),
        };
    }
}
my @tables = _tables();

# A boundary the catalogue called when it shipped and a later migration
# drops (migration 105 drops the unwired subsystems'): the catalogue no
# longer names it, so it is held to forwarding its own typed parameters to
# its previous version instead.
my %dropped_in = _dropped();

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
    is_deeply( $created, ['api.forum_lookup'], 'and the function is seen' );
};

subtest 'only registered typed boundaries gain owner rights' => sub {
    my $head = 'LANGUAGE sql SECURITY DEFINER';
    for my $version ( @RETAINED_SEARCH_VERSIONS, $CURRENT_SEARCH_VERSION ) {
        my $boundary = $boundaries{"search_ranked_v$version"};
        my $call =
            'SELECT * FROM api.'
          . $boundary->{implementation} . '('
          . $boundary->{arguments} . ');';
        ok(
            _boundary( "search_ranked_v$version", $head, $call ),
            "registered v$version forwards all typed arguments"
        );
        ok( !_boundary( "search_ranked_v$version", $head, "$call SELECT 1;" ),
            'extra SQL is refused' );
        my $other = $call =~ s/search_ranked/search_autocomplete/rmsx;
        ok( !_boundary( "search_ranked_v$version", $head, $other ),
            'a different implementation is refused' );
        my $missing = $call =~ s/p_permission_mode,\s*//rmsx;
        ok( !_boundary( "search_ranked_v$version", $head, $missing ),
            'dropping a typed argument is refused' );
    }
    my $arguments =
      $boundaries{"search_ranked_v$CURRENT_SEARCH_VERSION"}{arguments};
    ok(
        !_boundary(
            'search_ranked_v10', $head,
            "SELECT * FROM api.search_ranked_v9($arguments);"
        ),
        'an unregistered future version is refused'
    );
    ok(
        !_boundary(
            'core_helper_v2', $head, 'SELECT * FROM api.core_helper_v1();'
        ),
        'helpers cannot gain owner rights'
    );
    my $retired_head = "p_a text, p_b jsonb\n) RETURNS int LANGUAGE sql";
    ok(
        _retired_boundary(
            'plugin_find_v2', $retired_head,
            'SELECT * FROM api.plugin_find_v1(p_a, p_b);'
        ),
        'a dropped boundary that forwarded its own parameters is accepted'
    );
    ok(
        !_retired_boundary(
            'plugin_find_v2', $retired_head,
            'SELECT * FROM api.plugin_find_v1(p_a);'
        ),
        'and one that dropped a parameter is refused'
    );
};

my ( @problems, %created );
for my $file ( @{ GPForum::Migration::Plan->new->files } ) {
    my ($version) = path($file)->basename =~ /\A (\d+) _/msx;
    next if $version lt $FIRST_API_MIGRATION;

    my ( $found, $created ) = _problems( $file, path($file)->slurp, $version );
    push @problems, @{$found};
    @created{ @{$created} } = ($file) x @{$created};
}
is_deeply( \@problems, [], 'every api function follows ADR 0126' );
ok(
    $created{'api.core_canonical_json_v1'},
    'the functions of the migrations are seen'
);
for my $function ( sort keys %catalogued ) {
    ok( $created{$function}, "$function, which the catalogue calls, exists" );
}

done_testing();

# A migration's problems, and the functions it creates.
sub _problems ( $file, $sql, $version = undef ) {
    my $code = join "\n", grep { !/\A \s* --/msx } split /\n/msx, $sql;
    my ( @found, @created );
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
          _function_problems( "$file: api.$function{name}",
            \%function, $code, $version );
        push @created, "api.$function{name}";
    }
    while ( $code =~ /$DROP/gmsx ) {
        my $dropped = $LAST_PAREN_MATCH{dropped};
        if ( $catalogued{$dropped} ) {
            push @found, "$file: drops $dropped, which the catalogue calls";
        }
    }

    return ( \@found, \@created );
}

sub _function_problems ( $label, $function, $code, $version = undef ) {
    my ( $name, $head, $body ) = @{$function}{qw(name head body)};
    my $dropped_later = defined $version
      && ( $dropped_in{"api.$name"} // q{} ) gt $version;
    my $boundary =
      $dropped_later
      ? _retired_boundary( $name, $head, $body )
      : _boundary( $name, $head, $body );
    my $revoked = qr/$REVOKE \Q$name\E $FROM_PUBLIC/imsx;
    my %rule    = (
        'CREATE OR REPLACE'                   => defined $function->{replace},
        'EXECUTE revoked from PUBLIC nowhere' => $code !~ $revoked,
        'SECURITY DEFINER' => ( $head =~ /SECURITY \s+ DEFINER/imsx )
          && !$boundary ? 1 : 0,
        'dynamic SQL' => ( $body =~ /\b EXECUTE \b/imsx ) ? 1 : 0,
        'no version suffix or area'  => $name !~ $NAME,
        'plan_cache_mode not pinned' => $head !~ $PLAN_MODE,
        'search_path not pinned'     => $head !~ $SEARCH_PATH,
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

# A dropped boundary: LANGUAGE sql, forwarding exactly its own parameters,
# in order, to the previous version of itself.
sub _retired_boundary ( $name, $head, $body ) {
    my ( $base, $version ) = $name =~ /\A (\w+) _v ([[:digit:]]+) \z/msx;
    return 0 if !$base || $base =~ /\A core_/msx || $version < 2;
    return 0 if $head           !~ /LANGUAGE\s+sql\b/imsx;
    my ($parameters) = $head =~ /\A ([^)]*) [)]/msx;
    my $arguments    = join q{\s*,\s*},
      ( $parameters // q{} ) =~ /\b (p_\w+) \b/gmsx;
    my $implementation = $base . '_v' . ( $version - 1 );
    my $opening =
      qr/\A\s*SELECT\s+[*]\s+FROM\s+api[.]\Q$implementation\E\s*[(]\s*/imsx;

    return $body =~ /$opening$arguments\s*[)]\s*;?\s*\z/imsx ? 1 : 0;
}

# The functions a migration drops, by the version of the migration.
sub _dropped {
    my %dropped;
    for my $file ( @{ GPForum::Migration::Plan->new->files } ) {
        my ($version) = path($file)->basename =~ /\A (\d+) _/msx;
        my $code      = join "\n", grep { !/\A \s* --/msx } split /\n/msx,
          path($file)->slurp;
        while ( $code =~ /$DROP/gmsx ) {
            $dropped{ $LAST_PAREN_MATCH{dropped} } = $version;
        }
    }

    return %dropped;
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

# The typed arguments a boundary of this version forwards: today's, less
# what its implementation did not take yet.
sub _boundary_arguments ( $name, $version, $entry ) {
    my @names = @{ $entry->{names} };
    if ( $version == 2 && exists $VERSION_2_ARGUMENTS{$name} ) {
        return $VERSION_2_ARGUMENTS{$name}->(@names);
    }

    # The ranked search gained its scope at v7; the retained boundaries
    # forward the arguments of their day.
    if ( $name eq 'search_ranked' && $version < $CURRENT_SEARCH_VERSION ) {
        pop @names;
    }

    return @names;
}

1;
