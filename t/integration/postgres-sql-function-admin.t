# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use JSON::MaybeXS;
use Test::More;

use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Infrastructure::Row    qw(column_of);
use GPForum::Service::Admin::AuditReview;
use GPForum::Service::Admin::Bootstrapper;
use GPForum::Service::Admin::CategoryStore;
use GPForum::Service::Admin::ConsoleReader;
use GPForum::Service::Admin::PermissionReview;
use GPForum::Service::Admin::RoleBindingStore;
use GPForum::Service::Admin::RoleCatalog;
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
const my $JSON       => JSON::MaybeXS->new( canonical => 1 );

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to check the admin functions';
}

# The admin area's api.admin_* functions on a seeded database, each held to
# a stated answer: the rows a plain query over the tables gives in the
# order the console documents, and for each write the rows and audit
# entries it leaves. These answers are those the Perl readers and writers
# gave before they were removed (ADR 0177); the functions matched them.
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $schema   = $database->schema;
my $dbh      = $database->dbh;
my $user     = seed_id( user  => 1 );
my $space    = seed_id( space => 1 );
my $clock    = GPForum::Test::FixedClock->new( iso8601 => $NOW );

_fixture();
_reads();
_console_reads();
_owner_reads();
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
    _store('RoleCatalog')->create_role(
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
        _stated(
            [ _store('RoleCatalog')->list_roles( { limit => $limit } ) ],
            'role_id',
            'SELECT role_id FROM roles ORDER BY name LIMIT ?',
            [$limit],
            "roles by name, $limit at most"
        );
        _stated(
            [ _store('RoleCatalog')->list_permissions( { limit => $limit } ) ],
            'permission_id',
            'SELECT permission_id FROM permissions'
              . ' ORDER BY resource_type, action, name LIMIT ?',
            [$limit],
            "permissions by resource type, action and name, $limit at most"
        );
        _stated(
            [ _store('CategoryStore')->list_categories( { limit => $limit } ) ],
            'category_id',
            'SELECT category_id FROM categories'
              . ' ORDER BY position, title, category_id LIMIT ?',
            [$limit],
            "categories by position and title, $limit at most"
        );
        _stated(
            [
                _store('PermissionReview')
                  ->roles_for_user( $user, { limit => $limit } )
            ],
            'binding_id',
            'SELECT binding_id FROM role_bindings'
              . ' WHERE user_id = ? AND revoked_at IS NULL'
              . ' ORDER BY resource_type, role_id LIMIT ?',
            [ $user, $limit ],
            "a member's unrevoked bindings, $limit at most"
        );
    }
    return;
}

sub _console_reads {
    my $console = _store('ConsoleReader');
    for my $limit (@LIMITS) {
        for my $status ( undef, 'active', 'open', 'pending' ) {
            my $options = { limit => $limit, status => $status };
            my $named   = $status // 'any';
            _stated(
                [ $console->list_users($options) ],
                'id',
                'SELECT id FROM users WHERE status = coalesce(?, status)'
                  . ' ORDER BY created_at DESC, username LIMIT ?',
                [ $status, $limit ],
                "users newest first, $named, $limit at most"
            );
            _stated(
                [ $console->list_reports($options) ],
                'report_id',
q{SELECT report_id FROM reports WHERE status = coalesce(?, 'open')}
                  . ' ORDER BY created_at, report_id LIMIT ?',
                [ $status, $limit ],
                "reports oldest first, $named or open, $limit at most"
            );
            _stated(
                [ $console->list_outbox($options) ],
                'outbox_id',
                'SELECT outbox_id FROM outbox_messages'
                  . ' WHERE status = coalesce(?, status)'
                  . ' ORDER BY created_at DESC, outbox_id DESC LIMIT ?',
                [ $status, $limit ],
                "outbox newest first, $named, $limit at most"
            );
        }
        _stated(
            [ $console->list_dead_letters( { limit => $limit } ) ],
            'dead_letter_id',
            'SELECT dead_letter_id FROM dead_letters'
              . ' ORDER BY last_failed_at DESC, dead_letter_id DESC LIMIT ?',
            [$limit],
            "dead letters latest failure first, $limit at most"
        );
    }
    is(
        $console->count_outbox,
        _value('SELECT count(*) FROM outbox_messages'),
        'the outbox is counted whole'
    );
    is(
        $console->count_dead_letters,
        _value('SELECT count(*) FROM dead_letters'),
        'as are the dead letters'
    );
    is(
        $console->email_of($user),
        _value( 'SELECT email_normalized FROM users WHERE id = ?', $user ),
        'administrator address'
    );
    is( $console->email_of('invalid'),
        undef, 'malformed address lookup fails closed' );
    return;
}

