# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Admin::RoleBindingStore;
use GPForum::Test::AdminAuditLog;
use GPForum::Test::TransactionFunctions;

our $VERSION = '0.001';

# A role binding's writes as RoleBindingStore sends them to the api.admin_*
# functions, on a call layer that answers as stated and records each
# transaction: which calls share one, how an id conflict is retried, and
# what a failure leaves. The functions themselves, the FOR UPDATE that
# serialises two revocations among them, run on PostgreSQL in
# t/integration/postgres-role-admin.t.

my %BINDING_INPUT = (
    actor_user_id => 'actor-1',
    resource_id   => 'space-1',
    resource_type => 'space',
    role_id       => 'role-1',
    space_id      => 'space-1',
    user_id       => 'user-1',
);

my $functions = GPForum::Test::TransactionFunctions->new;
my $bound     = _store($functions)->bind_role( {%BINDING_INPUT} );
ok( $bound->{ok}, 'bind_role stores a new binding' );
is_deeply(
    $functions->transactions->[0]{calls},
    [qw(admin_lookup_binding admin_insert_binding ops_record_audit)],
    'bind_role looks, inserts and audits in one transaction'
);
is_deeply(
    $functions->transactions->[1]{calls},
    [qw(admin_insert_binding ops_record_audit)],
    'the insert and its audit in a savepoint of it'
);
is(
    $functions->asked('admin_insert_binding')->[0]{values}{binding_id},
    $bound->{binding}{binding_id},
    'the binding answered is the one sent'
);
is(
    $functions->asked('ops_record_audit')->[0]{audit}{target_id},
    $bound->{binding}{binding_id},
    'and the one audited'
);

my $binding_id = $bound->{binding}{binding_id};
my $open       = GPForum::Test::TransactionFunctions->new(
    answers => { admin_lock_binding => [ _stored($binding_id) ] } );
my $revoked = _store($open)->revoke_binding( $binding_id, 'actor-2' );
is( $revoked->{binding_id}, $binding_id, 'revoke_binding reports the binding' );
ok( defined $revoked->{revoked_at}, 'with when it was revoked' );
is_deeply(
    $open->transactions->[0]{calls},
    [qw(admin_lock_binding admin_revoke_binding ops_record_audit)],
    'revoke_binding locks, revokes and audits in one transaction'
);

my $closed = GPForum::Test::TransactionFunctions->new(
    answers => {
        admin_lock_binding =>
          [ _stored( $binding_id, revoked_at => '2026-05-23T12:00:00Z' ) ]
    }
);
my $again = _store($closed)->revoke_binding( $binding_id, 'actor-3' );
ok( $again->{idempotent}, 'a second revocation is reported, not repeated' );
is_deeply(
    [ map { $_->[0] } @{ $closed->calls } ],
    ['admin_lock_binding'],
    'and records no second revocation audit'
);
is(
    _store( GPForum::Test::TransactionFunctions->new )
      ->revoke_binding( 'missing', 'actor-3' ),
    undef,
    'a binding that does not exist cannot be revoked'
);

# A minted id already stored is minted once more, in a fresh savepoint.
my $inserts = 0;
my $taken   = GPForum::Test::TransactionFunctions->new(
    answers => {
        admin_insert_binding => sub ($values) {
            if ( !$inserts++ ) {
                GPForum::Infrastructure::UniqueConflict->throw(
                    'role_bindings_pkey');
            }
            return [ {} ];
        },
    }
);
my $retried = _store($taken)->bind_role( {%BINDING_INPUT} );
ok( $retried->{ok}, 'an id conflict is retried' );
is( $inserts, 2, 'exactly once' );
isnt(
    $taken->asked('admin_insert_binding')->[0]{values}{binding_id},
    $taken->asked('admin_insert_binding')->[1]{values}{binding_id},
    'with a new id'
);
is( scalar @{ $taken->asked('ops_record_audit') },
    1, 'and one audit row, for the insert that stood' );

# A concurrent request that won the active key leaves its binding to reuse.
my $raced = GPForum::Test::TransactionFunctions->new(
    answers => {
        admin_insert_binding => sub ($values) {
            GPForum::Infrastructure::UniqueConflict->throw(
                'idx_role_bindings_active_unique');
        },
        admin_lookup_audit   => [ { audit_id => 'audit-1' } ],
        admin_lookup_binding => sub ($values) {
            state $lookups = 0;
            return $lookups++ ? [ _stored('binding-won') ] : [];
        },
    }
);
my $reused = _store($raced)->bind_role( {%BINDING_INPUT} );
ok( $reused->{idempotent}, 'a binding the race left is reused' );
is( $reused->{binding}{binding_id}, 'binding-won', 'that binding' );
is( scalar @{ $raced->asked('ops_record_audit') },
    0, 'with no second audit row when it has one' );

# Any other failure propagates, and nothing is returned.
my $failing = GPForum::Test::TransactionFunctions->new(
    answers => {
        admin_insert_binding => sub ($values) {
            die "role binding store offline\n";
        },
    }
);
my ( $failed, $failure );
try {
    $failed = _store($failing)->bind_role( {%BINDING_INPUT} );
}
catch ($error) {
    $failure = $error;
};
like(
    $failure,
    qr/role [ ] binding [ ] store [ ] offline/msx,
    'a thrown insert error still propagates to the caller'
);
ok( !defined $failed, 'nothing is returned when the insert throws' );
is( scalar @{ $failing->asked('admin_insert_binding') },
    1, 'and it is not retried' );

done_testing();

sub _store {
    my ($layer) = @_;

    return GPForum::Service::Admin::RoleBindingStore->new(
        functions => $layer,
        recorder  => GPForum::Test::AdminAuditLog->new,
        schema    => {},
    );
}

sub _stored {
    my ( $stored_id, %columns ) = @_;

    return {
        binding_id         => $stored_id,
        created_at         => '2026-05-23T11:00:00Z',
        created_by_user_id => 'actor-1',
        resource_id        => 'space-1',
        resource_type      => 'space',
        revoked_at         => undef,
        role_id            => 'role-1',
        space_id           => 'space-1',
        user_id            => 'user-1',
        %columns,
    };
}

1;
