package GPForum::Test::AuditChainStorage;

use Mojo::Base 'GPForum::Test::BareStorage';
use v5.40;

our $VERSION = '0.001';

has schema => undef;

# The storage is its own handle. Like a DBI handle it reports AutoCommit,
# false only inside a transaction: UniqueConflict takes a savepoint only when
# it is false, and DBIx::Class refuses a savepoint outside a transaction.
sub dbh {
    my ($self) = @_;

    $self->{AutoCommit} = $self->transaction_depth ? 0 : 1;

    return $self;
}

sub selectrow_array {
    my ( $self, $sql, undef, @bind ) = @_;

    $self->schema->record_step( 'lock', $sql );

    return $bind[0];
}

1;
