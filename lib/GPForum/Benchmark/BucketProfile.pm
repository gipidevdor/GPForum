# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Benchmark::BucketProfile;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use Time::HiRes qw(time);

our $VERSION = '0.001';

# What the inventory of ADR 0126 charged DBIx::Class with, by bucket: the
# statement SQL::Abstract builds, the resultset, row, schema and storage
# methods, row inflation and column accessors; and DBI, the calls that wait
# on PostgreSQL and the socket.
const my %METHODS => (
    dbic => {
        'DBIx::Class::InflateColumn' => [qw(get_inflated_column)],
        'DBIx::Class::ResultSet'     => [
            qw(search search_rs find single create new_result all next first
              count count_rs get_column update update_all delete delete_all
              populate find_or_create update_or_create search_related
              related_resultset as_query cursor slice _construct_results)
        ],
        'DBIx::Class::ResultSetColumn' => [qw(all first next func max min sum)],
        'DBIx::Class::Row'             => [
            qw(insert update delete discard_changes set_column set_columns
              get_column get_columns get_inflated_columns has_column_loaded
              inflate_result related_resultset)
        ],
        'DBIx::Class::Schema'       => [qw(resultset txn_do source)],
        'DBIx::Class::Storage::DBI' => [
            qw(txn_do dbh_do insert update delete select select_single
              txn_begin txn_commit txn_rollback svp_begin svp_release dbh
              _gen_sql_bind)
        ],
    },
    dbi => {
        'DBI::db' => [
            qw(do prepare prepare_cached selectrow_array selectrow_arrayref
              selectrow_hashref selectall_arrayref selectcol_arrayref
              begin_work commit rollback pg_savepoint pg_release
              pg_rollback_to)
        ],
        'DBI::st' => [
            qw(execute fetch fetchrow_array fetchrow_arrayref
              fetchrow_hashref fetchall_arrayref fetchall_hashref)
        ],
    },
);

has active   => 0;
has original => sub { return {}; };
has spent    => sub { return {}; };
has stack    => sub { return []; };
has since    => 0;

# Wraps every method of the buckets: a call made while measuring charges
# the time since the last event to the bucket on top of the stack, and its
# own time to its bucket. A DBI call inside a DBI call is DBI's.
sub wrap ($self) {
    require DBI;
    require DBIx::Class::InflateColumn;
    require DBIx::Class::ResultSet;
    require DBIx::Class::ResultSetColumn;
    require DBIx::Class::Row;
    require DBIx::Class::Schema;
    require DBIx::Class::Storage::DBI;
    for my $bucket ( sort keys %METHODS ) {
        for my $package ( sort keys %{ $METHODS{$bucket} } ) {
            for my $method ( @{ $METHODS{$bucket}{$package} } ) {
                $self->_wrap( "${package}::$method", $bucket );
            }
        }
    }

    return $self;
}

sub unwrap ($self) {
    for my $name ( keys %{ $self->original } ) {
        _install( $name, $self->original->{$name} );
    }
    $self->original( {} );

    return $self;
}

# Runs the code and answers the exclusive seconds each bucket took, and
# "other" for the rest.
sub measure ( $self, $code ) {
    $self->spent( {} );
    $self->stack( [] );
    $self->since(time);
    $self->active(1);
    $code->();
    $self->charge;
    $self->active(0);

    return { %{ $self->spent } };
}

# The time since the last event, to the bucket on top of the stack.
sub charge ($self) {
    my $now = time;
    $self->spent->{ $self->stack->[-1] // 'other' } += $now - $self->since;
    $self->since($now);

    return;
}

sub _wrap ( $self, $name, $bucket ) {
    my $original = $self->_defined($name);
    return if !$original || $self->original->{$name};

    $self->original->{$name} = $original;
    my $profile = $self;
    _install(
        $name,
        sub {
            return &{$original}
              if !$profile->active || ( $profile->stack->[-1] // q{} ) eq 'dbi';

            $profile->charge;
            push @{ $profile->stack }, $bucket;
            my $want = wantarray;
            my @result;
            try {
                @result =
                    $want         ? &{$original}
                  : defined $want ? scalar &{$original}
                  :                 ( &{$original}, () );
            }
            catch ($error) {
                $profile->charge;
                pop @{ $profile->stack };
                die $error;    ## no critic (ErrorHandling::RequireCarping) -- the wrapped method's error, as it was
            };
            $profile->charge;
            pop @{ $profile->stack };

            return $want ? @result : $result[0];
        }
    );

    return;
}

sub _defined ( $self, $name ) {
    ## no critic (TestingAndDebugging::ProhibitNoStrict) -- a method named at run time
    no strict 'refs';
    return defined &{$name} ? \&{$name} : undef;
    ## use critic
}

sub _install ( $name, $code ) {
    ## no critic (TestingAndDebugging::ProhibitNoStrict TestingAndDebugging::ProhibitNoWarnings) -- a method replaced, by name, for the length of a profile
    no strict 'refs';
    no warnings 'redefine';
    *{$name} = $code;
    ## use critic

    return;
}

1;

__END__

=head1 NAME

GPForum::Benchmark::BucketProfile - Exclusive time per bucket: DBIx::Class, DBI and the rest.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $profile = GPForum::Benchmark::BucketProfile->new->wrap;
    my $spent   = $profile->measure( sub { $reader->thread_page($request) } );
    # { dbic => 0.0006, dbi => 0.0004, other => 0.0021 }, in seconds
    $profile->unwrap;

=head1 DESCRIPTION

The measure ADR 0126 is judged by: how much of an operation's Perl time
DBIx::Class takes -- SQL::Abstract building the statement, resultsets,
storage, row inflation, accessors -- against the time spent in DBI waiting
on PostgreSQL. Every method of the two buckets is wrapped; a call made
while L</measure> runs charges the time since the last event to the bucket
on top of the stack and pushes its own. A DBI call made inside another is
the outer one's. The wrappers cost time of their own, so the totals are
larger than an unwrapped run's; the shares are what to read.

=head1 SUBROUTINES/METHODS

=head2 wrap

Wraps the methods, once; returns the profile.

=head2 unwrap

Puts the methods back.

=head2 measure

Runs the code and returns the exclusive seconds of each bucket: C<dbic>,
C<dbi> and C<other>.

=head2 charge

Charges the time since the last event to the bucket on top of the stack.

=head1 DIAGNOSTICS

An error of a wrapped method passes through as it was.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<DBI>, L<DBIx::Class>, L<Time::HiRes>, L<Const::Fast>, L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The process's methods are replaced while the profile is wrapped: one
profile at a time.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
