# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Migration::Runner;

use Carp qw(croak);
use Const::Fast;
use Digest::SHA qw(sha256_hex);
use List::Util  qw(max);
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Mojo::File  qw(path);
use Time::HiRes qw(time);

use GPForum::Migration::Plan;
use GPForum::X::Argument;
use GPForum::X::Check;

our $VERSION = '0.001';

const my $MILLISECONDS => 1_000;

# One fixed key for the whole migration surface. Session-level, not
# transaction-level: the migration files open and commit their own
# transactions, so a transaction-scoped lock would be released by the first
# COMMIT and leave the rest of the run unprotected. Each file's transaction
# carries its own record (_with_records), so a migration and the row that
# says it ran commit together.
const my $MIGRATION_LOCK_KEY => 4_021_970_001;

# A migration whose first line is this marker runs outside a transaction, one
# statement at a time. CREATE INDEX CONCURRENTLY needs that: PostgreSQL refuses
# it inside a transaction block, and a file sent whole is one, so every index
# so far was built under a lock that stopped writes to its table. Such a file
# holds plain statements, each ending with a semicolon at the end of a line,
# and each safe to run again: a failure part-way leaves the earlier ones
# applied and the migration unrecorded, so the next run repeats them.
const my $NO_TRANSACTION => qr{\A -- [ ] gpforum:no-transaction \b}msx;
const my $DOLLAR_QUOTE   => qr{[\$][\$]}msx;

# The lines that open and close a transaction in a migration file. A
# PL/pgSQL block's BEGIN has no semicolon, so it is not one.
const my $OPENS  => qr{^ [ \t]* BEGIN [ \t]* ; [ \t]* $}imsx;
const my $CLOSES => qr{^ [ \t]* COMMIT [ \t]* ; [ \t]* $}imsx;

# A statement that opens or ends a transaction, wherever it stands, and a
# dollar-quoted body, whose words are not statements of the file.
const my $CONTROL_WORD =>
  qr{BEGIN|START [ \t]+ TRANSACTION|COMMIT|ROLLBACK|ABORT}imsx;
const my $TRANSACTION_CONTROL => qr{\b ($CONTROL_WORD) [ \t]* ;}imsx;
const my $DOLLAR_BODY         => qr{([\$] \w* [\$]) .*? \1}msx;

# What a migration that has its schema_versions row written in its own
# transaction reads its time from: the statement the whole file is sent in.
const my $ELAPSED_MS => '(extract(epoch FROM clock_timestamp()'
  . ' - statement_timestamp()) * 1000)::integer';

# The files written before a migration had to be one transaction, each of
# whose transactions is safe to run again (their comments say why): they run
# as they are, and are recorded after. A new file that needs more than one
# transaction is a no-transaction migration of repeatable statements.
const my %SEVERAL_TRANSACTIONS => map { $_ => 1 } qw(049 051);

# The versions the history leaves free for a migration that lands after
# higher ones were applied: 120 was held for a fix written alongside 121 and
# after. Any other version below an applied one is a migration that missed
# its turn, and a database that ran the later ones without it.
const my %LATE_ARRIVALS => map { $_ => 1 } qw(120);

# pg_ping's answer for a connection inside a transaction block, or one that
# failed.
const my $IN_TRANSACTION => 3;

__PACKAGE__->requires(qw(schema));
has plan       => sub { return GPForum::Migration::Plan->new; };
has applied_by => sub { return $ENV{USER} || 'gpforum'; };

sub pending ($self) {
    my $applied = $self->applied_versions;

    return [ grep { !exists $applied->{ $_->{version} } }
          @{ $self->plan->summary } ];
}

sub applied_versions ($self) {
    my $rows = $self->_select_leniently('SELECT version FROM schema_versions');

    return {} if !$rows;

    my %applied = map { $_->{version} => 1 } @{$rows};

    return \%applied;
}

# Two hosts deploying at once used to run the same migration twice, because
# nothing serialised them: each read an empty schema_versions and proceeded.
# The lock is held across the whole run, not per migration, so a second host
# waits for the first to finish rather than interleaving with it.
sub apply_pending ($self) {
    my $locked = $self->_lock;
    my @applied;
    my $failure;
    try {
        $self->verify_applied;
        $self->verify_order;
        for my $migration ( @{ $self->pending } ) {
            push @applied, $self->apply_migration($migration);
        }
    }
    catch ($error) {
        $failure = $error;
        $self->_roll_back;
    };
    if ($locked) {
        $self->_unlock;
    }
    if ( defined $failure ) {
        croak $failure;
    }

    return \@applied;
}

