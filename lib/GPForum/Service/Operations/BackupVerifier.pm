# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Operations::BackupVerifier;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;
use DBI;
use Crypt::URandom qw(urandom);
use GPForum::X::Check;

our $VERSION = '0.001';

const my $DATABASE_NAME_RANDOM_BYTES => 12;
__PACKAGE__->requires(qw(config tools));

# The counts and pg_dump must see the SAME snapshot. Counting the live
# source after dumping creates false failures on a forum receiving replies.
sub run ( $self, $dump ) {
    my $dsn    = $self->config->database_dsn;
    my $source = $self->_connect($dsn);
    my $name   = 'gpforum_verify_' . unpack 'H*',
      urandom($DATABASE_NAME_RANDOM_BYTES);
    my $quoted = $source->quote_identifier($name);
    my ( $target, $created, $result, $failure );
    try {
        $source->do("CREATE DATABASE $quoted TEMPLATE template0");
        $created = 1;
        $source->begin_work;
        $source->do(
            'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY');
        my ($snapshot) =
          $source->selectrow_array('SELECT pg_export_snapshot()');
        my $before = _counts($source);
        $self->tools->dump_database( $dsn, $dump, $snapshot );
        $source->rollback;
        my $target_dsn = $self->tools->rewrite_dsn( $dsn, $name );
        $self->tools->restore_database( $target_dsn, $dump );
        $target = $self->_connect($target_dsn);
        my $after = _counts($target);

        for my $table ( sort keys %{$before} ) {
            if ( $before->{$table} != $after->{$table} ) {
                GPForum::X::Check->throw(
                    message => "backup restore mismatch: $table" );
            }
        }
        $result = {
            status          => 'verified',
            source_counts   => $before,
            restored_counts => $after
        };
    }
    catch ($error) { $failure = $error; };

    # Cleanup is attempted after restore errors, count mismatches and success.
    try {
        if ($target)                  { $target->disconnect; }
        if ( !$source->{AutoCommit} ) { $source->rollback; }
        if ($created) { $source->do("DROP DATABASE $quoted WITH (FORCE)"); }
    }
    catch ($error) {
        $failure =
          defined $failure ? "$failure; cleanup failed: $error" : $error;
    };
    $source->disconnect;
    die $failure if defined $failure;    ## no critic (ErrorHandling::RequireCarping) -- preserves the restore or cleanup failure
    $result->{temporary_database_removed} = 1;
    return $result;
}

sub _connect ( $self, $dsn ) {
    return DBI->connect(
        $dsn,
        $self->config->database_user,
        $self->config->database_password,
        { AutoCommit => 1, RaiseError => 1, PrintError => 0 }
    );
}

sub _counts ($dbh) {
    return { map { $_ => 0 + $dbh->selectrow_array("SELECT count(*) FROM $_") }
          qw(users threads posts post_bodies post_signatures schema_versions) };
}

1;

__END__

=head1 NAME

GPForum::Service::Operations::BackupVerifier - Restore and count a consistent backup.

=head1 DESCRIPTION

C<run($dump)> exports a repeatable-read source snapshot, counts users,
threads, posts, post bodies and migrations, and dumps that same snapshot.
It restores with pg_restore's exit-on-error into a randomly named database
on the same server, compares all counts, and drops the temporary database
on success or failure. The configured database role needs CREATEDB.
The result is recorded in the backup manifest only after cleanup succeeds.

=head1 SUBROUTINES/METHODS

=head2 run

Dumps one exported source snapshot, restores it into a temporary database, compares row counts, drops the database and returns evidence.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $evidence = $verifier->run($dump_path);

=head1 DIAGNOSTICS

Restore errors, mismatches and cleanup failures propagate and prevent a verified manifest.

=head1 CONFIGURATION AND ENVIRONMENT

Inject database configuration and PgTools. The role needs CREATEDB.

=head1 DEPENDENCIES

DBI, Crypt::URandom and the configured pg_dump and pg_restore clients.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Checks database row counts. Attachment archives are checked separately by Backup.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
