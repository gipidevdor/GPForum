# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use Scalar::Util qw(blessed);
use Test::More;

use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Infrastructure::Row;
use GPForum::Service::Admin::AuditReview;
use GPForum::Service::Admin::Bootstrapper;
use GPForum::Service::Admin::CategoryStore;
use GPForum::Service::Admin::ConsoleReader;
use GPForum::Service::Admin::PermissionReview;
use GPForum::Service::Admin::RoleBindingStore;
use GPForum::Service::Admin::RoleCatalog;
use GPForum::Service::Identity::Support;
use GPForum::Test::FixedClock;
use GPForum::Test::PgDatabase;
use GPForum::Test::ScriptedId;

our $VERSION = '0.001';
const my @LIMITS     => ( 1, 3, 100 );
const my $NOW        => '2026-10-01T12:00:00Z';
const my $PAGE_GUARD => 100;
const my $ID         => '018f1000-0000-7000-8000-000000000081';
const my $NEXT       => '018f1000-0000-7000-8000-000000000082';
const my $ROLE       => '018f1000-0000-7000-8000-000000000083';
const my $PERMISSION => '018f1000-0000-7000-8000-000000000084';
const my $CATEGORY   => '018f1000-0000-7000-8000-000000000085';
const my %TIME_KEY => map { $_ => 1 }
  qw(created_at updated_at revoked_at available_at next_attempt_at first_failed_at last_failed_at);

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to compare admin functions';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $schema   = $database->schema;
my $dbh      = $database->dbh;
my $user     = seed_id( user  => 1 );
my $space    = seed_id( space => 1 );
my $support  = GPForum::Service::Identity::Support->new;
my $clock    = GPForum::Test::FixedClock->new( iso8601 => $NOW );

_fixture();
_reads();
_audits();
_mutations();
_calls();
done_testing();

sub _fixture {
    $dbh->do(
q{INSERT INTO roles(role_id, name, description, created_at) VALUES (?, 'api-probe-role', 'probe', ?)},
        undef, $ROLE, $NOW
    );
    $dbh->do(
q{INSERT INTO permissions(permission_id, name, resource_type, action, created_at) VALUES (?, 'api-probe-action', 'api-probe', 'read', ?)},
        undef, $PERMISSION, $NOW
    );
    $dbh->do(
'INSERT INTO role_permissions(role_id, permission_id, created_at) VALUES (?, ?, ?)',
        undef, $ROLE, $PERMISSION, $NOW
    );
    $dbh->do(
q{INSERT INTO role_bindings(binding_id, user_id, role_id, resource_type, created_at) VALUES (?, ?, ?, 'global', ?)},
        undef, $NEXT, $user, $ROLE, $NOW
    );
    $dbh->do(
q{INSERT INTO categories(category_id, space_id, slug, title, created_at, updated_at) VALUES (?, ?, 'api-probe-category', 'Probe', ?, ?)},
        undef, $CATEGORY, $space, $NOW, $NOW
    );
    _store( 'RoleCatalog', 0 )->create_role(
        {
            actor_user_id => $user,
            name          => 'api-audited-role',
            description   => 'audit'
        }
    );
    return;
}