sub _owner_reads {
    my $bootstrapper = _store('Bootstrapper');
    is( $bootstrapper->has_owner('api-probe-role'),
        1, 'a role bound globally has its owner' );
    is( $bootstrapper->has_owner('api-audited-role'),
        0, 'a role bound to nobody has none' );
    is( $bootstrapper->is_owner( { id => $user }, 'api-probe-role' ),
        1, 'the member bound to it is its owner' );
    is(
        $bootstrapper->is_owner(
            { id => seed_id( user => 2 ) },
            'api-probe-role'
        ),
        0,
        'another member is not'
    );
    my $username = _value( 'SELECT username FROM users WHERE id = ?', $user );
    my $member   = $bootstrapper->find_member(" \U$username\E ");
    is( $member->{id}, $user,
        'a member is found by username, trimmed and in any case' );
    is( $member->{username}, $username, 'and answered with it' );
    is( $bootstrapper->find_member('nobody-at-all'),
        undef, 'nobody is found for an unknown name' );
    return;
}

sub _audits {
    my $review = _store('AuditReview');
    my ($newest) = @{ $review->recent( { limit => 1 } ) };
    is(
        $newest->get_column('audit_id'),
        _value(
'SELECT audit_id FROM audit_log ORDER BY created_at DESC, audit_id DESC LIMIT 1'
        ),
        'the newest audit row first'
    );
    is_deeply(
        $newest->get_inflated_column('metadata'),
        $JSON->decode(
            _value(
                'SELECT metadata::text FROM audit_log WHERE audit_id = ?',
                $newest->get_column('audit_id')
            )
        ),
        'audit metadata also retains its inflated accessor'
    );
    for my $case (
        [ {}, 'TRUE' ],
        [ { actor_id    => $user },          'actor_id = ?', $user ],
        [ { action      => 'role.created' }, 'action = ?',   'role.created' ],
        [ { target_type => 'role' },         'target_type = ?', 'role' ],
        [
            { from => '2026-10-01', until => '2026-10-01' },
            q{created_at >= '2026-10-01T00:00:00Z'}
              . q{ AND created_at < '2026-10-02T00:00:00Z'}
        ],
      )
    {
        my ( $filters, $where, @values ) = @{$case};
        my ( @paged, $after );
        for my $page ( 1 .. $PAGE_GUARD ) {
            my $got =
              $review->page( $filters, { limit => 1, after => $after } );
            push @paged, map { $_->get_column('audit_id') } @{ $got->{rows} };
            $after = $got->{next_cursor};
            last if !$after;
        }
        is_deeply(
            \@paged,
            $dbh->selectcol_arrayref(
                "SELECT audit_id FROM audit_log WHERE $where"
                  . ' ORDER BY created_at DESC, audit_id DESC LIMIT ?',
                undef,
                @values,
                $PAGE_GUARD
            ),
            'paged one row at a time, newest first: ' . $JSON->encode($filters)
        );
    }
    return;
}

sub _mutations {

    # The fixture's audited role took the first id drawn: the role is
    # minted the next one on the conflict, and the audit names it.
    _wrote(
        'create role',
        sub {
            return _store('RoleCatalog')
              ->create_role(
                { actor_user_id => $user, name => 'differential-role' } );
        },
        { role_id => $NEXT, name => 'differential-role' },
        [ [ 'role.created', $NEXT ] ],
        [
            q{SELECT count(*) FROM roles WHERE role_id = ?}
              . q{ AND name = 'differential-role'},
            $NEXT
        ]
    );
    _wrote(
        'repeat role completes audit once',
        sub {
            return _store('RoleCatalog')
              ->create_role(
                { actor_user_id => $user, name => 'api-probe-role' } );
        },
        { role_id => $ROLE, idempotent => 1 },
        [ [ 'role.created', $ROLE ] ],
        [q{SELECT count(*) FROM roles WHERE name = 'api-probe-role'}]
    );
    _wrote(
        'create permission',
        sub {
            return _store('RoleCatalog')->create_permission(
                {
                    actor_user_id => $user,
                    name          => 'differential-permission',
                    resource_type => 'differential',
                    action        => 'read'
                }
            );
        },
        { permission_id => $ID, name => 'differential-permission' },
        [ [ 'permission.created', $ID ] ],
        [ 'SELECT count(*) FROM permissions WHERE permission_id = ?', $ID ]
    );
    _wrote(
        'attach permission',
        sub {
            return _store('RoleCatalog')->attach_permission(
                {
                    actor_user_id => $user,
                    role_id       => $ROLE,
                    permission_id => $PERMISSION
                }
            );
        },
        { role_id => $ROLE, permission_id => $PERMISSION, idempotent => 1 },
        [ [ 'role_permission.attached', $ROLE ] ],
        [
            'SELECT count(*) FROM role_permissions'
              . ' WHERE role_id = ? AND permission_id = ?',
            $ROLE,
            $PERMISSION
        ]
    );
    _wrote(
        'repeat binding completes audit once',
        sub {
            return _store('RoleBindingStore')->bind_role( _binding('global') );
        },
        { ok => 1, idempotent => 1, binding_id => $NEXT },
        [ [ 'role_binding.created', $NEXT ] ],
        [ 'SELECT count(*) FROM role_bindings WHERE binding_id = ?', $NEXT ]
    );
    _wrote(
        'new scoped binding',
        sub {
            return _store('RoleBindingStore')->bind_role( _binding('space') );
        },
        { ok => 1, binding_id => $ID },
        [ [ 'role_binding.created', $ID ] ],
        [
            'SELECT count(*) FROM role_bindings'
              . ' WHERE binding_id = ? AND space_id = ? AND resource_id = ?',
            $ID, $space, $space
        ]
    );
    _wrote(
        'revoke binding',
        sub {
            return _store('RoleBindingStore')->revoke_binding( $NEXT, $user );
        },
        { binding_id => $NEXT },
        [ [ 'role_binding.revoked', $NEXT ] ],
        [
            'SELECT count(*) FROM role_bindings'
              . ' WHERE binding_id = ? AND revoked_at IS NOT NULL',
            $NEXT
        ]
    );
    _wrote(
        'create category',
        sub {
            return _store('CategoryStore')->create_category(
                {
                    actor_user_id => $user,
                    space_id      => $space,
                    title         => 'Differential category',
                    slug          => 'differential-category'
                }
            );
        },
        { slug => 'differential-category', space_id => $space },
        [ [ 'category.created', $ID ] ],
        [
            q{SELECT count(*) FROM categories}
              . q{ WHERE category_id = ? AND slug = 'differential-category'},
            $ID
        ]
    );
    _wrote(
        'update category',
        sub {
            return _store('CategoryStore')->update_category(
                {
                    actor_user_id => $user,
                    category_id   => $CATEGORY,
                    title         => 'Changed',
                    visibility    => 'members'
                }
            );
        },
        {
            category_id => $CATEGORY,
            title       => 'Changed',
            visibility  => 'members'
        },
        [ [ 'category.updated', $CATEGORY ] ],
        [
            q{SELECT count(*) FROM categories WHERE category_id = ?}
              . q{ AND title = 'Changed' AND visibility = 'members'},
            $CATEGORY
        ]
    );
    return;
}

