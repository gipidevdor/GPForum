# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Test::More;
use Test::Mojo;
use Const::Fast;
use JSON::MaybeXS qw(decode_json);
use lib 'lib';
use lib 't/lib';
use GPForum::Infrastructure::Id;
use GPForum::Service::Admin::PermissionGate;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';
const my $HTTP_OK => 200;
if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'requires PostgreSQL';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $dbh = $database->dbh;
my $ids = GPForum::Infrastructure::Id->new;
my ( $member, $moderator, $role, $permission, $binding, $category ) =
  map { $ids->uuid } qw(member moderator role permission binding category);

for my $account ( [ $member, 'nav_reader' ], [ $moderator, 'nav_moderator' ] ) {
    $dbh->do(
q{INSERT INTO users(id,username,display_name,email_normalized,password_hash,status,email_verified_at) VALUES (?,?,?,?,'x','active',now())},
        undef,
        $account->[0],
        $account->[1],
        $account->[1],
        "$account->[1]\@example.test"
    );
}
$dbh->do(
q{INSERT INTO roles(role_id,name,description) VALUES (?,'nav_media_role','Media moderation')},
    undef, $role
);
my ($known) = $dbh->selectrow_array(
q{SELECT permission_id FROM permissions WHERE resource_type='thread' AND action='moderate'}
);
if ($known) { $permission = $known; }
else {
    $dbh->do(
q{INSERT INTO permissions(permission_id,name,resource_type,action) VALUES (?,'nav_thread_moderate','thread','moderate')},
        undef, $permission
    );
}
$dbh->do( q{INSERT INTO role_permissions(role_id,permission_id) VALUES (?,?)},
    undef, $role, $permission );
$dbh->do(
q{INSERT INTO role_bindings(binding_id,user_id,role_id,resource_type) VALUES (?,?,?,'global')},
    undef, $binding, $moderator, $role
);
my $gate =
  GPForum::Service::Admin::PermissionGate->new( schema => $database->schema );
is_deeply( $gate->navigation_context($member)->{permissions},
    {}, 'ordinary member has no staff links' );
ok( $gate->navigation_context($moderator)->{permissions}{'thread.moderate'},
    'global media grant reaches navigation' );
is( $gate->navigation_context($moderator)->{username},
    'nav_moderator', 'profile identifier is read with permissions' );

my $t      = Test::Mojo->new('GPForum');
my $routes = $t->app->routes;
$routes->get('/__test/nav/:id')->to(
    cb => sub ($c) {
        $c->session( user_id => $c->param('id') );
        return $c->render( text => 'ready' );
    }
);
$t->get_ok('/menu')->status_is($HTTP_OK);
$t->element_exists_not('a[href="/moderation/media"]');
$t->get_ok("/__test/nav/$moderator")->status_is($HTTP_OK);
$t->get_ok('/menu')->status_is($HTTP_OK);
$t->element_exists('a[href="/moderation/media"]');
$t->element_exists('a[href="/u/nav_moderator"]');
$t->element_exists_not('a[href="/admin/plugins"]');
$t->header_is( 'Cache-Control' => 'private, no-store' );
$dbh->do(
q{UPDATE role_bindings SET resource_type='category', resource_id=? WHERE binding_id=?},
    undef, $category, $binding
);
is_deeply( $gate->navigation_context($moderator)->{permissions},
    {}, 'category-scoped binding cannot expose global consoles' );
$t->get_ok('/menu')->status_is($HTTP_OK);
$t->element_exists_not('a[href="/moderation/media"]');
$dbh->do(
q{UPDATE role_bindings SET resource_type='global',resource_id=NULL,revoked_at=now() WHERE binding_id=?},
    undef, $binding
);
is_deeply( $gate->navigation_context($moderator)->{permissions},
    {}, 'revocation takes effect on the next read' );
$t->get_ok('/menu')->status_is($HTTP_OK);
$t->element_exists_not('a[href="/moderation/media"]');
$dbh->do( q{UPDATE role_bindings SET revoked_at=NULL WHERE binding_id=?},
    undef, $binding );
my $suspension = $ids->uuid;
$dbh->do(
q{INSERT INTO suspensions(suspension_id,user_id,actor_user_id,reason) VALUES (?,?,?,'navigation test')},
    undef, $suspension, $moderator, $member
);
is_deeply( $gate->navigation_context($moderator)->{permissions},
    {}, 'suspended moderator has no staff menu' );
$dbh->do( q{UPDATE suspensions SET revoked_at=now() WHERE suspension_id=?},
    undef, $suspension );
ok( $gate->navigation_context($moderator)->{permissions}{'thread.moderate'},
    'released suspension restores eligible tools' );
$t->get_ok("/__test/nav/$member")->status_is($HTTP_OK);
$t->get_ok('/menu')->status_is($HTTP_OK);
$t->element_exists_not('a[href="/moderation/media"]');
$t->element_exists('a[href="/u/nav_reader"]');
$dbh->do( q{UPDATE users SET status='deleted',deleted_at=now() WHERE id=?},
    undef, $moderator );
is_deeply( $gate->navigation_context($moderator)->{permissions},
    {}, 'deleted account has no staff context' );
done_testing();
1;
