# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::QueryPlanEvidenceDbh;

use Carp          qw(croak);
use JSON::MaybeXS qw(encode_json);
use Mojo::Base -base;
use v5.40;

our $VERSION = '0.001';

has plan => sub {
    return {
        Plan => {
            'Node Type'     => 'Index Scan',
            'Relation Name' => 'threads',
            'Plan Rows'     => 10,
            'Actual Rows'   => 10,
            'Total Cost'    => 1,
        },
    };
};

# The plan with sequential scans disabled; the same plan unless a test
# gives the index the planner falls back to.
has forced_plan => undef;

# What the catalog says of a table's size: large unless a test says not.
has relation_rows => 1_000_000;
has statements    => sub { return []; };
has transactions  => sub { return []; };

# Plans answered in turn, before `plan` takes over: a deep endpoint EXPLAINs
# its first page, then the deep one.
has plans => sub { return []; };

# The row the deep-page query finds, as DBD::Pg returns it; none -- a
# database with nothing to page through -- unless a test gives one.
has deep_page => undef;

# Opt-in fixtures for the function gate: the driver's warning stream carries
# auto_explain JSON, while the call still returns its ordinary rows.
has nested_plans    => sub { return []; };
has nested_calls    => 0;
has fail_load       => 0;
has load_error      => "auto_explain unavailable\n";
has state           => undef;
has statement_error => undef;

sub selectall_arrayref {
    my ( $self, $sql, undef, @bind ) = @_;

    push @{ $self->statements }, { sql => $sql, bind => \@bind };
    $self->nested_calls( $self->nested_calls + 1 );
    for my $plan (
        @{ $self->nested_plans },
        { 'Query Text' => 'SELECT * FROM api.forum_list_public_threads_v2()' }
      )
    {
        warn 'plan: ' . encode_json($plan) . "\n";
    }

    return [];
}

# Records what was EXPLAINed, so a test can check it is the application's
# SQL, and answers with the configured plan.
sub selectrow_array {
    my ( $self, $sql, undef, @bind ) = @_;

    croak $self->statement_error if defined $self->statement_error;

    push @{ $self->statements }, { sql => $sql, bind => \@bind };
    return $self->relation_rows if $sql =~ /\b pg_class \b/msx;

    if ( $self->{seqscan_off} ) {
        return encode_json( [ $self->forced_plan || $self->plan ] );
    }

    return encode_json( [ shift @{ $self->plans } || $self->plan ] );
}

sub selectrow_hashref {
    my ( $self, $sql ) = @_;

    push @{ $self->statements }, { sql => $sql, bind => [] };

    return $self->deep_page;
}

## no critic (Subroutines::ProhibitBuiltinHomonyms)
# The name is DBI's: the command under test calls $dbh->do, so the double must
# answer to it.
sub do {
    my ( $self, $sql ) = @_;

    croak $self->load_error
      if $self->fail_load && $sql eq q{LOAD 'auto_explain'};

    push @{ $self->statements }, { sql => $sql, bind => [] };
    if ( $sql =~ /enable_seqscan [ ] = [ ] off/msx ) {
        $self->{seqscan_off} = 1;
    }

    return 1;
}
## use critic

sub begin_work {
    my ($self) = @_;

    push @{ $self->transactions }, 'begin';

    return 1;
}

sub rollback {
    my ($self) = @_;

    push @{ $self->transactions }, 'rollback';
    $self->{seqscan_off} = 0;

    return 1;
}

1;