sub _calls {
    my @statements;
    $schema->storage->debugcb(
        sub ( $kind, $statement ) { push @statements, $statement; } );
    $schema->storage->debug(1);
    _store('RoleCatalog')->list_roles( { limit => 1 } );
    _store('RoleCatalog')->list_permissions( { limit => 1 } );
    _store('PermissionReview')->roles_for_user( $user, {} );
    _store('CategoryStore')->list_categories( { limit => 1 } );
    _store('AuditReview')->recent( { limit => 1 } );
    _store('ConsoleReader')->list_users( { limit => 1 } );
    _store('Bootstrapper')->has_owner('api-probe-role');
    $schema->storage->debug(0);
    $schema->storage->debugcb(undef);
    ok( @statements, 'admin data operations were traced' );
    is_deeply(
        [ grep { !/\A SELECT [ ] [*] [ ] FROM [ ] api[.]/msx } @statements ],
        [], 'every admin read is a fixed API call' );
    return;
}

# The keys of the rows a read answered, against those the query states.
sub _stated ( $rows, $key, $sql, $values, $label ) {
    my @rows = map { ref $_ eq 'ARRAY' ? @{$_} : $_ } @{$rows};
    is_deeply( [ map { column_of( $_, $key ) } @rows ],
        $dbh->selectcol_arrayref( $sql, undef, @{$values} ), $label );
    return;
}

# A write inside a transaction rolled back after: what it answered, the
# audit entries it added, as [action, target], and the row it left.
sub _wrote ( $label, $operation, $answered, $audits, $row ) {
    subtest $label => sub {
        $schema->txn_begin;
        my $before = _audit_ids();
        my $answer = $operation->();
        my $added  = $dbh->selectall_arrayref(
            'SELECT action, target_id::text FROM audit_log'
              . ' WHERE audit_id::text <> ALL (?) ORDER BY action, target_id',
            undef, $before
        );
        my ( $sql, @values ) = @{$row};
        my $stored = _value( $sql, @values );
        $schema->txn_rollback;

        for my $key ( sort keys %{$answered} ) {
            is( _answered( $answer, $key ), $answered->{$key}, "answers $key" );
        }
        is_deeply( $added, $audits, 'audits it once' );
        is( $stored, 1, 'and leaves the row' );
    };
    return;
}

# A store answers its row whole, or under binding or category.
sub _answered ( $answer, $key ) {
    for my $holder ( $answer, $answer->{binding}, $answer->{category} ) {
        next if ref $holder ne 'HASH' || !exists $holder->{$key};
        return $holder->{$key};
    }
    return column_of( $answer, $key );
}

sub _binding ($scope) {
    my $space_scope = $scope eq 'space' ? $space : undef;
    return {
        actor_user_id => $user,
        user_id       => $user,
        role_id       => $ROLE,
        resource_type => $scope,
        resource_id   => $space_scope,
        space_id      => $space_scope
    };
}

sub _audit_ids {
    return $dbh->selectcol_arrayref('SELECT audit_id::text FROM audit_log');
}

sub _value ( $sql, @values ) {
    return scalar $dbh->selectrow_array( $sql, undef, @values );
}

sub _store ($kind) {
    my $class = 'GPForum::Service::Admin::' . $kind;
    return $class->new(
        clock      => $clock,
        id_service =>
          GPForum::Test::ScriptedId->new( next_ids => [ $ID, $NEXT ] ),
        schema => $schema,
    );
}

1;
