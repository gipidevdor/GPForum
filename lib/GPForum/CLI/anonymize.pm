# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
## no critic (NamingConventions::Capitalization) -- command basename is lowercase
package GPForum::CLI::anonymize;
## use critic
use Mojo::Base 'Mojolicious::Command', -signatures;
use v5.40;
use GPForum::Config;
use GPForum::Service::Operations::Anonymize;
use GPForum::Command::Usage;
our $VERSION = '0.001';
has description => 'Create a scrubbed staging database copy';
has usage =>
"Usage: gpforum anonymize --copy-to gpforum_anon_NAME\nCreates a new database using administrative credentials; never overwrites one.\nUse GPFORUM_ADMIN_DATABASE_DSN, GPFORUM_ADMIN_DATABASE_USER and\nGPFORUM_ADMIN_DATABASE_PASSWORD for a separate administrative login.\n";

sub run ( $self, @arguments ) {
    return GPForum::Command::Usage->help( \*STDOUT, $self->usage )
      if GPForum::Command::Usage->wants_help(@arguments);
    return GPForum::Command::Usage->front_door(
        GPForum::Command::Usage->error(
            'use --copy-to with a new database name',
            $self->usage
        )
    ) if @arguments != 2 || $arguments[0] ne '--copy-to';
    try {
        my $result = GPForum::Service::Operations::Anonymize->new(
            config => GPForum::Config->from_environment )->run( $arguments[1] );
        GPForum::Command::Usage->json( \*STDOUT, $result );
    }
    catch ($error) {
        return GPForum::Command::Usage->front_door(
            GPForum::Command::Usage->failure($error) );
    };
    return 0;
}
1;
