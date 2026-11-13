# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use lib 'lib';
use lib 't/lib';

use Mojo::Transaction::HTTP;
use Mojo::URL;
use Mojolicious;
use Test::More;

use GPForum::Controller::Admin::Base;
use GPForum::Controller::Moderation::Base;
use GPForum::Controller::Privacy::Base;
use GPForum::Service::Admin::PermissionGate;
use GPForum::Test::AnsweringFunctions;
use GPForum::Test::RecordingPermissionGate;

use GPForum::Test::Promise qw(await_result);

our $VERSION = '0.001';

my @live_transactions;

my $moderate = {
    resource_type => 'thread',
    action        => 'moderate',
};

# Which binding satisfies which scope is api.admin_permission_allowed's to
# decide, and t/integration/postgres-admin-authorization.t checks it on
# PostgreSQL: global, category, space and pair bindings, revoked ones, a
# partial match. Here the gate is held to what it asks and what it makes of
# the answer, on a call layer that answers as stated.
my $granting = _functions(1);
my $gate     = _gate($granting);
ok( $gate->allowed( { user_id => 'moderator-1' }, $moderate ),
    'a granted permission is allowed' );
is_deeply(
    $granting->asked('admin_permission_allowed')->[0],
    {
        action        => 'moderate',
        resource_id   => undef,
        resource_type => 'thread',
        space_id      => undef,
        user_id       => 'moderator-1',
    },
    'an unscoped check asks for a global binding only'
);

$gate->allowed( 'moderator-1',
    { %{$moderate}, resource_id => 'category-1', space_id => 'space-1' } );
is_deeply(
    $granting->asked('admin_permission_allowed')->[1],
    {
        action        => 'moderate',
        resource_id   => 'category-1',
        resource_type => 'thread',
        space_id      => 'space-1',
        user_id       => 'moderator-1',
    },
    'a scoped check sends its resource and space, for a user id given bare'
);

$gate->allowed( { user_id => 'moderator-1' },
    { %{$moderate}, resource_id => q{}, space_id => q{} } );
is_deeply(
    [
        @{ $granting->asked('admin_permission_allowed')->[2] }
          {qw(resource_id space_id)}
    ],
    [ undef, undef ],
    'empty resource scope is treated as unscoped and stays fail-closed'
);

ok(
    !_gate( _functions(0) )->allowed( { user_id => 'moderator-1' }, $moderate ),
    'a refused permission is not allowed'
);
ok(
    !_gate( GPForum::Test::AnsweringFunctions->new )
      ->allowed( { user_id => 'moderator-1' }, $moderate ),
    'nor is one the function answers no row for'
);

my $anonymous = _functions(1);
ok( !_gate($anonymous)->allowed( {}, $moderate ),
    'anonymous actors are denied' );
ok( !_gate($anonymous)->allowed( undef, $moderate ), 'as are missing ones' );
is( scalar @{ $anonymous->calls }, 0, 'before any statement' );

my $application = Mojolicious->new;
$application->log->level('fatal');
$application->secrets( ['permission-scope-test-secret'] );
my $gate_recorder = GPForum::Test::RecordingPermissionGate->new;
$application->helper( gp_permission_gate => sub { return $gate_recorder; } );

my $moderation = _controller(
    $application,
    'GPForum::Controller::Moderation::Base',
    '/moderation/threads/thread-1/lock'
);
$moderation->stash( thread_id => 'thread-1' );
is_deeply(
    $moderation->write_permission_scope('thread'),
    { resource_id => 'thread-1', space_id => undef },
    'moderation write scope uses the thread route placeholder'
);
is_deeply(
    $moderation->write_permission_scope('post'),
    { resource_id => undef, space_id => undef },
    'moderation write scope stays global without a matching placeholder'
);
is_deeply(
    $moderation->write_permission_scope('suspension'),
    { resource_id => undef, space_id => undef },
    'moderation suspension revoke has no placeholder scope'
);
is_deeply(
    $moderation->global_permission_scope,
    { resource_id => undef, space_id => undef },
    'moderation global scope names both columns explicitly'
);

my $injected = _controller(
    $application,
    'GPForum::Controller::Moderation::Base',
    '/moderation/reports/report-1/assign?thread_id=thread-9'
);
is_deeply(
    $injected->write_permission_scope('thread'),
    { resource_id => undef, space_id => undef },
    'query parameters cannot widen a moderation write scope'
);

$moderation->session( user_id => 'moderator-1' );
is( await_result( $moderation->authorized_user_id('view_queue') ),
    'moderator-1', 'moderation reads authorize the session actor' );
is_deeply(
    $gate_recorder->last_permission,
    {
        action        => 'view_queue',
        resource_type => 'report',
        resource_id   => undef,
        space_id      => undef,
    },
    'moderation reads ask the gate for a global binding'
);

my $admin = _controller(
    $application,
    'GPForum::Controller::Admin::Base',
    '/admin/users/user-1/roles?resource_id=category-1&space_id=space-1'
);
$admin->stash( action => 'bind_role' );
is_deeply(
    $admin->write_permission_scope,
    { resource_id => 'category-1', space_id => 'space-1' },
    'admin binding writes scope to the requested resource and space'
);
$admin->stash( action => 'create_role' );
is_deeply(
    $admin->write_permission_scope,
    { resource_id => undef, space_id => undef },
    'other admin writes ignore resource_id and space_id parameters'
);

$admin->session( user_id => 'admin-1' );
is( await_result( $admin->authorized_user_id('view') ),
    'admin-1', 'admin reads authorize the session actor' );
is_deeply(
    $gate_recorder->last_permission,
    {
        action        => 'view',
        resource_type => 'admin_console',
        resource_id   => undef,
        space_id      => undef,
    },
    'admin reads ask the gate for a global binding'
);

is_deeply(
    GPForum::Controller::Privacy::Base->new->global_permission_scope,
    { resource_id => undef, space_id => undef },
    'privacy checks are global by declaration'
);

done_testing();

sub _functions {
    my ($allowed) = @_;

    return GPForum::Test::AnsweringFunctions->new(
        answers => { admin_permission_allowed => [ { allowed => $allowed } ] }
    );
}

sub _gate {
    my ($functions) = @_;

    return GPForum::Service::Admin::PermissionGate->new(
        functions => $functions,
        schema    => {},
    );
}

sub _controller {
    my ( $host, $class, $path ) = @_;

    my $transaction = Mojo::Transaction::HTTP->new;
    $transaction->req->url( Mojo::URL->new($path) );
    push @live_transactions, $transaction;

    return $class->new( app => $host, tx => $transaction );
}

1;
