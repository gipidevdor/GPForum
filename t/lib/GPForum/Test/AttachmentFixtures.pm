# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::AttachmentFixtures;

use v5.40;

use Const::Fast;
use File::Temp qw(tempdir);

use GPForum::Infrastructure::Id;
use GPForum::Service::Attachment::FilesystemStorage;
use GPForum::Service::Attachment::IntentBuilder;
use GPForum::Service::Attachment::Store;
use GPForum::Service::Attachment::UploadPipeline;
use GPForum::Test::FixedClock;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

const my $PUBLIC_POST_SQL => join q{ },
  'SELECT post_id, author_user_id FROM posts',
  q{WHERE deleted_at IS NULL AND hidden_at IS NULL},
  q{AND visibility = 'public' ORDER BY post_id LIMIT 1};

# An upload pipeline over a seeded PostgreSQL database of its own and real
# filesystem storage, with a public post and its author to upload to (ADR
# 0177: the store has no other path). Returns the pipeline, its store,
# storage and clock, the database, and the post and its author.
sub build {
    my ( undef, %input ) = @_;

    my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
    my ( $post_id, $owner ) = $database->dbh->selectrow_array($PUBLIC_POST_SQL);
    my $clock = GPForum::Test::FixedClock->new;
    my $store = GPForum::Service::Attachment::Store->new(
        schema     => $database->schema,
        clock      => $clock,
        id_service => GPForum::Infrastructure::Id->new,
    );
    my $storage = GPForum::Service::Attachment::FilesystemStorage->new(
        root => tempdir( CLEANUP => 1 ) );

    return {
        clock    => $clock,
        database => $database,
        owner    => $owner,
        post_id  => $post_id,
        store    => $store,
        storage  => $storage,
        pipeline => GPForum::Service::Attachment::UploadPipeline->new(
            antivirus      => $input{antivirus},
            intent_builder => GPForum::Service::Attachment::IntentBuilder->new(
                clock      => $clock,
                id_service => GPForum::Infrastructure::Id->new,
            ),
            storage => $storage,
            store   => $store,
        ),
    };
}

1;
