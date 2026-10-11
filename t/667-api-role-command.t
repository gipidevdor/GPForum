# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Test::Exception;
use Test::More;
use lib 'lib';
use GPForum::Command::ApiRole;
use GPForum::Command::Support::Verbs;
use GPForum::Config;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Schema;
use GPForum::Service::Admin::Settings;

our $VERSION = '0.001';

my $config = GPForum::Config->new(
    database_dsn            => 'dbi:Pg:dbname=runtime_never_connect',
    database_user           => 'runtime_never_connect',
    database_password       => 'runtime-secret',
    admin_database_password => 'admin-secret',
);
throws_ok { GPForum::Command::ApiRole->new( config => $config )->_admin_dbh }
qr/requires [ ] GPFORUM_ADMIN_DATABASE_USER/msx,
  'administrative provisioning never falls back to the runtime login';
my $settings = GPForum::Service::Admin::Settings->new( config => $config );
is( $settings->redact('runtime-secret/admin-secret'),
    '[redacted]/[redacted]',
    'administrator credentials are redacted with runtime credentials' );
my $read = GPForum::Config->from_environment(
    {
        GPFORUM_ADMIN_DATABASE_DSN      => 'dbi:Pg:dbname=owner',
        GPFORUM_ADMIN_DATABASE_USER     => 'owner',
        GPFORUM_ADMIN_DATABASE_PASSWORD => 'owner-secret',
    }
);
is( $read->admin_database_user,
    'owner', 'administrative connection settings are read separately' );
is( $read->database_user, 'gpforum',
    'the runtime default remains independent' );
my $verb = GPForum::Command::Support::Verbs->find('api-role');
is( $verb->{command}, 'api_role', 'the front door reaches provisioning' );
like(
    GPForum::Command::ApiRole->new->usage_text,
    qr/Plans [ ] by [ ] default/msx,
    'the operator sees that changing grants requires --apply'
);
throws_ok {
    GPForum::Infrastructure::SqlFunction->for_schema( GPForum::Schema->connect )
}
'GPForum::X::Argument',
  'unconfigured real schemas cannot silently fall back to ORM';
done_testing();

1;
