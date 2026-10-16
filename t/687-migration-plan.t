# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Test::Exception;
use Test::More;

use lib 'lib';

use GPForum::Migration::Plan;

our $VERSION = '0.001';

my $directory = path( tempdir( CLEANUP => 1 ) );
$directory->child('z-schema')->make_path;
$directory->child('a-api')->make_path;
$directory->child('z-schema/002_second.sql')->spew('SELECT 2;');
$directory->child('a-api/010_tenth.sql')->spew('SELECT 10;');
$directory->child('001_first.sql')->spew('SELECT 1;');
$directory->child('README.md')->spew('Not a migration');

my $plan = GPForum::Migration::Plan->new( directory => "$directory" );
is_deeply(
    [ map { $_->{version} } @{ $plan->summary } ],
    [qw(001 002 010)],
    'nested and flat migrations run in numeric order, independent of directory'
);
is_deeply( [ map { $_->{description} } @{ $plan->summary } ],
    [qw(first second tenth)],
    'directories do not change recorded descriptions' );

$directory->child('a-api/2_duplicate.sql')->spew('SELECT 2;');
throws_ok { $plan->files }
'GPForum::X::Config', 'duplicate numeric versions fail before application';
$directory->child('a-api/2_duplicate.sql')->remove;

my $empty = path( tempdir( CLEANUP => 1 ) );
is_deeply( GPForum::Migration::Plan->new( directory => "$empty" )->files,
    [], 'an empty migration directory remains valid' );

done_testing();

1;
