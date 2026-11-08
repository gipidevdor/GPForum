# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::PgStorage;

use Mojo::Base -base, -signatures;
use v5.40;
use Carp qw(croak);
use Const::Fast;
use English qw(-no_match_vars);
use Mojo::Pg;
use Mojo::Promise;
use GPForum::Infrastructure::PgConnect;
use Scalar::Util qw(weaken);

our $VERSION = '0.001';
our $HTTP_PID;

# Set inside a CPU-only child (AsyncWork::cpu_p): such a child never opens
# a PostgreSQL connection of its own.
our $NO_DATABASE;
const my $ATTRIBUTES_INDEX => 3;

has notifications => undef, weak => 1;
has connect_info  => sub { return []; };
has debug         => 0;
has debugobj      => undef;    # optional: request query statistics observer
has debugcb       => undef;    # optional: diagnostic statement callback
has
  async_queries => undef,
  weak          => 1;   # optional: the schema's dedicated asynchronous executor
has pg => sub ($self) {
    my ( $dsn, $user, $password, $attributes ) = @{ $self->connect_info };
    croak 'PostgreSQL connection information is required' if !defined $dsn;
    croak 'Mojo::Pg requires PostgreSQL' if $dsn !~ /\Adbi:Pg:/imsx;
    my %options = %{ $attributes // {} };
    delete @options{
        qw(on_connect_do on_connect_call on_connect_call_p quote_names auto_savepoint limit_dialect)
    };
    my $pg = Mojo::Pg->new;
    $pg->database_class('GPForum::Infrastructure::PgDatabase');
    $pg->dsn($dsn)->username( $user // q{} )->password( $password // q{} );
    $pg->options( { %{ $pg->options }, %options, pg_prepare_now => 1 } );
    my $storage = $self;
    weaken($storage);
    $pg->on(
        connection => sub ( $, $dbh ) {
            if ( $storage && !$dbh->{private_gp_async_connect} ) {
                $storage->_connected($dbh);
            }
            return;
        }
    );
    return $pg;
};
has savepoints => sub { return []; };
has frames     => sub { return []; };
has connector  => sub { return GPForum::Infrastructure::PgConnect->new; };

sub database_p ( $self, $context = undef ) {
    return $self->connector->connect_p( $self->pg )->then(
        sub ($db) {
            $db->dbh->{private_gp_async_connect} = 1;
            $self->pg->emit( connection => $db->dbh );
            return $self->_connected_p( $db, $context )
              ->then( sub { return $db; } );
        }
    );
}

sub _connected_p ( $self, $db, $context ) {
    my $options  = $self->connect_info->[$ATTRIBUTES_INDEX] // {};
    my $settings = $options->{on_connect_do}                // [];
    if ( ref $settings ne 'ARRAY' ) { $settings = [$settings]; }
    my $chain = Mojo::Promise->resolve;
    for my $setting ( @{$settings} ) {
        $chain = $chain->then(
            sub {
                my ( $sql, @bind ) =
                  ref $setting eq 'ARRAY' ? @{$setting} : ($setting);
                my $stats = $self->debug ? $self->debugobj : undef;
                if ($stats) {
                    $stats->in_context( $context,
                        sub { $stats->query_start($sql); return; } );
                }
                return $db->query_p( $sql, @bind )->finally(
                    sub {
                        if ($stats) {
                            $stats->in_context( $context,
                                sub { $stats->query_end; return; } );
                        }
                        return;
                    }
                );
            }
        );
    }
    return $chain->then(
        sub {
            my $callback = $options->{on_connect_call_p};
            return $callback->( $self, $db ) if ref $callback eq 'CODE';
            croak 'asynchronous connections require on_connect_call_p'
              if ref $options->{on_connect_call} eq 'CODE';
            return;
        }
    );
}

sub _connected ( $self, $dbh ) {
    local $self->{connecting_dbh} = $dbh;    ## no critic (Variables::ProhibitLocalVars) -- the connection hook must reuse its handle while it initializes the storage
    my $options  = $self->connect_info->[$ATTRIBUTES_INDEX] // {};
    my $settings = $options->{on_connect_do}                // [];
    if ( ref $settings ne 'ARRAY' ) { $settings = [$settings]; }
    for my $setting ( @{$settings} ) {
        my ( $sql, @bind ) = ref $setting eq 'ARRAY' ? @{$setting} : ($setting);
        my $stats = $self->debug ? $self->debugobj : undef;
        if ($stats) { $stats->query_start( $sql, @bind ); }
        my $error;
        try { $dbh->do( $sql, undef, @bind ); }
        catch ($caught) { $error = $caught; };
        if ($stats) { $stats->query_end( $sql, @bind ); }
        die $error if defined $error;    ## no critic (ErrorHandling::RequireCarping) -- preserve the original connection exception
    }
    my $callback = $options->{on_connect_call};
    if ( ref $callback eq 'CODE' ) { $callback->($self); }
    return;
}

sub database ($self) {
    croak 'PostgreSQL access in a CPU-only child' if $NO_DATABASE;
    croak 'blocking PostgreSQL access on HTTP event loop'
      if defined $HTTP_PID && $HTTP_PID == $PROCESS_ID;
    croak 'Connection lost inside a transaction' if $self->{transaction_broken};
    if ( $self->{owner} && $self->{owner} != $PROCESS_ID ) {
        if ( my $old = delete $self->{database} ) {
            $old->dbh->{InactiveDestroy}       = 1;
            $old->dbh->{private_mojo_no_reuse} = 1;
        }
        $self->pg->reset;
        $self->frames( [] );
        $self->savepoints( [] );
    }
    $self->{owner} = $PROCESS_ID;
    return $self->{database} //= $self->pg->db;
}

sub _get_dbh ($self) {
    return $self->{connecting_dbh} // $self->database->dbh;
}

sub dbh ($self) {
    croak 'PostgreSQL access in a CPU-only child' if $NO_DATABASE;
    croak 'blocking PostgreSQL access on HTTP event loop'
      if defined $HTTP_PID && $HTTP_PID == $PROCESS_ID;
    return $self->{connecting_dbh} if $self->{connecting_dbh};
    $self->ensure_connected;
    return $self->_get_dbh;
}

sub connected ($self) {
    croak 'blocking PostgreSQL access on HTTP event loop'
      if defined $HTTP_PID && $HTTP_PID == $PROCESS_ID;
    return 0 if !$self->{database} || ( $self->{owner} // 0 ) != $PROCESS_ID;
    my $dbh = $self->{database}->dbh;
    return $dbh->{Active} && $dbh->ping ? 1 : 0;
}

sub ensure_connected ($self) {
    return $self                                 if $self->connected;
    croak 'Connection lost inside a transaction' if $self->transaction_depth;
    $self->disconnect;
    $self->database;
    return $self;
}

sub disconnect ($self) {
    if ( my $broker  = $self->notifications ) { $broker->retire_connections; }
    if ( my $queries = $self->async_queries ) { $queries->retire_connections; }
    $self->frames( [] );
    $self->savepoints( [] );
    delete $self->{transaction_broken};
    if ( my $db = delete $self->{database} ) {
        $db->dbh->{private_mojo_no_reuse} = 1;
        if ( ( $self->{owner} // 0 ) == $PROCESS_ID ) { $db->disconnect; }
        else { $db->dbh->{InactiveDestroy} = 1; }
    }
    if ( $self->{pg} ) { $self->pg->reset; }
    return;
}

sub dbh_do ( $self, $code, @args ) {
    return $code->( $self, $self->_get_dbh, @args );
}

sub transaction_depth ($self) { return scalar @{ $self->frames }; }

sub txn_begin ($self) {
    my $dbh = $self->_get_dbh;
    my $savepoint;
    if ( !$dbh->{AutoCommit} ) {
        $savepoint = $self->svp_begin;
    }
    else {
        $dbh->begin_work;
        if ( $self->debug && $self->debugobj ) { $self->debugobj->txn_begin; }
    }
    push @{ $self->frames }, $savepoint;
    return;
}

sub txn_commit ($self) {
    croak 'No active transaction' if !$self->transaction_depth;
    my $savepoint = $self->frames->[-1];
    if ( defined $savepoint ) { $self->svp_release($savepoint); }
    else {
        $self->_get_dbh->commit;
        if ( $self->debug && $self->debugobj ) { $self->debugobj->txn_commit; }
    }
    pop @{ $self->frames };
    return;
}

sub txn_rollback ($self) {
    croak 'No active transaction' if !$self->transaction_depth;
    my $savepoint = $self->frames->[-1];
    if ( defined $savepoint ) {
        $self->svp_rollback($savepoint);
        $self->svp_release($savepoint);
    }
    else {
        $self->_get_dbh->rollback;
        if ( $self->debug && $self->debugobj ) {
            $self->debugobj->txn_rollback;
        }
    }
    pop @{ $self->frames };
    return;
}

sub txn_do ( $self, $code, @args ) {
    my $want = wantarray;
    my ( @values, $value, $error );
    $self->txn_begin;
    try {
        if    ( !defined $want ) { $code->(@args); }
        elsif ($want)            { @values = $code->(@args); }
        else                     { $value = $code->(@args); }
        $self->txn_commit;
    }
    catch ($caught) {
        $error = $caught;
        try { $self->txn_rollback; } catch ($rollback_error) {

            # A failed nested rollback poisons the enclosing transaction.
            # Catching its exception must never permit autocommit on a new
            # connection before all transaction owners have unwound.
            $self->{transaction_broken} = 1;
            pop @{ $self->frames };
            if ( !$self->transaction_depth ) {
                try { $self->disconnect; } catch ($disconnect_error) {
                };
            }
        };
    };
    die $error if defined $error;    ## no critic (ErrorHandling::RequireCarping) -- preserve the caller's original exception after rollback
    return $want ? @values : $value;
}

sub svp_begin ( $self, $name = undef ) {
    $name //= 'gpforum_' . ++$self->{savepoint_sequence};
    croak 'Invalid savepoint name'
      if $name !~ /\A[[:alpha:]_][[:alnum:]_]*\z/amsx;
    $self->_get_dbh->do("SAVEPOINT $name");
    push @{ $self->savepoints }, $name;
    return $name;
}

sub svp_rollback ( $self, $name = undef ) {
    $name //= $self->savepoints->[-1];
    $self->_savepoint_index($name);
    $self->_get_dbh->do("ROLLBACK TO SAVEPOINT $name");
    splice @{ $self->savepoints }, $self->_savepoint_index($name) + 1;
    return;
}

sub svp_release ( $self, $name = undef ) {
    $name //= $self->savepoints->[-1];
    my $index = $self->_savepoint_index($name);
    $self->_get_dbh->do("RELEASE SAVEPOINT $name");
    splice @{ $self->savepoints }, $index;
    return;
}

sub _savepoint_index ( $self, $name ) {
    my @names = @{ $self->savepoints };
    for my $index ( 0 .. $#names ) {
        return $index if defined $name && $names[$index] eq $name;
    }
    croak 'Unknown savepoint';
}

1;