# A checksum nobody compares is a comment. An applied migration whose file has
# changed since means the database and the tree disagree about what was run,
# which is exactly the state a checksum column exists to detect.
sub verify_applied ($self) {
    my $recorded = $self->recorded_checksums;
    if ( !%{$recorded} ) {
        return [];
    }

    my @drifted;
    for my $migration ( @{ $self->plan->summary } ) {
        my $stored = $recorded->{ $migration->{version} };
        next if !defined $stored;
        my $current = sha256_hex( path( $migration->{file} )->slurp );
        next if $current eq $stored;
        push @drifted,
          {
            version  => $migration->{version},
            recorded => $stored,
            current  => $current,
          };
    }

    if (@drifted) {
        GPForum::X::Check->throw(
            message => 'migration files changed after they were applied: '
              . join ', ',
            map { "$_->{version}" } @drifted
        );
    }

    return \@drifted;
}

# Migrations run in the order of their numbers. One numbered below a version
# already applied was not there when the later ones ran -- a branch that
# landed late, a file renumbered -- and running it now applies the history in
# an order nobody tested. It is refused, unless its number is a gap the
# history lists as left for it.
sub verify_order ($self) {
    my @applied =
      grep { /\A [[:digit:]]+ \z/msx } keys %{ $self->applied_versions };
    return [] if !@applied;

    my $newest = max @applied;
    my @late   = grep {
        $_->{version} < $newest && !exists $LATE_ARRIVALS{ $_->{version} }
    } @{ $self->pending };
    if (@late) {
        my $versions = join q{, }, map { $_->{version} } @late;
        GPForum::X::Check->throw( message =>
"migrations numbered below one already applied ($newest) are pending: $versions"
        );
    }

    return \@late;
}

sub recorded_checksums ($self) {
    my $rows =
      $self->_select_leniently('SELECT version, checksum FROM schema_versions');

    return {} if !$rows;

    return { map { $_->{version} => $_->{checksum} } @{$rows} };
}

# A database without schema_versions yet -- or none to be reached -- reads as
# one where nothing was applied: the rows, or undef.
sub _select_leniently ( $self, $sql ) {
    my $rows;
    try {
        $rows = $self->_dbh->selectall_arrayref( $sql, { Slice => {} } );
    }
    catch ($error) {
        $rows = undef;
    };

    return $rows;
}

sub _lock ($self) {
    my $dbh = $self->_dbh;
    if ( !$dbh || !$dbh->can('selectrow_array') ) {
        return 0;
    }

    return $self->_advisory( $dbh, 'pg_advisory_lock' );
}

sub _unlock ($self) {
    my $dbh = $self->_dbh;
    if ( !$dbh || !$dbh->can('selectrow_array') ) {
        return 0;
    }

    return $self->_advisory( $dbh, 'pg_advisory_unlock' );
}

# 1 when the advisory lock call ran, 0 when it died.
sub _advisory ( $self, $dbh, $function ) {
    my $done = 0;
    try {
        $dbh->selectrow_array( "SELECT $function(?)",
            undef, $MIGRATION_LOCK_KEY );
        $done = 1;
    }
    catch ($error) {
        $done = 0;
    };

    return $done;
}

sub apply_migration ( $self, $migration ) {
    my $sql      = path( $migration->{file} )->slurp;
    my $checksum = sha256_hex($sql);
    my $started  = time;
    my $recorded = 0;

    if ( $sql =~ $NO_TRANSACTION ) {
        $self->_execute_each( $migration, $sql );
    }
    elsif ( my $atomic = $self->_with_records( $migration, $sql, $checksum ) ) {
        $self->_execute($atomic);
        $recorded = 1;
    }
    else {
        $self->_execute($sql);
    }

    my $elapsed_ms = int( ( time - $started ) * $MILLISECONDS );

    if ( !$recorded ) {
        $self->_record_schema_version( $migration, $checksum );
        $self->_record_migration_safety( $migration, $checksum, $elapsed_ms );
    }

    return {
        version           => $migration->{version},
        description       => $migration->{description},
        checksum          => $checksum,
        execution_time_ms => $elapsed_ms,
    };
}

