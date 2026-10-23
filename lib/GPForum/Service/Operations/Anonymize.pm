# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Operations::Anonymize;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;

use Carp           qw(croak);
use Crypt::URandom qw(urandom);
use DBI;
use File::Temp qw(tempdir);
use GPForum::Service::Operations::StagingDrill::PgTools;

our $VERSION = '0.001';

const my $SALT_BYTES => 32;
__PACKAGE__->requires('config');

# Only the relational forum shape survives. Queues, logs, sessions, tokens,
# credentials, private messages and attachment metadata are deliberately empty.
my %KEEP = map { $_ => 1 } qw(users spaces categories threads posts post_bodies
  post_revisions search_documents thread_counters post_replies thread_read_state schema_versions
  partition_registry endpoint_query_budgets);
my %TEXT = (
    users => {
        map { $_ => 1 }
          qw(username display_name email_normalized password_hash
          status preferred_locale preferred_theme preferred_timezone bio)
    },
    spaces     => { map { $_ => 1 } qw(slug title description visibility) },
    categories => { map { $_ => 1 } qw(slug title description visibility) },
    threads => { map { $_ => 1 } qw(title slug visibility moderation_state) },
    posts   => { map { $_ => 1 } qw(visibility moderation_state) },
    post_bodies => {
        map { $_ => 1 }
          qw(body_format body_source body_rendered_safe source_hash)
    },
    schema_versions =>
      { map { $_ => 1 } qw(version description checksum applied_by) },
    endpoint_query_budgets => { map { $_ => 1 } qw(endpoint_name notes) },
    partition_registry     =>
      { map { $_ => 1 } qw(table_name partition_name state) },
    search_documents => {
        map { $_ => 1 }
          qw(entity_type permission_scope language title body visibility)
    },
    post_revisions => { edit_reason => 1 },
);

