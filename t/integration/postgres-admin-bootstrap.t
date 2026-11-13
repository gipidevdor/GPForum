# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::AdminBootstrap;
use GPForum::Service::Admin::Bootstrapper;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

const my $EXIT_USAGE => 2;
const my $OWNER      => '018f1b00-0001-7000-8000-000000000001';
const my $GRANTEE    => '018f1b00-0001-7000-8000-000000000002';
const my $OPERATOR   => '018f1b00-0001-7000-8000-000000000003';
const my $UNNAMED    => '018f1b00-0001-7000-8000-000000000004';
const my $USER_SQL => join q{ },
  'INSERT INTO users (id, username, display_name, email_normalized,',
  q{password_hash, status) VALUES (?, ?, ?, ?, 'x', 'active')};
const my $ACTORS_SQL =>
  'SELECT DISTINCT actor_id::text FROM audit_log WHERE audit_id <> ALL (?)'
  . ' ORDER BY 1';
const my $BINDINGS_SQL =>
  'SELECT count(*) FROM role_bindings WHERE user_id = ? AND role_id = ?';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_DATABASE_DSN to run the admin bootstrap test';
}

# The first owner's role, as gpforum admin grant makes it on PostgreSQL: the
# owner role, every default permission attached to it and a global binding,
# each audited under the operator who ran it -- or under the member made
# owner when no operator is named -- and a second run that finds the rows
# the first created and reports them with their ids.
my $database = GPForum::Test::PgDatabase->fresh;
my $dbh      = $database->dbh;
for my $member (
    [ $OWNER,    'owner' ],
    [ $GRANTEE,  'grantee' ],
    [ $OPERATOR, 'operator' ],
    [ $UNNAMED,  'unnamed' ],
  )
{
    my ( $id, $name ) = @{$member};
    $dbh->do( $USER_SQL, undef, $id, $name, $name, "$name\@example.test" );
}

my $bootstrapper =
  GPForum::Service::Admin::Bootstrapper->new( schema => $database->schema );

_first_bootstrap();
_custom_role_command();
_dry_run();
_usage_errors();
_unnamed_operator();

done_testing();

sub _first_bootstrap {
    my $before = _audit_ids();
    my $first  = $bootstrapper->bootstrap(
        { actor_user_id => $OPERATOR, user_id => $OWNER } );
    my $permissions = scalar @{ $first->{permissions} };

    is( $first->{role}{name}, 'gpforum_owner', 'bootstrap creates owner role' );
    is_deeply(
        $first->{counts},
        {
            bindings_created          => 1,
            permissions_created       => $permissions,
            role_permissions_attached => $permissions,
            roles_created             => 1,
        },
        'and each default permission, its attachment and the binding'
    );
    is( $first->{binding}{resource_type},
        'global', 'bootstrap uses global scope binding' );
    is( $first->{binding}{created_by_user_id},
        $OPERATOR, 'and the binding is created by the operator' );
    is(
        scalar @{ _audit_ids($before) },
        1 + $permissions * 2 + 1,
        'bootstrap audits role, permissions, attachments, and binding'
    );
    is_deeply( _audit_actors($before), [$OPERATOR],
        'every audit row of the bootstrap names the operator' );

    for my $name (
        qw(admin_console.manage report.view_queue post.moderate
        user.suspend privacy_rights.manage member_note.view member_note.write
        avatar.moderate)
      )
    {
        ok( _has_permission( $first, $name ), "bootstrap includes $name" );
    }

    my $audited = _audit_ids();
    my $again   = $bootstrapper->bootstrap(
        { actor_user_id => $OPERATOR, user_id => $OWNER } );
    is_deeply(
        $again->{counts},
        {
            bindings_created          => 0,
            permissions_created       => 0,
            role_permissions_attached => 0,
            roles_created             => 0,
        },
        'a second bootstrap reuses the role, permissions and binding'
    );
    is_deeply(
        [
            @{ $again->{binding} }
              {qw(binding_id role_id user_id created_by_user_id)}
        ],
        [
            @{ $first->{binding} }
              {qw(binding_id role_id user_id created_by_user_id)}
        ],
        'and reports the binding the first created'
    );
    is( $again->{role}{role_id}, $first->{role}{role_id}, 'and its role' );
    is_deeply(
        [ map { $_->{permission}{permission_id} } @{ $again->{permissions} } ],
        [ map { $_->{permission}{permission_id} } @{ $first->{permissions} } ],
        'and each of its permissions'
    );
    is( scalar @{ _audit_ids($audited) }, 0, 'and audits nothing again' );
    is(
        $dbh->selectrow_array(
            'SELECT count(*) FROM roles WHERE name = ?', undef,
            'gpforum_owner'
        ),
        1,
        'idempotent bootstrap avoids duplicate role rows'
    );
    is(
        $dbh->selectrow_array(
            $BINDINGS_SQL, undef, $OWNER, $first->{role}{role_id}
        ),
        1,
        'idempotent bootstrap avoids duplicate bindings'
    );
    ok( $bootstrapper->has_owner, 'the forum has its owner' );
    ok( $bootstrapper->is_owner( { id => $OWNER } ), 'and it is the owner' );
    return;
}

