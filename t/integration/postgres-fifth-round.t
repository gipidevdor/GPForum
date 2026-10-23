# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Const::Fast;
use Test::More;
use Carp       qw(croak);
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Mojolicious::Command::Author::generate::gpforum_service;
use English qw(-no_match_vars);
use lib 'lib', 't/lib';
use GPForum::Test::PgDatabase;
use GPForum::Config;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Operations::Anonymize;
use GPForum::Service::Discovery::CanonicalUrl;
use GPForum::Service::Discovery::SitemapBuilder;
use GPForum::Service::Discovery::SitemapPages;
our $VERSION = '0.001';

const my $FIRST_PAGE_ENTRIES => 1003;
if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'run make integration';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh      = $database->dbh;

subtest 'sitemap pages cover more than the former 100-row limit' => sub {
    my ( $category, $author ) = $dbh->selectrow_array(
        'SELECT category_id, author_user_id FROM threads LIMIT 1');
    $dbh->do(
q{INSERT INTO threads(thread_id, category_id, author_user_id, title, slug) }
          . q{SELECT gen_random_uuid(), ?, ?, 'Sitemap thread', 'sitemap-thread' FROM generate_series(1, 1100)},
        undef, $category, $author
    );
    my $builder = GPForum::Service::Discovery::SitemapBuilder->new(
        canonical_url => GPForum::Service::Discovery::CanonicalUrl->new(
            base_url => 'https://forum.test'
        )
    );
    my $pages = GPForum::Service::Discovery::SitemapPages->new(
        schema  => $database->schema,
        builder => $builder
    );
    my $index = $pages->sitemap_index;
    like( $index, qr/sitemapindex/msx,    'index document' );
    like( $index, qr{sitemap-2[.]xml}msx, 'second page indexed' );
    my $functions =
      GPForum::Infrastructure::SqlFunction->for_schema( $database->schema );
    my $before = $functions->row( 'forum_sitemap_count', {} )->{total};
    my ($space) = $dbh->selectrow_array(
        'SELECT space_id FROM categories WHERE category_id = ?',
        undef, $category );
    $dbh->do( 'UPDATE spaces SET deleted_at = now() WHERE space_id = ?',
        undef, $space );
    cmp_ok( $functions->row( 'forum_sitemap_count', {} )->{total},
        '<', $before, 'removed spaces disappear from discovery' );
    $dbh->do( 'UPDATE spaces SET deleted_at = NULL WHERE space_id = ?',
        undef, $space );
    my $first     = $pages->page(1);
    my $next_page = $pages->page(2);
    is( scalar( () = $first =~ /<url>/gmsx ),
        $FIRST_PAGE_ENTRIES, '1000 resources plus legal pages' );
    my @first = $first =~ m{<loc>(.*?)</loc>}gmsx;
    my %seen  = map { $_ => 1 } @first;
    ok( !grep( { $seen{$_} } $next_page =~ m{<loc>(.*?)</loc>}gmsx ),
        'pages do not overlap' );
    my ($private_id) = $dbh->selectrow_array(
        q{SELECT thread_id FROM threads WHERE visibility <> 'public' LIMIT 1});

    if ($private_id) {
        unlike(
            $first . $next_page,
            qr/\Q$private_id\E/msx,
            'private content excluded'
        );
    }
};

subtest 'generated service calls the migrated catalogue contract' => sub {
    my $root = path( tempdir( CLEANUP => 1 ) );
    $root->child('lib/GPForum/Infrastructure')->make_path;
    $root->child('migrations')->make_path;
    $root->child('.perltidyrc')->spew( path('.perltidyrc')->slurp );
    $root->child('lib/GPForum/Infrastructure/SqlFunctionCatalogue.pm')
      ->spew(
        path('lib/GPForum/Infrastructure/SqlFunctionCatalogue.pm')->slurp );
    $root->child('migrations/1000_previous.sql')->spew('-- existing');
    Mojolicious::Command::Author::generate::gpforum_service->new->run(
        'Forum::FifthGenerated', '--root', "$root" );
    $dbh->do(
        $root->child('migrations/1001_forum_fifth_generated.sql')->slurp );
    local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
    my $program =
q{my $schema = GPForum::Schema->connect_from_config(GPForum::Config->from_environment);}
      . q{my $result = GPForum::Service::Forum::FifthGenerated->new(schema => $schema)->execute(undef);}
      . q{print JSON::MaybeXS::encode_json($result);};
    my $pid = open my $output, q{-|}, $EXECUTABLE_NAME,
      '-I' . $root->child('lib'), '-Ilib',
      '-MGPForum::Service::Forum::FifthGenerated',
      '-MGPForum::Config', '-MGPForum::Schema', '-MJSON::MaybeXS', '-e',
      $program;
    defined $pid or croak 'cannot start generated service';
    my $result = do { local $INPUT_RECORD_SEPARATOR = undef; <$output> };
    my $closed = close $output;
    ok( $closed, 'generated service executed in a fresh Perl process' );
    is( $result, '{}',
        'generated SQL result decoded through the generated catalogue entry' );
};