# The file as it is sent, its records written inside its transaction: before
# its COMMIT when it is one transaction, in one opened around it when it has
# none. Undef for a listed file of several transactions, which is recorded
# after it runs; any other such file is refused before it runs.
sub _with_records ( $self, $migration, $sql, $checksum ) {
    my $code = join "\n", grep { !/\A \s* --/msx } split /\n/msx, $sql;
    $code =~ s/$DOLLAR_BODY//gmsx;
    my @control = $code =~ /$TRANSACTION_CONTROL/gmsx;
    my $records = $self->_records( $migration, $checksum );

    if ( !@control ) {
        return "BEGIN;\n$sql\n$records\nCOMMIT;\n";
    }
    if (   "@control" =~ /\A BEGIN [ ] COMMIT \z/imsx
        && $code =~ /\A \s* $OPENS/msx
        && $code =~ /$CLOSES \s* \z/msx )
    {
        my ( $body, $commit_line ) = $sql =~ /\A (.*) ($CLOSES .*) \z/msx;

        return "$body$records\n$commit_line";
    }
    return undef if exists $SEVERAL_TRANSACTIONS{ $migration->{version} };

    GPForum::X::Argument->throw( message =>
"migration $migration->{version} runs more than one transaction: write it as one, or as a no-transaction migration of statements safe to repeat"
    );
}

# The schema_versions row, and the migration_safety row once that table
# exists, as statements sent with the migration: its text holds no
# placeholders, so the values are written as quoted literals.
sub _records ( $self, $migration, $checksum ) {
    my ( $version, $description, $sum, $by ) =
      map { _literal($_) }
      ( @{$migration}{qw(version description)}, $checksum, $self->applied_by );
    my $records =
        'INSERT INTO schema_versions (version, description, checksum)'
      . " VALUES ($version, $description, $sum);";
    return $records if $migration->{version} lt '004';

    return
        "$records\n"
      . 'INSERT INTO migration_safety (version, checksum, applied_by,'
      . ' execution_time_ms, requires_lock, reversible, rollback_sql_hash)'
      . " VALUES ($version, $sum, $by, $ELAPSED_MS, false, false, '');";
}

