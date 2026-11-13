# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Test::More;
use lib 'lib';
use GPForum::Schema;
use GPForum::Infrastructure::Id;
use GPForum::Service::Admin::RoleCatalog;
use GPForum::Service::Moderation::SuspensionStore;

our $VERSION = '0.001';

my @schemas = map {
    GPForum::Schema->connect( "dbi:Pg:host=127.0.0.1;port=1;dbname=factory_$_",
        q{}, q{} )
} qw(first second);
my @ids    = map { GPForum::Infrastructure::Id->new } @schemas;
my @owners = (
    GPForum::Service::Admin::RoleCatalog->new(
        schema     => $schemas[0],
        id_service => $ids[0]
    ),
    GPForum::Service::Moderation::SuspensionStore->new(
        schema     => $schemas[1],
        id_service => $ids[1]
    ),
);

for my $index ( 0 .. $#owners ) {
    my $owner = $owners[$index];
    ok( !exists $owner->{functions}, 'SQL routing remains lazy' );
    ok( !exists $owner->{recorder},  'event wiring remains lazy' );
    is( $owner->functions->schema,
        $schemas[$index],
        'SQL routing belongs to this owner without opening a connection' );
    is( $owner->recorder->schema,
        $schemas[$index], 'the recorder belongs to this schema' );
    is( $owner->recorder->id_service,
        $ids[$index], 'the injected id generator is retained' );
    is( $owner->recorder, $owner->recorder,
        'each owner retains its lazy recorder' );
}
isnt(
    $owners[0]->recorder,
    $owners[1]->recorder,
    'separate owners retain separate recorders'
);
isnt(
    $owners[0]->functions,
    $owners[1]->functions,
    'separate schemas retain separate SQL routes'
);

my $injected = GPForum::Service::Admin::RoleCatalog->new(
    schema    => $schemas[0],
    functions => $owners[1]->functions,
    recorder  => $owners[1]->recorder,
);
is(
    $injected->functions,
    $owners[1]->functions,
    'an explicitly injected SQL layer is not replaced'
);
is(
    $injected->recorder,
    $owners[1]->recorder,
    'an explicitly injected recorder is not replaced'
);
is(
    GPForum::Service::Admin::RoleCatalog->new(
        schema    => $schemas[0],
        functions => undef
    )->functions,
    undef,
    'an explicit undef keeps the reference test path'
);

done_testing();

1;
