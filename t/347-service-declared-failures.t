# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Digest::SHA qw(sha256_hex);
use File::Temp  qw(tempdir);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Config;
use GPForum::Service::Attachment::FilesystemStorage;
use GPForum::Service::Attachment::Scanner;
use GPForum::Service::Attachment::Store;
use GPForum::Service::Operations::LocalCache;
use GPForum::Service::Operations::MetricsSnapshot;
use GPForum::Service::Operations::QueryBudget;
use GPForum::Service::Operations::SharedCache;
use GPForum::Service::Outbox::FailureType;
use GPForum::Service::Search::Indexer;
use GPForum::Test::Antivirus;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use GPForum::Test::SearchSchema;

our $VERSION = '0.001';

const my $PNG_BYTES      => pack( 'H*', '89504e470d0a1a0a' ) . 'attachment';
const my $PENDING_KEY    => 'attachments/user-1/attachment-1';
const my $EXCESS_QUERIES => 1000;
const my @OPTIONAL_SECTIONS => qw(
  db_query_stats os os_features os_preflight os_processes os_sockets
  realtime realtime_listener runtime_enforcement security
);

# The WP4 services raise GPForum::X classes where they croaked strings: the
# outbox reads the declared failure_type (X::Unavailable is retried as a
# transport failure, X::Argument, X::Config and X::Check are permanent), and
# the CLI and the controllers can tell a broken call from a configuration
# that is wrong. The messages did not change, so each test that matched one
# still passed when the class was taken away again; these pin the class.
my $types = GPForum::Service::Outbox::FailureType->new;

# The attachment scanner retries what it cannot read or scan. The store
# answers a pending upload without a database; the storage is real.
{
    my $storage = GPForum::Service::Attachment::FilesystemStorage->new(
        root => tempdir( CLEANUP => 1 ) );
    my $unreadable = _error_of(
        sub {
            _scanned( $storage, GPForum::Test::Antivirus->new );
        }
    );
    isa_ok( $unreadable, 'GPForum::X::Unavailable',
        'a stored object that cannot be read' );
    like(
        "$unreadable",
        qr/\Acannot [ ] read [ ] stored [ ] object/msx,
        'with the message it had'
    );
    ok( defined $unreadable->cause, 'and the read error as its cause' );
    is( $types->classify($unreadable),
        'transport', 'which the outbox retries as a transport failure' );
}
{
    my $storage = GPForum::Service::Attachment::FilesystemStorage->new(
        root => tempdir( CLEANUP => 1 ) );
    $storage->write_object( $PENDING_KEY, $PNG_BYTES );
    my $unscanned = _error_of(
        sub {
            _scanned(
                $storage,
                GPForum::Test::Antivirus->new(
                    verdict => {
                        engine => 'Fake 1/1',
                        error  => 'timeout',
                        status => 'error',
                    }
                )
            );
        }
    );
    isa_ok( $unscanned, 'GPForum::X::Unavailable',
        'an antivirus that cannot scan' );
    like(
        "$unscanned",
        qr/antivirus [ ] could [ ] not [ ] scan/msx,
        'with the message it had'
    );
}

# The query budget's hard-fail mode is a check that failed.
{
    my $breach = _error_of(
        sub {
            GPForum::Service::Operations::QueryBudget->new->enforce(
                'thread_view',
                { queries => $EXCESS_QUERIES, transactions => 1 } );
        }
    );
    isa_ok( $breach, 'GPForum::X::Check', 'a query budget breach' );
    is(
        "$breach",
        'query budget exceeded:thread_view:queries',
        'with the message it had'
    );
}

# A rebuild cursor the indexer cannot follow is a broken call.
{
    my $indexer = GPForum::Service::Search::Indexer->new(
        schema => GPForum::Test::SearchSchema->new );
    my $type =
      _error_of(
        sub { $indexer->rebuild_batch( { entity_type => 'bogus' } ) } );
    isa_ok( $type, 'GPForum::X::Argument', 'an unknown rebuild entity type' );
    is( "$type", 'unknown rebuild entity type: bogus', 'named' );
    my $stage = _error_of(
        sub {
            $indexer->rebuild_batch(
                { entity_type => 'thread', stage => 'bogus' } );
        }
    );
    isa_ok( $stage, 'GPForum::X::Argument', 'an unknown rebuild stage' );
    is( "$stage", 'unknown rebuild stage: bogus', 'named' );
}

# The caches: a key that is missing breaks the call, a size or a GlifiStore
# URL that is missing or malformed is configuration.
{
    my %expected = (
        'LocalCache without a key' => [
            'GPForum::X::Argument',
            sub { GPForum::Service::Operations::LocalCache->new->get(q{}) },
        ],
        'LocalCache with no room' => [
            'GPForum::X::Config',
            sub {
                GPForum::Service::Operations::LocalCache->new(
                    max_entries => 0 )->put( 'key', 1 );
            },
        ],
        'SharedCache without a key' => [
            'GPForum::X::Argument',
            sub {
                GPForum::Service::Operations::SharedCache->new->invalidate(q{});
            },
        ],
        'SharedCache without a URL' => [
            'GPForum::X::Config',
            sub {
                GPForum::Service::Operations::SharedCache->connect_required(
                    {} );
            },
        ],
        'SharedCache with a malformed URL' => [
            'GPForum::X::Config',
            sub {
                GPForum::Service::Operations::SharedCache->parse_endpoint(
                    'ftp://cache');
            },
        ],
    );
    for my $case ( sort keys %expected ) {
        my ( $class, $code ) = @{ $expected{$case} };
        isa_ok( _error_of($code), $class, $case );
    }
}

# A metrics scrape without its optional collaborators reports their sections
# empty, not missing: /metrics renders each one as a hash.
{
    my $snapshot = GPForum::Service::Operations::MetricsSnapshot->new->collect;
    is_deeply(
        { map { $_ => $snapshot->{$_} } @OPTIONAL_SECTIONS },
        { map { $_ => {} } @OPTIONAL_SECTIONS },
        'every optional section is an empty hash without its collaborator'
    );
}

done_testing();

# What the scanner does with a pending upload stored under $PENDING_KEY, the
# store's row read without a database.
sub _scanned {
    my ( $storage, $antivirus ) = @_;

    my $pending = {
        attachment_id => 'attachment-1',
        checksum      => sha256_hex($PNG_BYTES),
        deleted_at    => undef,
        media_type    => 'image/png',
        object_key    => $PENDING_KEY,
        scan_status   => 'pending',
        state         => 'uploaded',
    };
    return with_replaced_subs(
        'GPForum::Service::Attachment::Store',
        { find_attachment => sub { return { %{$pending} }; } },
        sub {
            return GPForum::Service::Attachment::Scanner->new(
                antivirus => $antivirus,
                storage   => $storage,
                store     =>
                  GPForum::Service::Attachment::Store->new( schema => {} ),
            )->scan('attachment-1');
        }
    );
}

sub _error_of {
    my ($code) = @_;

    my $failure;
    try {
        $code->();
    }
    catch ($error) {
        $failure = $error;
    };

    return $failure;
}

1;