subtest 'anonymize creates a separate copy and leaves its source intact' =>
  sub {
    my $name = 'gpforum_anon_test_' . $PROCESS_ID;
    $dbh->do(q{UPDATE spaces SET description = 'Private space description'});
    $dbh->do(
        q{UPDATE categories SET description = 'Private category description'});
    my $email = $dbh->selectrow_array(
        'SELECT email_normalized FROM users ORDER BY id LIMIT 1');
    my $copy = GPForum::Service::Operations::Anonymize->new(
        config => GPForum::Config->new(
            database_dsn      => $database->dsn,
            database_user     => $ENV{GPFORUM_DATABASE_USER},
            database_password => q{}
        )
    );
    my $result = $copy->run($name);
    is( $result->{status}, 'ok', 'dump, restore, scrub and vacuum completed' );
    is(
        $dbh->selectrow_array(
            'SELECT email_normalized FROM users ORDER BY id LIMIT 1'),
        $email,
        'source email unchanged'
    );
    my $dsn = $database->dsn;
    $dsn =~ s/dbname=[^;]+/dbname=$name/msx;
    my $clone = DBI->connect(
        $dsn, $ENV{GPFORUM_DATABASE_USER},
        q{}, { RaiseError => 1, PrintError => 0 }
    );
    is(
        $clone->selectrow_array(
q{SELECT count(*) FROM users WHERE email_normalized NOT LIKE '%@example.invalid'}
        ),
        0,
        'restored copy has no real email addresses'
    );

    for my $table (qw(spaces categories)) {
        is(
            $clone->selectrow_array(
                "SELECT count(*) FROM $table WHERE description LIKE 'Private%'"
            ),
            0,
            "$table descriptions are scrubbed"
        );
    }
    $clone->disconnect;
    my $error;
    try { $copy->run($name) } catch ($caught) {
        $error = $caught
    };
    like(
        $error,
        qr/already[ ]exists/msx,
        'existing database cannot be overwritten'
    );
    $dbh->do( 'DROP DATABASE ' . $dbh->quote_identifier($name) );
    $dbh->do('ALTER TABLE users ADD COLUMN future_secret varchar(200)');
    $error = undef;
    try { $copy->run($name) } catch ($caught) {
        $error = $caught
    };
    like(
        $error,
        qr/incomplete[ ]copy[ ]was[ ]dropped/msx,
        'an unclassified column aborts copying'
    );
    is(
        $dbh->selectrow_array(
            'SELECT count(*) FROM pg_database WHERE datname = ?', undef,
            $name
        ),
        0,
        'failed copy is removed'
    );
    $dbh->do('ALTER TABLE users DROP COLUMN future_secret');
  };

subtest 'staging copy preserves core shape and removes live identities' => sub {
    $dbh->do(
q{UPDATE post_bodies SET body_source = repeat('Long source text ', 1300)}
    );
    my $users   = $dbh->selectrow_array('SELECT count(*) FROM users');
    my $threads = $dbh->selectrow_array('SELECT count(*) FROM threads');
    my $lengths = $dbh->selectall_arrayref(
        'SELECT char_length(body_source) FROM post_bodies ORDER BY 1');
    my $copy = GPForum::Service::Operations::Anonymize->new(
        config => GPForum::Config->new(
            database_dsn      => $database->dsn,
            database_user     => $ENV{GPFORUM_DATABASE_USER},
            database_password => q{}
        )
    );
    $copy->_scrub($dbh);
    is( $dbh->selectrow_array('SELECT count(*) FROM users'),
        $users, 'user count preserved' );
    is( $dbh->selectrow_array('SELECT count(*) FROM threads'),
        $threads, 'thread count preserved' );
    is_deeply(
        $dbh->selectall_arrayref(
            'SELECT char_length(body_source) FROM post_bodies ORDER BY 1'),
        $lengths,
        'body character lengths preserved'
    );
    is(
        $dbh->selectrow_array(
q{SELECT count(*) FROM users WHERE email_normalized NOT LIKE '%@example.invalid'}
        ),
        0,
        'all addresses use reserved domain'
    );
    is( $dbh->selectrow_array('SELECT count(*) FROM credentials'),
        0, 'credentials removed' );
    is( $dbh->selectrow_array('SELECT count(*) FROM outbox_messages'),
        0, 'no copied mail can leave' );
    is( $dbh->selectrow_array('SELECT count(*) FROM attachments'),
        0, 'no attachment metadata retained' );
};
done_testing();

1;
