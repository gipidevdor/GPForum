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
  forum_resolve_viewer_v6 outbox_claim_ready_v2 forum_thread_page_reads_v4
  ops_retention_purge_v2 notification_subscribers_v2
  notification_unread_count_v6 notification_list_inbox_v6
  forum_find_listed_post_v2 forum_poll_change_v2
  portability_export_parts_v22 privacy_revoke_user_v22 privacy_revoke_user_v24
  identity_register_command_v2 identity_update_user_v4
  moderation_active_suspension_v2 moderation_can_participate_v2
);

# The typed write boundaries kept for workers from the previous release,
# also retained by the static ADR 0127 contract in t/641.
const my @RETAINED_WRITES =>
  qw(forum_create_reply_v4 forum_store_write_v2 forum_write_command_v4);

# The shipped argument lists of the retained entry points, by name.
const my $READER_ARGUMENTS => join q{, },
  'p_recipient_user_id uuid',
  'p_filter_sources boolean', 'p_member boolean',      'p_global_read boolean',
  'p_viewer_user_id uuid',    'p_category_ids uuid[]', 'p_space_ids uuid[]';
const my %RETAINED_ARGUMENTS => (
    forum_resolve_viewer_v6 => 'p_user_id uuid',
    outbox_claim_ready_v2   =>
      'p_now text, p_locked_until text, p_worker_id text, p_row_limit integer',
    ops_retention_purge_v2 =>
      'p_source text, p_cutoff timestamp with time zone, p_row_limit integer',
    notification_subscribers_v2 =>
      'p_target_type text, p_target_id uuid, p_notification_type text',
    notification_unread_count_v6 => $READER_ARGUMENTS,
    notification_list_inbox_v6   => join( q{, },
        $READER_ARGUMENTS,
        'p_after_created_at timestamp with time zone',
        'p_after_notification_id uuid',
        'p_row_limit integer' ),
    privacy_revoke_user_v22   => 'p_source text, p_user_id uuid, p_at text',
    privacy_revoke_user_v24   => 'p_source text, p_user_id uuid, p_at text',
    forum_find_listed_post_v2 => join( q{, },
        'p_post_id uuid',
        'p_thread_id uuid',
        'p_member boolean',
        'p_global_read boolean',
        'p_scope_user_id uuid',
        'p_viewer_user_id uuid' ),
    forum_poll_change_v2 => join( q{, },
        'p_actor uuid',
        'p_command uuid',
        'p_thread_id uuid',
        'p_operation text',
        'p_values jsonb' ),
    forum_thread_page_reads_v4 => join( q{, },
        'p_thread_id uuid',
        'p_post_ids uuid[]',
        'p_viewer_user_id uuid',
        'p_engagement_target_type text',
        'p_link_target_type text',
        'p_link_post_ids uuid[]',
        'p_link_row_limit integer' ),
    portability_export_parts_v22 => 'p_user_id uuid',
    identity_update_user_v4      => 'p_user_id uuid, p_changes jsonb',
    identity_register_command_v2 => join( q{, },
        map { 'p_' . $_ . q{ } . ( /outbox_id\z/msx ? 'text' : 'jsonb' ) }
          qw(log answer accepted refused user credential event event_outbox_id audit token token_audit mail_event mail_outbox_id mail_outbox_extras)
    ),
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
for my $retained (@RETAINED_WRITES) {
    ok( $function{$retained},
        "api.$retained remains an owner-rights boundary for older workers" );
}

for my $retained (@RETAINED) {
    ok( $function{$retained},
        "api.$retained remains callable by older workers" );
    is(
        $function{$retained}{arguments},
        _retained_arguments($retained),
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
    @called{ @RETAINED, @RETAINED_WRITES } =
      (1) x ( @RETAINED + @RETAINED_WRITES );
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

sub _retained_arguments ($name) {
    return $RETAINED_ARGUMENTS{$name} if exists $RETAINED_ARGUMENTS{$name};

    return 'p_user_id uuid, p_now text';
}

1;