sub run ( $self, $target ) {
    croak
'copy name must start with gpforum_anon_ and contain only lowercase letters, digits and underscores'
      if $target !~ /\Agpforum_anon_[[:lower:][:digit:]_]{1,40}\z/msx;
    my $config   = $self->config;
    my $dsn      = $config->admin_database_dsn  // $config->database_dsn;
    my $user     = $config->admin_database_user // $config->database_user;
    my $password = $config->admin_database_password
      // $config->database_password;
    my $tools = GPForum::Service::Operations::StagingDrill::PgTools->find;
    $tools->user($user)->password($password);
    my $source = $tools->parse_dsn( $config->database_dsn )->{dbname};
    croak 'copy and source databases must differ' if $source eq $target;
    my $admin = DBI->connect( $dsn, $user, $password,
        { RaiseError => 1, PrintError => 0, AutoCommit => 1 } );
    my $target_dsn = $tools->rewrite_dsn( $dsn, $target );

    # CREATE DATABASE refuses an existing name. Never overwrite a database.
    $admin->do( 'CREATE DATABASE '
          . $admin->quote_identifier($target)
          . ' TEMPLATE template0' );
    my $copy;
    try {
        $admin->do( 'REVOKE CONNECT ON DATABASE '
              . $admin->quote_identifier($target)
              . ' FROM PUBLIC' );
        my $directory =
          tempdir( 'gpforum-anonymize-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
        my $dump = "$directory/source.dump";
        $tools->dump_database( $tools->rewrite_dsn( $dsn, $source ), $dump );
        $tools->restore_database( $target_dsn, $dump );
        unlink $dump or croak 'cannot remove source dump';
        $copy = DBI->connect( $target_dsn, $user, $password,
            { RaiseError => 1, PrintError => 0, AutoCommit => 1 } );
        $self->_scrub($copy);
        $copy->do('VACUUM FULL ANALYZE');
        $copy->disconnect;
    }
    catch ($error) {
        if ($copy) { $copy->disconnect; }
        $admin->do( 'DROP DATABASE '
              . $admin->quote_identifier($target)
              . ' WITH (FORCE)' );
        croak 'staging copy failed; the incomplete copy was dropped';
    };
    $admin->disconnect;
    return {
        database           => $target,
        attachments_copied => false,
        accounts_can_login => false,
        status             => 'ok'
    };
}

sub _scrub ( $self, $dbh ) {
    my $salt        = unpack 'H*', urandom($SALT_BYTES);
    my $quoted_salt = $dbh->quote($salt);
    my $tables      = $dbh->selectall_arrayref(<<'SQL');
        SELECT n.nspname, c.relname FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind IN ('r','p') AND NOT c.relispartition
          AND n.nspname NOT IN ('pg_catalog','information_schema')
          AND n.nspname NOT LIKE 'pg_%'
SQL
    $dbh->begin_work;
    try {
        # Requires a superuser: constraints are checked explicitly after all
        # UUIDs have been remapped together. Triggers must not log old values.
        $dbh->do('SET LOCAL session_replication_role = replica');
        my @clear = map { $dbh->quote_identifier( @{$_} ) }
          grep { $_->[0] ne 'public' || !$KEEP{ $_->[1] } } @{$tables};
        if (@clear) { $dbh->do( 'TRUNCATE ' . ( join q{, }, @clear ) ); }
        for my $table ( grep { $_->[0] eq 'public' && $KEEP{ $_->[1] } }
            @{$tables} )
        {
            $self->_scrub_table( $dbh, $table->[1], $quoted_salt );
        }
        $dbh->do(
q{UPDATE public.search_documents SET search_vector = to_tsvector('simple'::regconfig, title || ' ' || body)}
        );
        $dbh->do('SET LOCAL session_replication_role = origin');
        my $foreign = $dbh->selectall_arrayref(<<'SQL');
            SELECT c.conrelid::regclass::text, c.conname, pg_get_constraintdef(c.oid)
            FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
            WHERE c.contype = 'f' AND n.nspname = 'public'
SQL
        for my $constraint ( @{$foreign} ) {
            my ( $table, $name, $definition ) = @{$constraint};
            next if !$KEEP{ $table =~ s/^public[.]//rmsx };
            my $quoted = $dbh->quote_identifier($name);
            $dbh->do("ALTER TABLE $table DROP CONSTRAINT $quoted");
            $dbh->do("ALTER TABLE $table ADD CONSTRAINT $quoted $definition");
        }
        $dbh->commit;
    }
    catch ($error) {
        $dbh->rollback;
        die $error;    ## no critic (ErrorHandling::RequireCarping) -- preserve the database exception after rollback
    };
    return;
}

my %SAFE_COLUMN = map { $_ => 1 }
  qw(visibility moderation_state status preferred_locale preferred_theme body_format entity_type version checksum endpoint_name table_name partition_name state);
my %STRUCTURAL_TYPE = map { $_ => 1 } qw(bool int4 int8 timestamptz);
my %TRANSFORM       = (
    email_normalized => sub ( $column, $salt ) {
        return "md5($salt || $column) || '\@example.invalid'";
    },
    password_hash      => sub { return q{'!disabled-staging-copy'}; },
    preferred_timezone => sub { return q{'UTC'}; },
    applied_by         => sub { return q{'staging'}; },
    display_name       => sub {
        return
q{(ARRAY['Ada','Linus','Grace','Edsger','Margaret','Ken','Barbara','Alan'])[1 + get_byte(decode(md5(id::text), 'hex'),0) % 8]};
    },
    username =>
      sub ( $column, $salt ) { return "'member_' || md5($salt || id::text)"; },
    slug =>
      sub ( $column, $salt ) { return "'item-' || md5($salt || $column)"; },
    language    => sub { return q{'simple'}; },
    source_hash => sub {
        my $body = _filler('body_source');
        return "encode(sha256(convert_to($body, 'UTF8')), 'hex')";
    },
);

sub _scrub_table ( $self, $dbh, $table, $salt ) {
    my $columns = $dbh->selectall_arrayref( <<'SQL', undef, $table );
SELECT column_name, udt_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = ? AND is_generated = 'NEVER'
SQL
    my @assignments;
    for my $column ( @{$columns} ) {
        my ( $name, $type ) = @{$column};
        my $quoted = $dbh->quote_identifier($name);
        if ( $type eq 'uuid' ) {
            push @assignments, "$quoted = md5($salt || $quoted\::text)::uuid";
        }
        elsif ( $type eq 'text' ) {
            croak "unclassified staging column $table.$name"
              if !$TEXT{$table}{$name};
            next
              if $SAFE_COLUMN{$name}
              || ( $table eq 'schema_versions' && $name eq 'description' );
            my $value =
                $TRANSFORM{$name}
              ? $TRANSFORM{$name}->( $quoted, $salt )
              : _filler($quoted);
            push @assignments,
              "$quoted = CASE WHEN $quoted IS NULL THEN NULL ELSE $value END";
        }
        elsif ( !_structural_column( $table, $name, $type ) ) {
            croak "unclassified staging column $table.$name";
        }
    }
    if (@assignments) {
        $dbh->do( 'UPDATE '
              . $dbh->quote_identifier( 'public', $table ) . ' SET '
              . ( join q{, }, @assignments ) );
    }
    return;
}

sub _structural_column ( $table, $name, $type ) {
    return $STRUCTURAL_TYPE{$type}
      || ( $type eq 'tsvector'
        && $table eq 'search_documents'
        && $name eq 'search_vector' );
}

sub _filler ($column) {
    my $width = length 'Lorem ipsum dolor sit amet. ';
    return
"left(repeat('Lorem ipsum dolor sit amet. ', (char_length($column) / $width + 1)), char_length($column))";
}

1;

__END__

=head1 NAME

GPForum::Service::Operations::Anonymize - Create a scrubbed staging copy.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Operations::Anonymize->new(...);

=head1 DESCRIPTION

Create a scrubbed staging copy. See ADR 0155.

=head1 SUBROUTINES/METHODS

=head2 run

Takes a new gpforum_anon_ database name. Dumps the source through administrative credentials, restores a new copy, removes sensitive content and credentials, validates foreign keys and vacuums. An existing target is refused. Failure removes the incomplete copy. See ADR 0155 for retained shape and limits.

=head1 DIAGNOSTICS

Exceptions propagate to the command or worker, which reports the failure.

=head1 CONFIGURATION AND ENVIRONMENT

Receives configuration or collaborators through constructor arguments. See
ADR 0155 for the operator settings and commands.

=head1 DEPENDENCIES

Uses the modules listed in the source preamble and the locked cpanfile.

=head1 INCOMPATIBILITIES

Requires Perl 5.40 or newer.

=head1 BUGS AND LIMITATIONS

See ADR 0155 for the scope and operational limits.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
