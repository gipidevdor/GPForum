# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use Const::Fast;
const my $HTTP_FORBIDDEN => 403;
const my $HTTP_FOUND     => 302;
const my $HTTP_ACCEPTED  => 202;
const my $FIXTURE_USERS  => 5;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Command::AdminBootstrap;
use GPForum::Test::GuiDriver;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;
our $VERSION = '0.001';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'requires PostgreSQL';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $dbh    = $database->dbh;
my $admin  = seed_id( user => 1 );
my $member = seed_id( user => 2 );
GPForum::Test::PostgresHarness::quietly(
    sub {
        return GPForum::Command::AdminBootstrap->new(
            schema => $database->schema )->run( 'grant', '--user-id', $admin );
    }
);
my $t   = Test::Mojo->new('GPForum');
my $gui = GPForum::Test::GuiDriver->new( test => $t );
$gui->install_session;
$gui->actor($admin);
subtest
  'feature: roles create, attach, bind and revoke through actual forms' => sub {
    $gui->visit('/admin/roles')->submit( 'form[action="/admin/roles"]',
        { name => 'gui-feature-role', description => 'Native role management' }
    );
    my ($role) = $dbh->selectrow_array(
        q{SELECT role_id FROM roles WHERE name='gui-feature-role'});
    ok( $role, 'GUI role creation persists the role' );
    $gui->visit('/admin/roles')->submit(
        'form[action="/admin/permissions"]',
        {
            name          => 'gui.feature',
            resource_type => 'gui_feature',
            action        => 'read'
        }
    );
    my ($permission) = $dbh->selectrow_array(
q{SELECT permission_id FROM permissions WHERE resource_type='gui_feature' AND action='read'}
    );
    ok( $permission, 'GUI permission creation persists the permission' );
    $gui->visit('/admin/roles')
      ->submit( 'form[action="/admin/roles/' . $role . '/permissions"]',
        { permission_id => $permission } );
    is(
        $dbh->selectrow_array(
q{SELECT count(*) FROM role_permissions WHERE role_id=? AND permission_id=?},
            undef,
            $role,
            $permission
        ),
        1,
        'GUI attachment persists the role permission'
    );
    $gui->visit( '/admin/users/' . $member . '/roles' )->submit(
        'form[action="/admin/users/' . $member . '/roles"]',
        { role_id => $role, resource_type => 'global' }
    );
    my ($binding) = $dbh->selectrow_array(
q{SELECT binding_id FROM role_bindings WHERE user_id=? AND role_id=? AND revoked_at IS NULL},
        undef, $member, $role
    );
    ok( $binding,
        'GUI binding grants the selected role to the selected member' );
    $gui->visit( '/admin/users/' . $member . '/roles' )
      ->submit( 'form[action="/admin/role-bindings/' . $binding . '/revoke"]',
        { confirm => '1' } );
    ok(
        $dbh->selectrow_array(
q{SELECT revoked_at IS NOT NULL FROM role_bindings WHERE binding_id=?},
            undef,
            $binding
        ),
        'GUI revocation removes the live grant'
    );
    $gui->actor($member)
      ->visit( '/admin/roles', $HTTP_FORBIDDEN )
      ->actor($admin);
  };
subtest 'feature: announcements publish and retire through actual forms' =>
  sub {
    $gui->visit('/admin/announcements')
      ->submit( 'form[action="/admin/announcements"]',
        { message => 'GUI announcement feature', tone => 'warning' } );
    my ($id) = $dbh->selectrow_array(
q{SELECT announcement_id FROM site_announcements WHERE message='GUI announcement feature'}
    );
    ok( $id, 'GUI announcement publication persists its message' );
    $gui->visit(q{/});
    $t->content_like(qr/GUI[ ]announcement[ ]feature/msx);
    $gui->visit('/admin/announcements')
      ->submit( 'form[action="/admin/announcements/' . $id . '/retire"]' );
    ok(
        $dbh->selectrow_array(
q{SELECT retired_at IS NOT NULL FROM site_announcements WHERE announcement_id=?},
            undef,
            $id
        ),
        'GUI retirement persists its timestamp'
    );
    $gui->visit(q{/});
    $t->element_exists_not('.site-announcements');
  };
subtest 'feature: category settings persist through the category form' => sub {
    my $category = seed_id( category => 1 );
    $gui->visit('/admin/categories')
      ->submit( 'form[action="/admin/categories/' . $category . '"]',
        { title => 'GUI revised category' } );
    is(
        $dbh->selectrow_array(
            q{SELECT title FROM categories WHERE category_id=?}, undef,
            $category
        ),
        'GUI revised category',
        'GUI category edit persists its title'
    );
};
subtest
  'feature: a configuration default can be restored from its own control' =>
  sub {
    $gui->visit('/admin/configuration')
      ->submit( 'form[action="/admin/configuration"]',
        { GPFORUM_SITE_NAME => 'GUI configuration name' } );
    $gui->visit('/admin/configuration');
    $t->element_exists(
        'input[name="GPFORUM_SITE_NAME"][value="GUI configuration name"]');
    $gui->submit('form[action="/admin/configuration/GPFORUM_SITE_NAME/reset"]');
    $gui->visit('/admin/configuration');
    $t->element_exists_not(
        'input[name="GPFORUM_SITE_NAME"][value="GUI configuration name"]');
  };
subtest 'feature: search maintenance is requested from the jobs form' => sub {
    my ($before) = $dbh->selectrow_array(
q{SELECT count(*) FROM outbox_messages o JOIN event_log e USING(event_id) WHERE e.event_type='search.rebuild_requested'}
    );
    $gui->visit('/admin/jobs')->submit('form[action="/admin/search/rebuild"]');
    my ($after) = $dbh->selectrow_array(
q{SELECT count(*) FROM outbox_messages o JOIN event_log e USING(event_id) WHERE e.event_type='search.rebuild_requested'}
    );
    cmp_ok( $after, '>', $before,
        'GUI search maintenance queues its durable job' );
};
done_testing();
1;
