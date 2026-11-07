# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::SqlFunction;

use Carp qw(croak);
use Const::Fast;
use JSON::MaybeXS;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::AsyncQuery;
use GPForum::Infrastructure::PgTransaction;
use Mojo::Promise;
use Scalar::Util qw(weaken);
use GPForum::Infrastructure::SqlFunctionCatalogue;
use GPForum::X::Argument;
use GPForum::X::Conflict;

our $VERSION = '0.001';

const my $INVALID_PARAMETER => '22023';
const my $UNIQUE_VIOLATION  => '23505';

# What PostgreSQL answers a prepared statement whose result columns changed
# under it: a table a function RETURNS SETOF gained a column, and the plan
# was then invalidated (ADR 0126, section 2, amended 2026-10-22).
const my $FEATURE_NOT_SUPPORTED => '0A000';
const my $RESULT_TYPE_CHANGED =>
  qr/cached [ ] plan [ ] must [ ] not [ ] change [ ] result [ ] type/msx;

# A statement is prepared on the server when it is prepared, not at its
# second execution, as DBD::Pg does by default: its first execution was then
# unnamed, and a second one after such a migration came back with more
# columns than the handle had read the first time, and DBD::Pg 3.21 read
# past them and crashed the worker. Named from the start, it keeps the
# columns it was prepared with, or is refused as above. A plain hash, not a
# constant: DBD::Pg reads keys it does not hold.
my $PREPARED_NOW = { pg_prepare_now => 1 };
const my $POSTGRESQL_DSN => qr/\A dbi:Pg:/imsx;

# A uuid as PostgreSQL writes one and GPForum::Infrastructure::Id makes one.
const my $WRITTEN_UUID => GPForum::Infrastructure::Id->uuid_pattern;

# What a jsonb parameter given as a reference is written as, and what a json
# column is read with: the codec the json columns of GPForum::Schema use.
my $JSON = JSON::MaybeXS->new( canonical => 1, utf8 => 0 );

# One catalogue for the process, so each entry's statement is built once
# however many layers the requests make.
my $CATALOGUE = GPForum::Infrastructure::SqlFunctionCatalogue->new;

# The calls answered ahead while code runs under answering: each call's rows
# under its key, taken once. Every layer makes its own SqlFunction, so the
# answers are the process's, held only for the time of one answering.
my %ANSWERING = ( answers => undef );

__PACKAGE__->requires('schema');
has catalogue => sub { return $CATALOGUE; };
has async_database =>
  undef;    # optional: set only inside an owned promise transaction
has async_transaction =>
  undef;    # optional: the transaction's serialized query runner
has query_context => undef;    # optional: CLI callers have no request context

# The runtime schema owns Mojo::Pg. Every call joins its worker connection
# and transaction; in-memory service doubles keep their scripted answers.
sub for_schema ( $class, $schema ) {
    return undef if !blessed $schema || !$schema->isa('GPForum::Schema');

    my $info = $schema->storage->connect_info;
    if ( ref $info ne 'ARRAY' || !defined $info->[0] || ref $info->[0] ) {
        GPForum::X::Argument->throw(
            message => 'SQL function routing needs a configured database DSN' );
    }
    if ( $info->[0] !~ $POSTGRESQL_DSN ) {
        GPForum::X::Argument->throw(
            message => 'SQL function routing requires PostgreSQL' );
    }

    return $schema->{gp_sql_functions}
      if $schema->{gp_sql_functions}
      && ref( $schema->{gp_sql_functions} ) eq $class;
    my $functions = $class->new( schema => $schema );
    $schema->{gp_sql_functions} = $functions;
    weaken( $schema->{gp_sql_functions} );
    return $functions;
}

# The rows a function returns, as hashes keyed by its columns, its json
# columns decoded. The values are bound by the parameter names the catalogue
# gives, every one of them, each cast to its type in the statement.
sub rows ( $self, $name, $values ) {
    my $entry = $self->catalogue->function($name);
    my @bound = _bound( $entry, $values );
    return [] if _malformed_id( $entry, \@bound );

    my $rows = _answered( $entry, \@bound )
      // $self->_execute( $entry, \@bound );
    if ( %{ $entry->{json} } ) {
        _decode_json( $entry, $rows );
    }

    return $rows;
}

