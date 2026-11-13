# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Admin::RoleCatalog;
use GPForum::Test::AdminAuditLog;
use GPForum::Test::AnsweringFunctions;
use GPForum::Test::FixedClock;
use GPForum::Test::Id;

our $VERSION = '0.001';

const my $ATTACHED   => 'role_permission.attached';
const my $ROLE       => 'role-1';
const my $OTHER_ROLE => 'role-2';
const my $AUDITED    => 'permission-1';
const my $UNAUDITED  => 'permission-2';
const my $UPPER_ROLE => 'role-upper';
const my $UPPER_PERM => 'permission-upper';
const my $UUID_ROLE  => 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
const my $UUID_PERM  => '5f1c2d3e-4b5a-4c6d-8e7f-9a0b1c2d3e4f';
const my $UUID_OTHER => '6a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';

# An attachment's audit entry targets the role; only its metadata names the
# permission. The check for a lost entry used to match the role alone, so an
# attachment whose entry was lost stayed unaudited whenever another
# permission of the same role had been audited. The pair is matched in
# RoleCatalog, over the role's entries api.admin_attachment_audits reads;
# here the functions answer from the rows the test keeps, and
# t/integration/postgres-role-admin.t runs the same cases on PostgreSQL.
my $setup   = _fixture();
my $catalog = $setup->{catalog};

$catalog->attach_permission( _attach( $ROLE, $AUDITED ) );
is( _entries( $setup, $ROLE, $AUDITED ),
    1, 'a first attachment writes its audit entry' );

# The row of a second attachment was written; its entry was not.
push @{ $setup->{grants} },
  {
    created_at    => '2026-05-23T11:00:00Z',
    permission_id => $UNAUDITED,
    role_id       => $ROLE,
  };
is( _entries( $setup, $ROLE, $UNAUDITED ),
    0, 'the second attachment starts without an entry' );

my $completed = $catalog->attach_permission( _attach( $ROLE, $UNAUDITED ) );
ok( $completed->{idempotent},
    'attaching the pair again returns the existing attachment' );
is( $completed->{permission_id},
    $UNAUDITED, 'and it is the second permission' );
is(
    _entries( $setup, $ROLE, $UNAUDITED ),
    1,
    'the lost entry is written although another permission of the role was'
      . ' audited'
);
is( _entries( $setup, $ROLE, $AUDITED ),
    1, 'the audited attachment keeps its single entry' );

my $before = scalar @{ $setup->{audit} };
$catalog->attach_permission( _attach( $ROLE, $AUDITED ) );
$catalog->attach_permission( _attach( $ROLE, $UNAUDITED ) );
is( scalar @{ $setup->{audit} },
    $before, 'attaching audited pairs again writes nothing' );

# The same permission's entry on another role is not this pair's either.
push @{ $setup->{grants} },
  {
    created_at    => '2026-05-23T11:00:00Z',
    permission_id => $UNAUDITED,
    role_id       => $OTHER_ROLE,
  };
$catalog->attach_permission( _attach( $OTHER_ROLE, $UNAUDITED ) );
is( _entries( $setup, $OTHER_ROLE, $UNAUDITED ),
    1, 'an entry for the permission on another role does not count' );

# The metadata keeps the ids as the command spelled them; PostgreSQL hands
# the attachment's columns back in lower case.
push @{ $setup->{grants} },
  {
    created_at    => '2026-05-23T11:00:00Z',
    permission_id => $UPPER_PERM,
    role_id       => $UPPER_ROLE,
  };
push @{ $setup->{audit} },
  {
    action    => $ATTACHED,
    audit_id  => 'audit-upper',
    metadata  => { permission_id => uc $UPPER_PERM, role_id => uc $UPPER_ROLE },
    target_id => $UPPER_ROLE,
    target_type => 'role',
  };
$before = scalar @{ $setup->{audit} };
$catalog->attach_permission( _attach( $UPPER_ROLE, $UPPER_PERM ) );
is( scalar @{ $setup->{audit} },
    $before, 'an entry naming the pair in upper case counts as written' );

# PostgreSQL also reads a uuid in braces or without its hyphens and hands
# back its canonical form, so the entry may spell the pair differently from
# the row. Compared as lower-cased text, it did not count and a second entry
# was written on every repeat.
push @{ $setup->{grants} },
  {
    created_at    => '2026-05-23T11:00:00Z',
    permission_id => $UUID_PERM,
    role_id       => $UUID_ROLE,
  };
push @{ $setup->{audit} },
  {
    action   => $ATTACHED,
    audit_id => 'audit-spelled',
    metadata => {
        permission_id => $UUID_PERM =~ tr/-//dr,
        role_id       => '{' . uc($UUID_ROLE) . '}',
    },
    target_id   => $UUID_ROLE,
    target_type => 'role',
  };
$before = scalar @{ $setup->{audit} };
$catalog->attach_permission( _attach( $UUID_ROLE, $UUID_PERM ) );
is( scalar @{ $setup->{audit} },
    $before,
    'an entry naming the pair in braces or without hyphens counts as written' );

# Spelled that way, another permission's id is still another permission.
push @{ $setup->{grants} },
  {
    created_at    => '2026-05-23T11:00:00Z',
    permission_id => $UUID_OTHER,
    role_id       => $UUID_ROLE,
  };
$catalog->attach_permission( _attach( $UUID_ROLE, $UUID_OTHER ) );
is( _entries( $setup, $UUID_ROLE, $UUID_OTHER ),
    1, 'an entry for another uuid of the same role does not count' );

done_testing();

# The role's attachments and the audit log as rows, read and written by
# the functions RoleCatalog calls.
sub _fixture {
    my ( @grants, @audit );
    my $functions = GPForum::Test::AnsweringFunctions->new(
        answers => {
            admin_attachment_audits => sub ($values) {
                return [
                    grep {
                             $_->{action} eq $values->{action}
                          && $_->{target_id} eq $values->{target_id}
                    } @audit
                ];
            },
            admin_insert_role_permission => sub ($values) {
                push @grants, $values->{values};
                return [ $values->{values} ];
            },
            admin_lookup_role_permission => sub ($values) {
                my $query = $values->{query};
                return [
                    grep {
                             $_->{role_id} eq $query->{role_id}
                          && $_->{permission_id} eq $query->{permission_id}
                    } @grants
                ];
            },
            ops_record_audit => sub ($values) {
                push @audit, $values->{audit};
                return [ { audit => $values->{audit} } ];
            },
        }
    );

    return {
        audit   => \@audit,
        catalog => GPForum::Service::Admin::RoleCatalog->new(
            clock      => GPForum::Test::FixedClock->new,
            functions  => $functions,
            id_service => GPForum::Test::Id->new,
            recorder   => GPForum::Test::AdminAuditLog->new,
            schema     => {},
        ),
        grants => \@grants,
    };
}

sub _attach {
    my ( $role_id, $permission_id ) = @_;

    return {
        actor_user_id => 'admin-1',
        permission_id => $permission_id,
        role_id       => $role_id,
    };
}

sub _entries {
    my ( $fixture, $role_id, $permission_id ) = @_;

    my @entries = grep {
             $_->{action} eq $ATTACHED
          && $_->{target_id} eq $role_id
          && $_->{metadata}{role_id} eq $role_id
          && $_->{metadata}{permission_id} eq $permission_id
    } @{ $fixture->{audit} };

    return scalar @entries;
}

1;
