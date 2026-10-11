# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';

use GPForum::Command::Secret;
use GPForum::Command::Support::ServiceEnvironment;

our $VERSION = '0.001';

# Walkthrough 4, friction 10: gpforum help secret named
# /etc/gpforum/gpforum.env on macOS, where the file is Homebrew's.

subtest q{gpforum help secret names this host's file} => sub {
    local $ENV{HOMEBREW_PREFIX} = tempdir( CLEANUP => 1 );
    my $file = GPForum::Command::Support::ServiceEnvironment->new->default_file;
    my $help = GPForum::Command::Secret->usage_text;
    like( $help, qr/^ [ ][ ] \Q$file\E $/msx, "the file: $file" );
    if ( $file ne '/etc/gpforum/gpforum.env' ) {
        unlike(
            $help,
            qr{(?<! [\w.-] ) /etc/gpforum/gpforum[.]env}msx,
            q{and not Debian's, on this host}
        );
    }
};

done_testing();

1;
