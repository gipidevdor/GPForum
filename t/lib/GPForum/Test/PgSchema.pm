# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::PgSchema;
use Mojo::Base 'GPForum::Schema', -signatures;
use v5.40;
use GPForum::Test::LegacySchema;
use GPForum::Test::PgStorage;
use Scalar::Util qw(weaken);
our $VERSION = '0.001';

# ORM access exists only for historical fixture setup and metadata assertions.
# Services still recognize this as GPForum::Schema and execute on Mojo::Pg.
has storage        => sub { return GPForum::Test::PgStorage->new; };
has fixture_schema => sub ($self) {
    my $native = $self;
    weaken($native);
    my $fixture = GPForum::Test::LegacySchema->connect(
        sub {
            my $dbh = $native->storage->database->dbh;
            $dbh->{ShowErrorStatement} = 1;
            return $dbh;
        },
        { AutoCommit => 1, RaiseError => 1, PrintError => 0 }
    );
    $self->storage->bind_fixture( $fixture->storage );
    return $fixture;
};

sub resultset ( $self, @args ) {
    return $self->fixture_schema->resultset(@args);
}
sub source  ( $self, @args ) { return $self->fixture_schema->source(@args); }
sub sources ($self)          { return $self->fixture_schema->sources; }
1;