sub _literal ($value) {
    return q{'} . ( $value =~ s/'/''/grmsx ) . q{'};
}

# A migration that failed inside its transaction leaves the connection in a
# failed transaction block, where the unlock and every later statement are
# refused: it is rolled back, so the lock is let go of.
sub _roll_back ($self) {
    my $dbh = $self->_dbh;
    return 0 if !$dbh || !$dbh->can('pg_ping') || !$dbh->{AutoCommit};

    my $done = 0;
    try {
        if ( $dbh->pg_ping >= $IN_TRANSACTION ) {
            $dbh->do('ROLLBACK');
        }
        $done = 1;
    }
    catch ($error) {
        $done = 0;
    };

    return $done;
}

sub _execute_each ( $self, $migration, $sql ) {
    my $dbh = $self->_dbh;
    if ( defined $dbh->{AutoCommit} && !$dbh->{AutoCommit} ) {
        GPForum::X::Argument->throw( message =>
"$migration->{version} runs outside a transaction, and one is open"
        );
    }

    for my $statement ( $self->statements($sql) ) {
        $self->_execute($statement);
    }

    return;
}

# The statements of a no-transaction migration: comment lines dropped, split
# at each semicolon that ends a line. A dollar-quoted body could hold such a
# semicolon, so it is refused rather than split wrongly.
sub statements ( $class, $sql ) {
    if ( $sql =~ $DOLLAR_QUOTE ) {
        GPForum::X::Argument->throw( message =>
              'a no-transaction migration holds plain statements: no $$ bodies'
        );
    }

    my $code = join "\n", grep { !/\A \s* --/msx } split /\n/msx, $sql;
    my @statements;
    for my $statement ( split /;[ \t]*$/msx, $code ) {
        $statement =~ s/\A \s+ | \s+ \z//gmsx;
        if ( length $statement ) {
            push @statements, $statement;
        }
    }

    return @statements;
}

sub _record_schema_version ( $self, $migration, $checksum ) {
    $self->_execute(
'INSERT INTO schema_versions (version, description, checksum) VALUES (?, ?, ?)',
        undef, $migration->{version}, $migration->{description}, $checksum
    );

    return;
}

sub _record_migration_safety ( $self, $migration, $checksum, $elapsed_ms ) {
    return if $migration->{version} lt '004';

    $self->_execute(
'INSERT INTO migration_safety (version, checksum, applied_by, execution_time_ms, requires_lock, reversible, rollback_sql_hash) VALUES (?, ?, ?, ?, ?, ?, ?)',
        undef,
        $migration->{version},
        $checksum,
        $self->applied_by,
        $elapsed_ms,
        0,
        0,
        q{}
    );

    return;
}

sub _dbh ($self) {
    return $self->schema->storage->dbh;
}

sub _execute ( $self, $statement, @arguments ) {
    my $dbh = $self->_dbh;

    if ( $dbh->can('execute_statement') ) {
        return $dbh->execute_statement( $statement, @arguments );
    }

    return $dbh->do( $statement, @arguments );
}

1;

__END__

=head1 NAME

GPForum::Migration::Runner - Applies GPForum SQL migrations.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $runner = GPForum::Migration::Runner->new(schema => $schema);
    my $applied = $runner->apply_pending;

=head1 DESCRIPTION

Discovers pending SQL migrations, applies them through DBI in the order of
their numbers, records checksums in C<schema_versions>, and records safety
metadata once C<migration_safety> exists.

=head1 SUBROUTINES/METHODS

=head2 pending

Returns migrations not yet recorded in C<schema_versions>.

=head2 applied_versions

Returns a hash reference of applied migration versions.

=head2 apply_pending

Applies every pending migration in order, under one advisory lock, after
L</verify_applied> and L</verify_order>. A failure inside a migration's
transaction is rolled back before the lock is let go of.

=head2 verify_applied

Throws L<GPForum::X::Check> when an applied migration's file has changed
since; returns an empty array reference otherwise.

=head2 verify_order

Throws L<GPForum::X::Check> when a pending migration is numbered below one
already applied, unless its number is a gap the history leaves for it (120);
returns an empty array reference otherwise.

=head2 recorded_checksums

The recorded checksum of each applied version, by version.

=head2 apply_migration

Applies a single migration hash returned by L<GPForum::Migration::Plan>.

=head2 statements

The statements of a no-transaction migration, split at each semicolon that
ends a line, comment lines dropped. Croaks on a dollar-quoted body.

=head1 A MIGRATION AND ITS RECORD COMMIT TOGETHER

A migration file is one transaction, C<BEGIN;> on its first line and
C<COMMIT;> on its last, or holds no transaction control at all. The runner
sends it whole with its C<schema_versions> row (and its C<migration_safety>
row) written before that C<COMMIT>, or in a transaction it opens around a
file that has none, so a migration is never applied without its record, nor
recorded without being applied. A file of several transactions is refused,
except 049 and 051, written before this rule: each of their transactions is
safe to run again, and they are recorded after them.

=head1 NO-TRANSACTION MIGRATIONS

A migration whose first line is C<-- gpforum:no-transaction> runs one
statement at a time, each in its own transaction, so it can build an index
with C<CREATE INDEX CONCURRENTLY> without stopping writes to the table. Each
statement must be safe to repeat: drop a half-built index first
(C<DROP INDEX CONCURRENTLY IF EXISTS>), because a failed concurrent build
leaves an invalid one behind. Such a migration is recorded after its last
statement: a failure before then leaves it unrecorded, and the next run
repeats every statement.

=head1 DIAGNOSTICS

Throws L<GPForum::X::Argument> when built without a schema, when a
no-transaction migration meets an open transaction and when its SQL holds a
dollar-quoted body, and when a new migration runs more than one transaction;
L<GPForum::X::Check> when applied migration files have changed since, and
when a migration numbered below an applied one is pending. DBI failures
propagate.

=head1 CONFIGURATION AND ENVIRONMENT

C<USER> is used as the default applied-by value.

=head1 DEPENDENCIES

Uses L<Digest::SHA>, L<Mojo::File>, L<Time::HiRes>,
L<GPForum::Migration::Plan>, L<GPForum::X::Argument> and L<GPForum::X::Check>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Fresh database discovery treats an unreadable C<schema_versions> table as no
applied migrations.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