# A separate checked-out Mojo::Pg connection per in-flight operation.
# Existing transactional workflows keep rows(); promises never borrow their
# handle or retry an ambiguous write after a connection failure.
async sub rows_p ( $self, $name, $values, $context = undef ) {
    my $storage = $self->schema->storage;
    my $stats   = $storage->debug ? $storage->debugobj : undef;
    $context //= $self->query_context;
    if ($stats) { $context //= $stats->request_context; }
    my $entry = $self->catalogue->function($name);
    my @bound = _bound( $entry, $values );
    return [] if _malformed_id( $entry, \@bound );
    my @parameters = map {
        $entry->{types}[$_] eq 'bytea'
          ? { type => DBD::Pg::PG_BYTEA(), value => $bound[$_] }
          : $bound[$_]
    } 0 .. $#bound;
    if ( !@parameters ) {
        $entry      = { %{$entry}, sql => $entry->{sql} . ' WHERE ?::boolean' };
        @parameters = (1);
    }
    my $read = sub ($db) {
        return $self->_read_rows_p( $db, $entry, \@parameters, $stats,
            $context );
    };
    if ( $self->async_database ) {
        return await $self->async_transaction->query_p(
            sub {
                return $stats
                  ? $stats->in_context( $context,
                    sub { return $read->( $self->async_database ); } )
                  : $read->( $self->async_database );
            }
        );
    }
    return await GPForum::Infrastructure::AsyncQuery->for_schema(
        $self->schema )->run_p( $read, $context );
}

async sub _read_rows_p ( $self, $db, $entry, $parameters, $stats, $context ) {

    # Only the query needs to wait. Decode and finish its statistics in the
    # same completion instead of adding several event-loop turns per query.
    if ($stats) { $stats->query_start( $entry->{sql} ); }
    my ( $rows, $error );
    try {
        my $result = await $self->_query_p( $db, $entry, $parameters );
        $rows = $result->hashes->to_array;
        if ( %{ $entry->{json} } ) { _decode_json( $entry, $rows ); }
    }
    catch ($caught) { $error = $caught; };
    if ($stats) {
        $stats->in_context( $context, sub { $stats->query_end; return; } );
    }
    if ( defined $error ) {
        my $state = $db->dbh->state;

        # A refused standalone statement has already rolled itself back.
        # Transaction owners mark their lease only after a successful rollback.
        $db->{gp_reusable_after_error} = 1
          if !$self->async_transaction
          && defined $state
          && ( $state eq $INVALID_PARAMETER || $state eq $UNIQUE_VIOLATION );
        $self->_raise( $state, $error );
    }
    return $rows;
}

async sub row_p ( $self, $name, $values, $context = undef ) {
    my $rows = await $self->rows_p( $name, $values, $context );
    return $rows->[0];
}

sub transaction_p ( $self, $work, $context = undef, $readonly = 0 ) {
    $context //= $self->query_context;
    my $storage = $self->schema->storage;
    my $stats   = $storage->debug ? $storage->debugobj : undef;
    if ($stats) { $context //= $stats->request_context; }
    if ( $self->async_transaction ) {
        return $self->async_transaction->run_p( sub { return $work->($self); },
            $readonly );
    }
    return GPForum::Infrastructure::AsyncQuery->for_schema( $self->schema )
      ->run_p(
        sub ($db) {
            my $transaction = GPForum::Infrastructure::PgTransaction->new(
                database => $db,
                stats    => $stats,
                context  => $context,
            );
            my $scope = ref($self)->new(
                schema            => $self->schema,
                catalogue         => $self->catalogue,
                async_database    => $db,
                async_transaction => $transaction,
                query_context     => $context
            );
            return $transaction->run_p( sub { return $work->($scope); },
                $readonly );
        },
        $context
      );
}

sub _query_p ( $self, $db, $entry, $parameters, $attempt = 0 ) {
    return $db->query_p( $entry->{sql}, @{$parameters} )->catch(
        sub ($error) {
            my $state = $db->dbh->state;
            if (   _result_type_changed( $state, $error )
                && !$attempt
                && !$self->async_transaction
                && $db->dbh->{AutoCommit} )
            {
                return $self->_forget_p( $db, $entry->{sql} )->then(
                    sub {
                        return $self->_query_p( $db, $entry, $parameters, 1 );
                    }
                );
            }
            $self->_raise( $state, $error );
        }
    );
}

# Runs code with some of the calls it will make already answered: a page
# that knows which reads it makes reads them in one statement first
# (GPForum::Service::Forum::ThreadPageReads), and the layers that make each
# read take its rows from the answers instead of the database. An answer is
# a call's rows under answer_key, and is taken once: the same call again
# goes to the database. A call no answer names, and every call once the code
# has returned or died, goes to the database as before.
sub answering ( $class, $answers, $code ) {
    ## no critic (Variables::ProhibitLocalVars) -- held for the code's run alone, and given back when it dies
    local $ANSWERING{answers} = $answers;
    ## use critic

    return $code->();
}

# The key an answer is kept under: the function a call names and the values
# it binds, as rows binds them.
sub answer_key ( $self, $name, $values ) {
    my $entry = $self->catalogue->function($name);

    return _key( $entry, [ _bound( $entry, $values ) ] );
}

sub _answered ( $entry, $bound ) {
    my $answers = $ANSWERING{answers};
    return undef if !$answers || !%{$answers};

    return delete $answers->{ _key( $entry, $bound ) };
}

sub _key ( $entry, $bound ) {
    return join q{}, map { _key_part($_) } $entry->{function}, @{$bound};
}

# Text may contain either separator an unframed join would use. Each scalar
# carries its character count; arrays carry their element count and recurse.
# NULL, an empty array and an array containing empty text are distinct calls.
sub _key_part ($value) {
    return 'u' if !defined $value;
    if ( ref $value eq 'ARRAY' ) {
        return join q{}, 'a', scalar @{$value}, q{:}, map {
               !defined $_        ? 'u'
              : ref $_ eq 'ARRAY' ? _key_part($_)
              : 's'
              . length . q{:}
              . $_
        } @{$value};
    }

    return 's' . length($value) . q{:} . $value;
}

# The first row, or undef.
sub row ( $self, $name, $values ) {
    return $self->rows( $name, $values )->[0];
}

# The statement a call sends and its values, as rows binds them: for the
# query-plan evidence, which runs what the readers run.
sub statement ( $self, $name, $values ) {
    my $entry = $self->catalogue->function($name);

    return [ $entry->{sql}, _bound( $entry, $values ) ];
}

# The values in the order of the function's parameters. A parameter left out
# or one the function does not have is the caller's mistake: an undefined
# value is a NULL, a missing one is a typo.
sub _bound ( $entry, $values ) {
    my $given = $values // {};
    my @bound;
    for my $index ( 0 .. $#{ $entry->{names} } ) {
        my $parameter = $entry->{names}[$index];
        if ( !exists $given->{$parameter} ) {
            GPForum::X::Argument->throw( message =>
                  "$entry->{function} needs $parameter, which was not given" );
        }
        push @bound, _typed( $entry->{types}[$index], $given->{$parameter} );
    }
    if ( keys %{$given} != @{ $entry->{names} } ) {
        my %expected = map { $_ => 1 } @{ $entry->{names} };
        my $unknown  = join q{, },
          sort grep { !exists $expected{$_} } keys %{$given};
        GPForum::X::Argument->throw(
            message => "$entry->{function} has no $unknown" );
    }

    return @bound;
}

sub _typed ( $type, $value ) {
    return undef                 if !defined $value;
    return $value ? 1 : 0        if $type eq 'boolean';
    return $JSON->encode($value) if $type eq 'jsonb' && ref $value;

    return $value;
}

# A uuid parameter PostgreSQL would not read as one: it came from a URL, and
# PostgreSQL would refuse the whole statement, which a page answered as a
# 500 for a row that is not there. The call is not made and there are no
# rows, as Infrastructure::PreparedQuery does for its statements.
#
# The ids GPForum writes itself -- the database's, the generator's -- are in
# the one shape $WRITTEN_UUID matches, read at half the cost of every
# spelling PostgreSQL accepts; only another is held to those.
sub _malformed_id ( $entry, $bound ) {
    for my $index ( @{ $entry->{uuid_parameters} } ) {
        next if !defined $bound->[$index];
        for my $value (
            ref $bound->[$index] eq 'ARRAY'
            ? @{ $bound->[$index] }
            : $bound->[$index]
          )
        {
            next     if defined $value && $value =~ $WRITTEN_UUID;
            return 1 if !GPForum::Infrastructure::Id->is_uuid_spelling($value);
        }
    }

    return 0;
}

# Each fixed catalogue call is one statement in query budgets and timings.
# Mojo::Pg retains its prepared statement on the worker's connection.
sub _execute ( $self, $entry, $bound ) {
    my $storage = $self->schema->storage;
    my $stats   = $storage->debug ? $storage->debugobj : undef;
    my $callback =
      $storage->debug && $storage->can('debugcb') ? $storage->debugcb : undef;
    my @observed = ( $stats || $callback )
      ? map {
            $entry->{types}[$_] eq 'bytea' ? '[binary bytes]'
          : defined $bound->[$_]           ? $bound->[$_]
          : 'NULL'
      } 0 .. $#{$bound}
      : ();
    if ($callback) {
        $callback->(
            'SELECT', $entry->{sql} . ': ' . join( ', ', @observed ) . "\n"
        );
    }
    if ($stats) {
        $stats->query_start( $entry->{sql}, @observed );
    }
    my ( $rows, $failure );
    try {
        $rows = $self->_on_handle( $storage, $entry, $bound );
    }
    catch ($error) {
        $failure = $error;
    };
    if ($stats) {
        $stats->query_end( $entry->{sql}, @observed );
    }

    # Balance timing on errors too: an aborted call must not leave the next
    # call nested inside it, or hide all subsequent SQL time in this request.
    die $failure if defined $failure;    ## no critic (ErrorHandling::RequireCarping) -- rethrow the original SQL exception after ending its observation

    return $rows;
}

# Runtime calls use Mojo::Pg on the worker's retained connection. Scripted
# test handles retain the small dbh_do contract used by call-layer tests.
sub _on_handle ( $self, $storage, $entry, $bound ) {
    if ( $storage->isa('GPForum::Infrastructure::PgStorage') ) {
        return $self->_on_pg( $storage, $entry, $bound );
    }
    return $storage->dbh_do(
        sub ( $, $dbh ) { return $self->_fetch( $dbh, $entry, $bound ); } );
}

sub _on_pg ( $self, $storage, $entry, $bound, $attempt = 0 ) {
    my ( $rows, $failure, $state );
    my $db         = $storage->database;
    my @parameters = map {
        $entry->{types}[$_] eq 'bytea'
          ? { type => DBD::Pg::PG_BYTEA(), value => $bound->[$_] }
          : $bound->[$_]
    } 0 .. $#{$bound};
    try { $rows = $db->query( $entry->{sql}, @parameters )->hashes->to_array; }
    catch ($error) { $failure = $error; $state = $db->dbh->state; };
    return $rows if !defined $failure;
    if ( _result_type_changed( $state, $failure ) ) {
        _forget( $db->dbh, $entry->{sql} );
        return $self->_on_pg( $storage, $entry, $bound, 1 )
          if !$attempt && $db->dbh->{AutoCommit};
    }
    if (  !$attempt
        && $db->dbh->{AutoCommit}
        && !$storage->transaction_depth
        && !$storage->connected )
    {
        $storage->ensure_connected;
        return $self->_on_pg( $storage, $entry, $bound, 1 );
    }
    return $self->_raise( $state, $failure );
}

# A statement prepared before a migration changed the columns its function
# returns -- one of the functions that RETURNS SETOF public.<table>, whose
# table gained a column -- is refused once its plan is invalidated. The
# statement is forgotten, so the next call prepares it afresh, and outside a
# transaction this call is made once more. Inside one it is not: the error
# has ended the transaction, and the caller's retry begins a new one.
sub _fetch ( $self, $dbh, $entry, $bound ) {
    my ( $rows, $state, $error ) = _run( $dbh, $entry, $bound );
    if ( defined $error && _result_type_changed( $state, $error ) ) {
        _forget( $dbh, $entry->{sql} );
        if ( $dbh->{AutoCommit} ) {
            ( $rows, $state, $error ) = _run( $dbh, $entry, $bound );
        }
    }
    if ( defined $error ) {
        $self->_raise( $state, $error );
    }

    return $rows;
}

# The rows, or the SQLSTATE and the error.
sub _run ( $dbh, $entry, $bound ) {
    my $handle = $dbh->prepare_cached( $entry->{sql}, $PREPARED_NOW );
    my ( $rows, $failure );
    try {
        if ( $entry->{has_binary} ) {
            require DBD::Pg;
            for my $index ( 0 .. $#{$bound} ) {
                my $attributes =
                  $entry->{types}[$index] eq 'bytea'
                  ? { pg_type => DBD::Pg::PG_BYTEA() }
                  : {};
                $handle->bind_param( $index + 1, $bound->[$index],
                    $attributes );
            }
            $handle->execute;
        }
        else {
            $handle->execute( @{$bound} );
        }
        $rows = $handle->fetchall_arrayref( {} );
    }
    catch ($error) {
        $failure = $error;
    };

    return ( $rows, $handle->state, $failure );
}

sub _result_type_changed ( $state, $error ) {
    return ( $state // q{} ) eq $FEATURE_NOT_SUPPORTED
      && "$error" =~ $RESULT_TYPE_CHANGED;
}

# Drops the handle's cached statement for this SQL, so the next
# prepare_cached prepares it again.
sub _forget_p ( $self, $db, $sql ) {
    my $cached = $db->dbh->{CachedKids} // {};
    my @names;
    for my $key ( keys %{$cached} ) {
        my $statement = $cached->{$key};
        next if !$statement || ( $statement->{Statement} // q{} ) ne $sql;
        if ( $statement->{pg_prepare_name} ) {
            push @names, $statement->{pg_prepare_name};
        }
        delete $cached->{$key};
    }
    my $chain = Mojo::Promise->resolve;
    for my $name (@names) {
        $chain = $chain->then(
            sub {
                return $db->query_p(
                    'DEALLOCATE ' . $db->dbh->quote_identifier($name) );
            }
        );
    }
    return $chain;
}

sub _forget ( $dbh, $sql ) {
    my $cached = $dbh->{CachedKids} // {};
    for my $key ( keys %{$cached} ) {
        my $statement = $cached->{$key};
        next if !$statement || ( $statement->{Statement} // q{} ) ne $sql;
        delete $cached->{$key};
    }

    return;
}

# ADR 0126, section 6: a function's own contract violation (22023) is the
# caller's mistake, a unique violation that escapes a function is a
# conflict, and every other error propagates as DBI raised it.
sub _raise ( $self, $state, $error ) {
    if ( ( $state // q{} ) eq $INVALID_PARAMETER ) {
        GPForum::X::Argument->throw(
            cause   => $error,
            message => GPForum::X::Conflict->server_message($error),
        );
    }

    # The SQLSTATE decides that it is a conflict. The server's sentence names
    # the constraint, and only in English (lc_messages=C): a conflict it does
    # not name is one on no constraint a store recovers from.
    if ( ( $state // q{} ) eq $UNIQUE_VIOLATION ) {
        croak GPForum::X::Conflict->from_error( $error, $self->schema )
          // GPForum::X::Conflict->new(
            message => "$error",
            cause   => $error,
            schema  => $self->schema,
          );
    }

    croak $error;
}

sub _decode_json ( $entry, $rows ) {
    my @columns = keys %{ $entry->{json} };
    for my $row ( @{$rows} ) {
        for my $column (@columns) {
            next if !defined $row->{$column};
            $row->{$column} = $JSON->decode( $row->{$column} );
        }
    }

    return;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::SqlFunction - Call a PostgreSQL function with bound parameters and read its rows.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $functions = GPForum::Infrastructure::SqlFunction->for_schema($schema)
      or return $self->_old_path(...);    # a test double has none

    my $thread = $functions->row( 'forum_thread_page_head',
        { thread_id => $thread_id } );
    my $posts = $functions->rows(
        'forum_thread_page_posts',
        {
            after_position => undef,
            after_post_id  => undef,
            row_limit      => 26,
            standing       => 'member',
            thread_id      => $thread_id,
            viewer_user_id => $user_id,
        }
    );

=head1 DESCRIPTION

ADR 0126: every statement the application sends is a call to a function in
schema C<api>. This is the layer that makes the call. It takes the name a
release calls a function by (L<GPForum::Infrastructure::SqlFunctionCatalogue>
gives its version and its parameters) and the parameters by name, and
returns plain rows: hashes keyed by the function's columns, with its json
columns decoded. The statement is the catalogue's,
C<SELECT * FROM api.NAME_vN(?::type, ...)>, prepared once per handle, on the
server at once (C<pg_prepare_now>), and executed with the values. No SQL is
built per call, no row object is made.

Until the last area has moved, a call runs on the DBIx::Class schema's own
handle (C<dbh_do>): inside a C<txn_do> it joins that transaction, outside one
it is a statement in autocommit. Each call is reported to the storage's
statistics as one statement.

A boolean parameter is bound as 1 or 0, a jsonb parameter given as a
reference is encoded as canonical JSON, and an undefined value is a NULL. A
uuid parameter whose spelling PostgreSQL would refuse is not sent: there is
no call, and no rows.

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>): C<schema>, the L<DBIx::Class> schema whose
handle the calls run on, is required. C<catalogue> defaults to the
process's one L<GPForum::Infrastructure::SqlFunctionCatalogue>.

=head2 for_schema

The layer for a DBIx::Class schema configured for PostgreSQL. An unconfigured
real schema or another database driver raises C<GPForum::X::Argument>.
Returns undef for non-DBIx test doubles, whose callers retain their test path.

=head2 rows

Takes the function's catalogue name and a hash reference of its parameters
by name, every one of them. Returns an array reference of hashes, one per
row.

=head2 row

As L</rows>, the first row or undef.

=head2 statement

As L</rows> takes its arguments, the statement the call would send and its
values as they would be bound, in an array reference, without sending it.

=head2 answering

    my $payload = GPForum::Infrastructure::SqlFunction->answering(
        { $functions->answer_key( $name, $values ) => \@rows },
        sub { return build_the_page() },
    );

A class method. Runs the code with the answers given -- rows, under the
key L</answer_key> makes for the call they answer -- and returns what it
returns. While it runs, a call of L</rows> or L</row> whose key is among the
answers takes those rows, once, and sends nothing; any other call, and
every call after the code has returned or died, goes to the database.

=head2 answer_key

Takes a function's catalogue name and its parameters, as L</rows> does, and
answers the key L</answering> keeps that call's rows under: the function
and the values as they would be bound.

=head2 transaction_p

Exclusively leases a native connection through BEGIN and COMMIT or ROLLBACK.
The callback receives a scoped function transport; nested transactions use
savepoints. Query cancellation and swallowed statement failures reject the
transaction. Ambiguous commits are never replayed.

=head2 rows_p, row_p

Promise versions of rows and row, using a separate pooled connection per
in-flight operation. Parameter checks, JSON decoding and bytea bindings retain
the synchronous contracts. A changed prepared result type is retried once in
autocommit; connection loss never retries a potentially committed mutation.

=head1 DIAGNOSTICS

A name the catalogue does not list, a parameter left out and one the
function does not have throw L<GPForum::X::Argument>. A function's own
contract violation (SQLSTATE 22023, C<invalid_parameter_value>) is thrown as
L<GPForum::X::Argument> with the server's message; a unique violation
(23505) as a L<GPForum::X::Conflict>, whose C<on> knows the partitions'
indexes. Every other error is DBI's, as it was raised.

A prepared call whose function's result columns changed under it (SQLSTATE
0A000, C<cached plan must not change result type>: a table a function
C<RETURNS SETOF> gained a column) is not a failure of the call: the cached
statement is dropped, and outside a transaction the call is made once more
on a statement prepared afresh. Inside a transaction, which the error has
ended, the error propagates and the next call prepares the statement again.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<DBIx::Class> (its storage's handle and statistics), L<JSON::MaybeXS>,
L<Const::Fast>, L<Mojo::Base>, L<GPForum::Base>,
L<GPForum::Infrastructure::Id>,
L<GPForum::Infrastructure::SqlFunctionCatalogue>, L<GPForum::X::Argument>,
L<GPForum::X::Conflict>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The layer runs on DBIx::Class's connection until the last area has moved
(ADR 0126, section 8); it owns no connection of its own yet.

Outside a transaction, a call whose connection was lost is run once more on
a new connection, as DBIx::Class's C<dbh_do> runs it. A function that
writes in autocommit -- C<session_validate>'s touch, C<ops_rate_limit_check>'s
increment, C<session_create> -- can so be written twice when the connection
goes between the server's commit and the client's read of it. The commands
are idempotent through C<command_log>; these are not, and the window is a
connection lost at that instant. Kept for parity with C<dbh_do>.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
