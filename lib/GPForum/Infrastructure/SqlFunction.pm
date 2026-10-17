# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::SqlFunction;

use Carp qw(croak);
use Const::Fast;
use JSON::MaybeXS;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunctionCatalogue;
use GPForum::X::Argument;
use GPForum::X::Conflict;

our $VERSION = '0.001';

const my $INVALID_PARAMETER => '22023';
const my $UNIQUE_VIOLATION  => '23505';
const my $POSTGRESQL_DSN    => qr/\A dbi:Pg:/imsx;

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

# What separates the parts of a key: the function, then each bound value,
# an array's elements in order, a NULL as itself.
const my $KEY_UNIT    => "\N{INFORMATION SEPARATOR ONE}";
const my $KEY_ELEMENT => "\N{INFORMATION SEPARATOR TWO}";
const my $KEY_NULL    => "\N{NULL}";

__PACKAGE__->requires('schema');
has catalogue => sub { return $CATALOGUE; };

# ADR 0126, section 8. Until the last area has moved, a call runs on the
# DBIx::Class schema's own handle, so a call and a statement not yet moved
# share one connection and one transaction: a call made inside txn_do joins
# it, and one made outside is a statement in autocommit. A schema that is not
# a DBIx::Class schema -- an in-memory test double -- has no layer. A real
# schema must use PostgreSQL; another driver must not enable ORM routing.
sub for_schema ( $class, $schema ) {
    return undef if !blessed $schema || !$schema->isa('DBIx::Class::Schema');

    my $info = $schema->storage->connect_info;
    if ( ref $info ne 'ARRAY' || !defined $info->[0] || ref $info->[0] ) {
        GPForum::X::Argument->throw(
            message => 'SQL function routing needs a configured database DSN' );
    }
    if ( $info->[0] !~ $POSTGRESQL_DSN ) {
        GPForum::X::Argument->throw(
            message => 'SQL function routing requires PostgreSQL' );
    }

    return $class->new( schema => $schema );
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
    return join $KEY_UNIT, $entry->{function}, map {
           !defined $_ ? $KEY_NULL
          : ref $_ eq 'ARRAY'
          ? join( $KEY_ELEMENT, map { $_ // $KEY_NULL } @{$_} )
          : $_
    } @{$bound};
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
    my %given = %{ $values // {} };
    my @bound;
    for my $index ( 0 .. $#{ $entry->{names} } ) {
        my $parameter = $entry->{names}[$index];
        if ( !exists $given{$parameter} ) {
            GPForum::X::Argument->throw( message =>
                  "$entry->{function} needs $parameter, which was not given" );
        }
        push @bound,
          _typed( $entry->{types}[$index], delete $given{$parameter} );
    }
    if (%given) {
        my $unknown = join q{, }, sort keys %given;
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
sub _malformed_id ( $entry, $bound ) {
    for my $index ( 0 .. $#{$bound} ) {
        next
          if $entry->{types}[$index] ne 'uuid'
          && $entry->{types}[$index] ne 'uuid[]';
        next if !defined $bound->[$index];
        for my $value (
            ref $bound->[$index] eq 'ARRAY'
            ? @{ $bound->[$index] }
            : $bound->[$index]
          )
        {
            return 1 if !GPForum::Infrastructure::Id->is_uuid_spelling($value);
        }
    }

    return 0;
}

# Prepared once per handle and reported to the storage's statistics as one
# statement, as every DBIx::Class statement is, so the query budgets count a
# call as the one statement it is.
sub _execute ( $self, $entry, $bound ) {
    my $storage = $self->schema->storage;
    my $stats   = $storage->debug ? $storage->debugobj : undef;
    if ($stats) {
        $stats->query_start( $entry->{sql},
            map { defined $_ ? $_ : 'NULL' } @{$bound} );
    }
    my $rows = $storage->dbh_do(
        sub ( $, $dbh ) {
            return $self->_fetch( $dbh, $entry, $bound );
        }
    );
    if ($stats) {
        $stats->query_end( $entry->{sql},
            map { defined $_ ? $_ : 'NULL' } @{$bound} );
    }

    return $rows;
}

sub _fetch ( $self, $dbh, $entry, $bound ) {
    my $handle = $dbh->prepare_cached( $entry->{sql} );
    my $rows;
    try {
        $handle->execute( @{$bound} );
        $rows = $handle->fetchall_arrayref( {} );
    }
    catch ($error) {
        $self->_raise( $handle->state, $error );
    };

    return $rows;
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
    if ( ( $state // q{} ) eq $UNIQUE_VIOLATION ) {
        croak GPForum::X::Conflict->from_error( $error, $self->schema );
    }

    croak $error;
}

sub _decode_json ( $entry, $rows ) {
    for my $row ( @{$rows} ) {
        for my $column ( keys %{ $entry->{json} } ) {
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
C<SELECT * FROM api.NAME_vN(?::type, ...)>, prepared once per handle and
executed with the values. No SQL is built per call, no row object is made.

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

=head1 DIAGNOSTICS

A name the catalogue does not list, a parameter left out and one the
function does not have throw L<GPForum::X::Argument>. A function's own
contract violation (SQLSTATE 22023, C<invalid_parameter_value>) is thrown as
L<GPForum::X::Argument> with the server's message; a unique violation
(23505) as a L<GPForum::X::Conflict>, whose C<on> knows the partitions'
indexes. Every other error is DBI's, as it was raised.

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

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
