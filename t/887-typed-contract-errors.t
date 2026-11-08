# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Mojo::File qw(tempdir);
use Test::Fatal;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::OS::SupervisorProbe;
use GPForum::Service::Forum::PostSigner;
use GPForum::X::Argument;
use GPForum::X::Config;
use GPForum::X::Io;

our $VERSION = '0.001';

# A broken contract or an unusable key is a typed exception, not a bare
# string: a reader catches the class and the outbox reads the failure type
# it declares. The message stays what it was, word for word.

my $directory = tempdir;

subtest 'a signing key the filesystem cannot trust is a Config error' => sub {
    my $key_file = $directory->child('post.key');
    my $signer =
      GPForum::Service::Forum::PostSigner->new( key_file => "$key_file" );
    $signer->key;
    chmod oct '644', $key_file;
    my $loose =
      GPForum::Service::Forum::PostSigner->new( key_file => "$key_file" );
    my $error = exception { $loose->key };
    isa_ok( $error, 'GPForum::X::Config' );
    is(
        "$error",
        'signing key must be a private regular file',
        'it says what it said'
    );
    is( $error->failure_type, 'permanent', 'and retrying cannot help' );
};

subtest 'a probe misused by its caller is an Argument error' => sub {
    my $probe = GPForum::OS::SupervisorProbe->new(
        directory => "$directory",
        arguments => [],
        runner    => sub { return { status => 0, output => q{} }; },
        label     => 'com.gpforum.test.someone-else',
    );
    my $error = exception { $probe->start };
    isa_ok( $error, 'GPForum::X::Argument' );
    is(
        "$error",
        'native probe requires its own label',
        'it says what it said'
    );
};

subtest 'a failed file operation is an Io error the outbox retries' => sub {
    my $error =
      exception { GPForum::X::Io->throw( message => 'cannot write a key' ) };
    isa_ok( $error, 'GPForum::X::Io' );
    is( "$error", 'cannot write a key',    'it stringifies to its message' );
    is( $error->failure_type, 'transient', 'and a retry may succeed' );
    ok( GPForum::X::Io->caught($error), 'a reader can catch the class' );
};

done_testing();

1;