sub _custom_role_command {
    my $output = _capture_stdout(
        sub {
            return GPForum::Command::AdminBootstrap->new(
                schema => $database->schema )
              ->run( 'grant', '--user-id', $GRANTEE, '--actor-user-id',
                $OPERATOR, '--role-name', 'custom_owner' );
        }
    );
    like(
        $output,
qr/User [ ] \Q$GRANTEE\E [ ] holds [ ] the [ ] custom_owner [ ] role[.]/msx,
        'admin bootstrap command says the user holds the role it chose'
    );
    unlike( $output, qr/already/msx,
        'admin bootstrap command reports the binding it created as new' );
    ok( $bootstrapper->is_owner( { id => $GRANTEE }, 'custom_owner' ),
        'admin bootstrap command writes binding' );
    return;
}

# A dry run grants nothing.
sub _dry_run {
    my $before = _audit_ids();
    my $output = _capture_stdout(
        sub {
            return GPForum::Command::AdminBootstrap->new(
                schema => $database->schema )
              ->run( 'grant', '--user-id', $GRANTEE, '--dry-run' );
        }
    );
    like(
        $output,
qr/Would [ ] give [ ] user [ ] \Q$GRANTEE\E [ ] the [ ] gpforum_owner [ ] role/msx,
        'a dry run by id says what it would grant'
    );
    ok( !$bootstrapper->is_owner( { id => $GRANTEE } ), 'and binds no role' );
    is( scalar @{ _audit_ids($before) }, 0, 'nor audits one' );
    return;
}

sub _usage_errors {
    my $command =
      GPForum::Command::AdminBootstrap->new( schema => $database->schema );
    is( _usage_status( sub { return $command->run('--unknown'); } ),
        $EXIT_USAGE, 'unknown admin bootstrap option fails with usage' );
    is(
        _usage_status( sub { return $command->run( 'grant', '--user-id' ); } ),
        $EXIT_USAGE,
        'admin bootstrap requires value for user id'
    );
    return;
}

# Without an operator, the member made owner is the actor; here the role
# exists, so only the binding is written and audited.
sub _unnamed_operator {
    my $before = _audit_ids();
    my $owner  = $bootstrapper->bootstrap( { user_id => $UNNAMED } );
    is_deeply( _audit_actors($before), [$UNNAMED],
        'without an operator every audit row names the new owner' );
    is( $owner->{binding}{created_by_user_id}, $UNNAMED,
        'as does the binding' );
    return;
}

# The audit rows written since the ids given, or every row.
sub _audit_ids {
    my ($before) = @_;

    my %seen = map { $_ => 1 } @{ $before // [] };
    return [ grep { !$seen{$_} }
          @{ $dbh->selectcol_arrayref('SELECT audit_id::text FROM audit_log') }
    ];
}

sub _audit_actors {
    my ($before) = @_;

    return $dbh->selectcol_arrayref( $ACTORS_SQL, undef, $before );
}

sub _has_permission {
    my ( $result, $permission_name ) = @_;

    return
      scalar grep { $_->{permission}{name} eq $permission_name }
      @{ $result->{permissions} };
}

sub _capture_stdout {
    my ($code) = @_;

    my $captured = q{};
    open my $stdout, '>', \$captured or croak 'failed to capture stdout';
    {
        local *STDOUT = $stdout;
        $code->();
    }
    close $stdout or croak 'failed to close stdout capture';

    return $captured;
}

# A usage error is no exception: the command returns the documented exit
# status and prints the usage text to stderr.
sub _usage_status {
    my ($code) = @_;

    my $errors = q{};
    open my $capture, '>', \$errors or croak 'capture stderr';
    my $status;
    {
        local *STDERR = $capture;
        $status = $code->();
    }
    close $capture or croak 'close stderr';
    like( $errors, qr/Usage/msx, 'the usage text goes to stderr' );

    return $status;
}

1;
