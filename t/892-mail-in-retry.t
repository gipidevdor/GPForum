# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Test::More;
use lib 'lib';

use GPForum::CLI::mail_in;
use GPForum::Command::Usage;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

# A reply the forum cannot take now is deferred (EX_TEMPFAIL), so the mail
# server delivers it again; one refused for what it is bounces.
my $command = 'GPForum::CLI::mail_in';
my $failure = $GPForum::Command::Usage::EXIT_FAILURE;

ok(
    $command->temporary(
        GPForum::X::Unavailable->new(
            message => 'email reply rate limit exceeded'
        ),
        $failure
    ),
    'the reply rate defers'
);
ok(
    $command->temporary(
        'DBI connect(dbname=gpforum) failed: connection to server on socket'
          . ' "/tmp/.s.PGSQL.5432" failed: No such file or directory',
        $failure
    ),
    'an unreachable database defers'
);
ok( $command->temporary( 'settings', $GPForum::Command::Usage::EXIT_CONFIG ),
    'settings needing the operator defer' );
ok( !$command->temporary( 'email has no valid reply capability', $failure ),
    'a reply without a capability bounces' );
ok(
    !$command->temporary(
        'sender does not match a verified active recipient', $failure
    ),
    'and one from the wrong sender'
);

done_testing();

1;
