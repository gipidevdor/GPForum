# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- Mojolicious command basenames are lowercase
package GPForum::CLI::attachment_import;
## use critic

use Mojo::Base 'Mojolicious::Command', -signatures;
use v5.40;
use GPForum::Command::Usage;
use GPForum::Config;
use GPForum::Schema;
use GPForum::Service::Attachment::FilesystemStorage;
use GPForum::Service::Attachment::LegacyImport;
use GPForum::Service::Attachment::PostgresStorage;

our $VERSION = '0.001';
has description => 'Import legacy uploads into PostgreSQL';
has usage => "Usage: gpforum attachment-import [--apply]\n"
  . "Without --apply, validates live legacy files without writing.\n"
  . "With --apply, copies originals and variants to PostgreSQL; never removes source files.\n";

sub run ( $self, @arguments ) {
    return GPForum::Command::Usage->help( \*STDOUT, $self->usage )
      if GPForum::Command::Usage->wants_help(@arguments);
    my $apply = @arguments == 1 && $arguments[0] eq '--apply';
    return GPForum::Command::Usage->front_door(
        GPForum::Command::Usage->error(
            'use --apply or no options',
            $self->usage
        )
    ) if @arguments && !$apply;
    try {
        my $config = GPForum::Config->from_environment;
        my $schema = GPForum::Schema->connect_from_config($config);
        my $result = GPForum::Service::Attachment::LegacyImport->new(
            storage => GPForum::Service::Attachment::PostgresStorage->new(
                schema => $schema
            ),
            filesystem => GPForum::Service::Attachment::FilesystemStorage->new(
                root => $config->attachment_root
            ),
        )->run($apply);
        GPForum::Command::Usage->json( \*STDOUT, $result );
    }
    catch ($error) {
        return GPForum::Command::Usage->front_door(
            GPForum::Command::Usage->failure($error) );
    };
    return 0;
}

1;
