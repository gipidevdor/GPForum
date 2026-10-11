# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use English    qw(-no_match_vars);
use Mojo::File qw(path);
use Test::More;

use lib 'lib';

use GPForum::Infrastructure::SqlFunctionCatalogue;

our $VERSION = '0.001';

# ADR 0126, sections 2, 4, 7 and 11, held for every function in schema api
# from migration 052 on: a version suffix and an area, CREATE FUNCTION and
# never CREATE OR REPLACE (a shipped version never changes under the
# previous release's workers), a pinned search_path and plan mode, the
# invoker's rights, EXECUTE revoked from PUBLIC, no dynamic SQL, the tables
# of public written with their schema, and a transactional migration that
# sets lock_timeout. A function the catalogue calls is created by a
# migration and never dropped.
const my $FIRST_API_MIGRATION => '052';
const my @AREAS => qw(
  admin attachment community core forum identity moderation notification ops
  outbox partition portability privacy projection search session worker plugin
);
const my $AREA   => join q{|}, @AREAS;
const my $WORD   => qr/[[:lower:]] [[:lower:][:digit:]_]*/msx;
const my $SUFFIX => qr/_v [1-9] [[:digit:]]*/msx;
const my $NAME   => qr/\A (?:$AREA) _ $WORD $SUFFIX \z/msx;
const my $CREATE => qr/CREATE \s+ (?<replace>OR \s+ REPLACE \s+)? FUNCTION/imsx;
const my $OPENING  => qr/$CREATE \s+ api [.] (?<name>\w+) \s* [(]/imsx;
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

my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new;
my %catalogued =
  map { $catalogue->function($_)->{function} => 1 } @{ $catalogue->names };
my @tables = _tables();

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

my ( @problems, %created );
for my $file ( sort glob 'migrations/[0-9]*_*.sql' ) {
    my ($version) = path($file)->basename =~ /\A (\d+) _/msx;
    next if $version lt $FIRST_API_MIGRATION;

    my ( $found, $created ) = _problems( $file, path($file)->slurp );
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
sub _problems ( $file, $sql ) {
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
          _function_problems( "$file: api.$function{name}", \%function, $code );
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

sub _function_problems ( $label, $function, $code ) {
    my ( $name, $head, $body ) = @{$function}{qw(name head body)};
    my $revoked = qr/$REVOKE \Q$name\E $FROM_PUBLIC/imsx;
    my %rule    = (
        'CREATE OR REPLACE'                   => defined $function->{replace},
        'EXECUTE revoked from PUBLIC nowhere' => $code !~ $revoked,
        'SECURITY DEFINER' => ( $head =~ /SECURITY \s+ DEFINER/imsx )
          && !_boundary( $name, $head, $body ) ? 1 : 0,
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
    return 0 if $name =~ /\A core_/msx || $name !~ /_v2\z/msx;
    return 0 if !$catalogued{"api.$name"};
    return 0 if $head !~ /LANGUAGE\s+sql\b/imsx;
    my $implementation = $name =~ s/_v2\z/_v1/rmsx;
    my $argument       = qr/p_\w+\s*/msx;
    my $arguments      = qr/(?:$argument(?:,\s*$argument)*)?/msx;
    my $opening =
      qr/\A\s*SELECT\s+[*]\s+FROM\s+api[.]\Q$implementation\E\s*[(]\s*/imsx;
    my $closing = qr/[)]\s*;?\s*\z/msx;
    return $body =~ /$opening$arguments$closing/imsx
      ? 1
      : 0;
}

# The tables the migrations create, which a function names as public.NAME.
sub _tables {
    my %table;
    for my $file ( glob 'migrations/[0-9]*_*.sql' ) {
        my $sql = path($file)->slurp;
        while ( $sql =~
            /CREATE \s+ TABLE \s+ (?:IF \s+ NOT \s+ EXISTS \s+)? (\w+)/gimsx )
        {
            $table{ lc $1 } = 1;
        }
    }
    my @sorted = sort keys %table;

    return @sorted;
}

1;
