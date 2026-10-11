# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Command::ApiRole;

use Carp qw(croak);
use Const::Fast;
use DBI;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Command::Usage;
use GPForum::Config;
use GPForum::Service::Operations::ApiRole;

our $VERSION = '0.001';

has dbh    => undef;    # optional: an administrative handle for embedding/tests
has config => sub { return GPForum::Config->from_environment; };

sub run ( $self, @arguments ) {
    return GPForum::Command::Usage->help( \*STDOUT, $self->usage_text )
      if GPForum::Command::Usage->wants_help(@arguments);
    my $options = _options(@arguments);
    return GPForum::Command::Usage->error( $options->{error},
        $self->usage_text )
      if $options->{error};
    try {
        my $service = GPForum::Service::Operations::ApiRole->new(
            dbh => $self->_admin_dbh );
        if ( $options->{apply} ) {
            my $result = $service->provision( $options->{role} );
            if ( $options->{json} ) {
                GPForum::Command::Usage->json(
                    \*STDOUT,
                    {
                        command => 'gpforum-api-role',
                        mode    => 'apply',
                        status  => 'ok',
                        %{$result}
                    }
                );
            }
            else {
                print
"provisioned $result->{role} with $result->{functions} API functions\n"
                  or croak 'failed to write API role result';
            }
        }
        else {
            my $statements = $service->plan( $options->{role} );
            if ( $options->{json} ) {
                GPForum::Command::Usage->json(
                    \*STDOUT,
                    {
                        command    => 'gpforum-api-role',
                        mode       => 'plan',
                        status     => 'ok',
                        role       => $options->{role},
                        statements => $statements
                    }
                );
            }
            else {
                print join( ";\n", @{$statements} ) . ";\n"
                  or croak 'failed to write API role plan';
            }
        }
    }
    catch ($error) { return GPForum::Command::Usage->failure($error); };
    return 0;
}

sub _admin_dbh ($self) {
    return $self->dbh if $self->dbh;
    my $config = $self->config;
    croak
'API role provisioning requires GPFORUM_ADMIN_DATABASE_USER; the runtime login is not used'
      if !defined $config->admin_database_user
      || !length $config->admin_database_user;
    my $dbh = DBI->connect(
        $config->admin_database_dsn // $config->database_dsn,
        $config->admin_database_user,
        $config->admin_database_password // q{},
        {
            AutoCommit     => 1,
            RaiseError     => 1,
            PrintError     => 0,
            pg_enable_utf8 => 1
        }
    );
    return $dbh;
}

const my %SWITCH => (
    '--apply' => { apply => 1 },
    '--plan'  => { apply => 0 },
    '--json'  => { json  => 1 },
);

sub _options (@arguments) {
    my %options;
    while (@arguments) {
        my $argument = shift @arguments;
        if ( $argument eq '--role' ) {
            $options{role} = shift @arguments;
            return { error => '--role needs a PostgreSQL role name' }
              if !defined $options{role} || !length $options{role};
            next;
        }
        return { error => "unknown option $argument" }
          if !exists $SWITCH{$argument};
        %options = ( %options, %{ $SWITCH{$argument} } );
    }
    return { error => '--role is required' } if !defined $options{role};
    return \%options;
}

sub usage_text ($self) {
    return <<'USAGE';
Usage: bin/gpforum-api-role --role ROLE [--plan|--apply] [--json]

Plans by default; --apply provisions access to the catalogued API functions.
The role must already exist, own no objects, inherit no roles and have no
administrative attributes. Function owners must be ordinary migration roles.
Uses GPFORUM_ADMIN_DATABASE_USER and GPFORUM_ADMIN_DATABASE_PASSWORD, with
GPFORUM_ADMIN_DATABASE_DSN or the configured database DSN. Keep administrator
credentials in a separate environment file, outside web and worker services.
Run migrations first, then provision again after each catalogue change.

Exit status: 0 success, 1 failure, 2 usage error.
USAGE
}

1;

__END__

=head1 NAME

GPForum::Command::ApiRole - Plan or provision the application's function-only PostgreSQL role.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    bin/gpforum-api-role --role gpforum_runtime --plan
    bin/gpforum-api-role --role gpforum_runtime --apply

=head1 DESCRIPTION

Uses a separate administrator connection. Provisioning refuses an owner or
privileged runtime role and administrative owners of security-definer API
functions. It grants only the versioned signatures the application calls.

=head1 SUBROUTINES/METHODS

=head2 run

Takes C<--role>, C<--plan> (the default), C<--apply> and C<--json>.

=head2 usage_text

The command's help text.

=head1 DIAGNOSTICS

Missing administrative credentials fail before connecting. Provisioning
errors roll back the role's grants.

=head1 CONFIGURATION AND ENVIRONMENT

C<GPFORUM_ADMIN_DATABASE_DSN>, C<GPFORUM_ADMIN_DATABASE_USER> and
C<GPFORUM_ADMIN_DATABASE_PASSWORD> are separate from runtime credentials.

=head1 DEPENDENCIES

L<DBI>, L<GPForum::Config>, L<GPForum::Service::Operations::ApiRole>.

=head1 INCOMPATIBILITIES

Requires PostgreSQL.

=head1 BUGS AND LIMITATIONS

The operator creates the login role and supplies its authentication first.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