sub _reads {
    for my $limit (@LIMITS) {
        for my $method (qw(list_roles list_permissions)) {
            _compare(
                'RoleCatalog', $method,
                [ { limit => $limit } ],
                "catalogue $method/$limit"
            );
        }
        _compare(
            'CategoryStore',         'list_categories',
            [ { limit => $limit } ], "categories $limit"
        );
        _compare(
            'PermissionReview',             'roles_for_user',
            [ $user, { limit => $limit } ], "bindings $limit"
        );
        _compare(
            'PermissionReview',             'permissions_for_role',
            [ $ROLE, { limit => $limit } ], "attachments $limit"
        );
        for
          my $method (qw(list_users list_reports list_outbox list_dead_letters))
        {
            for my $status ( undef, 'active', 'open', 'pending' ) {
                _compare(
                    'ConsoleReader',
                    $method,
                    [ { limit => $limit, status => $status } ],
                    "console $method/$limit/" . ( $status // 'any' )
                );
            }
        }
    }
    for my $method (qw(count_outbox count_dead_letters)) {
        _compare( 'ConsoleReader', $method, [], $method );
    }
    _compare( 'ConsoleReader', 'email_of', [$user], 'administrator address' );
    is( _store( 'ConsoleReader', 0 )->email_of('invalid'),
        undef, 'malformed address lookup fails closed' );
    _compare( 'Bootstrapper', 'has_owner', ['api-probe-role'],
        'globally bound owner' );
    _compare( 'Bootstrapper', 'is_owner', [ { id => $user }, 'api-probe-role' ],
        'member owner' );
    my $username =
      $dbh->selectrow_array( 'SELECT username FROM users WHERE id = ?',
        undef, $user );
    _compare( 'Bootstrapper', 'find_member', [" $username "],
        'normalized bootstrap member' );
    return;
}

sub _audits {
    _compare( 'AuditReview', 'recent', [ { limit => 1 } ],
        'raw audit columns' );
    my $old = _store( 'AuditReview', 1 );
    my $new = _store( 'AuditReview', 0 );
    for my $filters (
        {},
        { actor_id    => $user },
        { action      => 'role.created' },
        { target_type => 'role' },
        { from        => '2026-10-01', until => '2026-10-01' }
      )
    {
        my $after;
        for my $page ( 1 .. $PAGE_GUARD ) {
            my $options  = { limit => 1, after => $after };
            my $expected = $old->page( $filters, $options );
            my $got      = $new->page( $filters, $options );
            is_deeply( _normalize($got), _normalize($expected),
                "audit filter page $page" );
            $after = $got->{next_cursor};
            last if !$after;
        }
    }
    my $row = $new->recent( { limit => 1 } )->[0];
    is_deeply(
        $row->get_inflated_column('metadata'),
        $old->recent( { limit => 1 } )->[0]->get_inflated_column('metadata'),
        'audit metadata also retains its inflated accessor'
    );
    return;
}

sub _mutations {
    _differential(
        'create role',
        sub ($old) {
            return _store( 'RoleCatalog', $old )
              ->create_role(
                { actor_user_id => $user, name => 'differential-role' } );
        }
    );
    _differential(
        'repeat role completes audit once',
        sub ($old) {
            return _store( 'RoleCatalog', $old )
              ->create_role(
                { actor_user_id => $user, name => 'api-probe-role' } );
        }
    );
    _differential(
        'create permission',
        sub ($old) {
            return _store( 'RoleCatalog', $old )->create_permission(
                {
                    actor_user_id => $user,
                    name          => 'differential-permission',
                    resource_type => 'differential',
                    action        => 'read'
                }
            );
        }
    );
    _differential(
        'attach permission',
        sub ($old) {
            return _store( 'RoleCatalog', $old )->attach_permission(
                {
                    actor_user_id => $user,
                    role_id       => $ROLE,
                    permission_id => $PERMISSION
                }
            );
        }
    );
    _differential(
        'repeat binding completes audit once',
        sub ($old) {
            return _store( 'RoleBindingStore', $old )->bind_role(
                {
                    actor_user_id => $user,
                    user_id       => $user,
                    role_id       => $ROLE,
                    resource_type => 'global',
                    resource_id   => undef,
                    space_id      => undef
                }
            );
        }
    );
    _differential(
        'new scoped binding',
        sub ($old) {
            return _store( 'RoleBindingStore', $old )->bind_role(
                {
                    actor_user_id => $user,
                    user_id       => $user,
                    role_id       => $ROLE,
                    resource_type => 'space',
                    resource_id   => $space,
                    space_id      => $space
                }
            );
        }
    );
    _differential(
        'revoke binding',
        sub ($old) {
            return _store( 'RoleBindingStore', $old )
              ->revoke_binding( $NEXT, $user );
        }
    );
    _differential(
        'create category',
        sub ($old) {
            return _store( 'CategoryStore', $old )->create_category(
                {
                    actor_user_id => $user,
                    space_id      => $space,
                    title         => 'Differential category',
                    slug          => 'differential-category'
                }
            );
        }
    );
    _differential(
        'update category',
        sub ($old) {
            return _store( 'CategoryStore', $old )->update_category(
                {
                    actor_user_id => $user,
                    category_id   => $CATEGORY,
                    title         => 'Changed',
                    visibility    => 'members'
                }
            );
        }
    );
    return;
}

sub _calls {
    my @statements;
    $schema->storage->debugcb(
        sub ( $kind, $statement ) { push @statements, $statement; } );
    $schema->storage->debug(1);
    _store( 'RoleCatalog',      0 )->list_roles( { limit => 1 } );
    _store( 'RoleCatalog',      0 )->list_permissions( { limit => 1 } );
    _store( 'PermissionReview', 0 )->roles_for_user( $user, {} );
    _store( 'CategoryStore',    0 )->list_categories( { limit => 1 } );
    _store( 'AuditReview',      0 )->recent( { limit => 1 } );
    _store( 'ConsoleReader',    0 )->list_users( { limit => 1 } );
    _store( 'Bootstrapper',     0 )->has_owner('api-probe-role');
    $schema->storage->debug(0);
    $schema->storage->debugcb(undef);
    ok( @statements, 'admin data operations were traced' );
    is_deeply(
        [ grep { !/\A SELECT [ ] [*] [ ] FROM [ ] api[.]/msx } @statements ],
        [], 'every admin read is a fixed API call' );
    return;
}

sub _differential ( $label, $operation ) {
    subtest $label => sub {
        my @runs;
        for my $old ( 1, 0 ) {
            $schema->txn_begin;
            my $answer = $operation->($old);
            push @runs, { answer => _normalize($answer), state => _state() };
            $schema->txn_rollback;
        }
        is_deeply( $runs[1], $runs[0], 'answer, domain rows and audit agree' );
    };
    return;
}

sub _state {
    return _normalize(
        {
            roles => $dbh->selectall_arrayref(
                'SELECT * FROM roles ORDER BY role_id',
                { Slice => {} }
            ),
            permissions => $dbh->selectall_arrayref(
                'SELECT * FROM permissions ORDER BY permission_id',
                { Slice => {} }
            ),
            attachments => $dbh->selectall_arrayref(
'SELECT * FROM role_permissions ORDER BY role_id, permission_id',
                { Slice => {} }
            ),
            bindings => $dbh->selectall_arrayref(
                'SELECT * FROM role_bindings ORDER BY binding_id',
                { Slice => {} }
            ),
            categories => $dbh->selectall_arrayref(
                'SELECT * FROM categories ORDER BY category_id',
                { Slice => {} }
            ),
            audits => $dbh->selectall_arrayref(
'SELECT action, actor_id, target_type, target_id, metadata FROM audit_log ORDER BY action, target_id, metadata::text',
                { Slice => {} }
            ),
        }
    );
}

sub _compare ( $kind, $method, $arguments, $label ) {
    is_deeply( _normalize( _store( $kind, 0 )->$method( @{$arguments} ) ),
        _normalize( _store( $kind, 1 )->$method( @{$arguments} ) ), $label );
    return;
}

sub _store ( $kind, $old ) {
    my $class = 'GPForum::Service::Admin::' . $kind;
    my %args  = ( schema => $schema, ( $old ? ( functions => undef ) : () ) );
    if (   $kind eq 'RoleCatalog'
        || $kind eq 'RoleBindingStore'
        || $kind eq 'CategoryStore'
        || $kind eq 'Bootstrapper' )
    {
        $args{clock} = $clock;
        $args{id_service} =
          GPForum::Test::ScriptedId->new( next_ids => [ $ID, $NEXT ] );
    }
    return $class->new(%args);
}

sub _normalize ( $value, $key = q{} ) {
    if ( blessed($value) && $value->can('get_columns') ) {
        $value = { $value->get_columns };
    }
    if ( ref $value eq 'ARRAY' ) {
        return [ map { _normalize($_) } @{$value} ];
    }
    if ( ref $value eq 'HASH' ) {
        return { map { $_ => _normalize( $value->{$_}, $_ ) } keys %{$value} };
    }
    if ( exists $TIME_KEY{$key} && defined $value ) {
        return $support->epoch_from_timestamp($value);
    }
    return $value;
}

1;
