# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Module::CPANfile;
use Test::More;
use lib 'lib';
use GPForum;
use GPForum::Schema;
our $VERSION = '0.001';

# These invariants run without PostgreSQL, including in the default CI tier.
# A future ORM import or dependency must not silently restore table access.
my $schema = GPForum::Schema->connect('dbi:Pg:dbname=transport_contract');
isa_ok( $schema->pg,      'Mojo::Pg' );
isa_ok( $schema->storage, 'GPForum::Infrastructure::PgStorage' );
for my $method (qw(resultset source sources)) {
    ok( !$schema->can($method), "the runtime exposes no $method ORM API" );
}
is_deeply( [ grep { m{\ADBIx/}msx } keys %INC ],
    [], 'the application import graph loads no DBIx module' );
my $prereqs = Module::CPANfile->load('cpanfile')->prereqs;
my $runtime = $prereqs->requirements_for( 'runtime', 'requires' );
ok( $runtime->requirements_for_module('Mojo::Pg'),
    'Mojo::Pg is mandatory at runtime' );
ok(
    !$runtime->requirements_for_module('DBIx::Class'),
    'DBIx is absent from runtime requirements'
);
ok(
    $prereqs->requirements_for( 'develop', 'requires' )
      ->requirements_for_module('DBIx::Class'),
    'historical ORM comparisons remain a maintainer dependency'
);
done_testing;
1;
