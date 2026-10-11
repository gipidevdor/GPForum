# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Operations::ApiRole;

use Carp qw(croak);
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::SqlFunctionCatalogue;

our $VERSION = '0.001';

__PACKAGE__->requires('dbh');
has catalogue =>
  sub { return GPForum::Infrastructure::SqlFunctionCatalogue->new; };

# Provisioning is administrative SQL, outside the application's function
# boundary. This only prepares a separate role; it never switches a running
# application's credentials while unmigrated areas still need table access.
sub provision ( $self, $role ) {
    my $dbh = $self->dbh;
    croak 'API role provisioning needs an autocommit connection'
      if !$dbh->{AutoCommit};
    my $statements = $self->plan($role);
    $dbh->begin_work;
    try {
        $self->_check_role($role);
        $self->_check_functions;
        for my $statement ( @{$statements} ) {
            $dbh->do($statement);
        }
        $self->_check_access($role);
        $dbh->commit;
    }
    catch ($error) {
        $dbh->rollback;
        croak $error;
    };

    return { functions => scalar @{ $self->catalogue->names }, role => $role };
}

# Quote identifiers with DBI, and grant individual versioned signatures.
# A new function receives no rights until the operator provisions again.
sub plan ( $self, $role ) {
    croak 'a runtime role is required' if !defined $role || !length $role;
    my $dbh             = $self->dbh;
    my $name            = $dbh->quote_identifier($role);
    my ($database)      = $dbh->selectrow_array('SELECT current_database()');
    my $quoted_database = $dbh->quote_identifier($database);
    my @statements      = (
        "REVOKE ALL ON DATABASE $quoted_database FROM $name",
        "REVOKE TEMPORARY ON DATABASE $quoted_database FROM PUBLIC",
        "GRANT CONNECT ON DATABASE $quoted_database TO $name",
        "REVOKE ALL ON SCHEMA public, api FROM $name",
        'REVOKE CREATE ON SCHEMA public FROM PUBLIC',
        "REVOKE ALL ON ALL TABLES IN SCHEMA public FROM $name, PUBLIC",
        "REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM $name, PUBLIC",
        "REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public, api FROM $name, PUBLIC",
        "GRANT USAGE ON SCHEMA api TO $name",
    );
    for my $operation ( @{ $self->catalogue->names } ) {
        my $entry = $self->catalogue->function($operation);
        push @statements,
          'GRANT EXECUTE ON FUNCTION ' . _signature($entry) . " TO $name";
    }

    return \@statements;
}

sub _check_role ( $self, $role ) {
    my $dbh   = $self->dbh;
    my $found = $dbh->selectrow_hashref(
        'SELECT oid, rolsuper, rolcreatedb, rolcreaterole, rolreplication, '
          . 'rolbypassrls FROM pg_catalog.pg_roles WHERE rolname = ?',
        undef, $role,
    );
    croak "runtime role $role does not exist" if !$found;
    for my $attribute (
        qw(rolsuper rolcreatedb rolcreaterole rolreplication rolbypassrls))
    {
        croak "runtime role $role has administrative rights"
          if $found->{$attribute};
    }
    my ($member) = $dbh->selectrow_array(
'SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members WHERE member = ?)',
        undef, $found->{oid},
    );
    croak "runtime role $role must not be a member of another role" if $member;
    my ($owns) = $dbh->selectrow_array(
        'SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_shdepend '
          . 'WHERE refclassid = \'pg_catalog.pg_authid\'::regclass '
          . 'AND refobjid = ? AND deptype = \'o\')',
        undef, $found->{oid},
    );
    croak "runtime role $role owns database objects" if $owns;

    return;
}

sub _check_functions ($self) {
    for my $operation ( @{ $self->catalogue->names } ) {
        my $entry    = $self->catalogue->function($operation);
        my $function = $self->dbh->selectrow_hashref(
            'SELECT p.prosecdef, p.proconfig, r.rolsuper, r.rolbypassrls '
              . 'FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r '
              . 'ON r.oid = p.proowner WHERE p.oid = pg_catalog.to_regprocedure(?)',
            undef, _signature($entry),
        );
        croak "$entry->{function} is not a restricted API boundary"
          if !$function || !$function->{prosecdef};
        croak "$entry->{function} has an administrative owner"
          if $function->{rolsuper} || $function->{rolbypassrls};
        my %settings =
          map { split /=/msx, $_, 2 } @{ $function->{proconfig} // [] };
        croak "$entry->{function} has an unsafe search_path"
          if ( $settings{search_path} // q{} ) ne 'pg_catalog, pg_temp';
    }

    return;
}

sub _check_access ( $self, $role ) {
    my ($unsafe) = $self->dbh->selectrow_array(
        'SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_class c '
          . 'JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace '
          . 'WHERE n.nspname IN (\'public\', \'api\') '
          . 'AND c.relkind IN (\'r\', \'p\', \'v\', \'m\', \'f\') '
          . 'AND (pg_catalog.has_table_privilege(?, c.oid, '
          . '\'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER\') '
          . 'OR pg_catalog.has_any_column_privilege(?, c.oid, \'SELECT,INSERT,UPDATE,REFERENCES\')))',
        undef, $role, $role,
    );
    croak "runtime role $role still has table access" if $unsafe;

    return;
}

sub _signature ($entry) {
    return $entry->{function} . '(' . join( q{, }, @{ $entry->{types} } ) . ')';
}

1;

__END__

=head1 NAME

GPForum::Service::Operations::ApiRole - Provision a separate runtime role with access to versioned API functions.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $roles = GPForum::Service::Operations::ApiRole->new(dbh => $admin);
    my $statements = $roles->plan('gpforum_runtime');
    $roles->provision('gpforum_runtime');

=head1 DESCRIPTION

Administrative provisioning for a dedicated forum database. The runtime role
must already exist, own no objects, hold no administrative attributes and
belong to no other role (membership permits SET ROLE even with NOINHERIT).
Only the catalogue's hardened SECURITY DEFINER entry points are granted;
their owners must not be superusers or bypass row security. Direct table,
sequence and helper-function access is revoked, as is temporary-table
creation inherited from PUBLIC. Existing application credentials are not
changed: they can switch only after every runtime area uses the API.

=head1 SUBROUTINES/METHODS

=head2 plan

Returns the quoted provisioning statements. Does not execute them.

=head2 provision

Validates the role and entry points, applies the grants in a transaction,
verifies table access is denied and returns C<role> and C<functions>.

=head1 DIAGNOSTICS

Unsafe roles or functions are refused before any grants change. Database
errors roll back the entire provisioning transaction.

=head1 CONFIGURATION AND ENVIRONMENT

Requires an administrative DBI connection in autocommit mode.

=head1 DEPENDENCIES

L<GPForum::Base>, L<GPForum::Infrastructure::SqlFunctionCatalogue>.

=head1 INCOMPATIBILITIES

Revoking PUBLIC privileges affects this dedicated database's other roles.

=head1 BUGS AND LIMITATIONS

Does not create logins or switch the application's credentials. Re-run after
deploying a catalogue version. PostgreSQL still accepts session commands and
SQL expressions that do not access application tables.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
