# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Const::Fast;
use Test::More;
use Carp          qw(croak);
use File::Temp    qw(tempdir);
use JSON::MaybeXS qw(decode_json encode_json);
use Mojo::File    qw(path);
use Perl::Critic;
use GPForum::Config;
use GPForum::Command::Doctor;
use GPForum::Service::Password;
use GPForum::Service::Operations::PasswordCalibration;
use GPForum::Service::Discovery::MetadataBuilder;
use GPForum::Service::Discovery::SitemapBuilder;
use GPForum::Service::Discovery::CanonicalUrl;
use GPForum::OS::SystemdNotify;
use Mojolicious::Command::Author::generate::gpforum_service;
use lib 't/lib';
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
our $VERSION = '0.001';

const my $MINIMUM_MEMORY_MIB   => 19;
const my $EXPECTED_DURATION_MS => 192;
const my $LATER_POSITION       => 26;
const my $DEFAULT_ITERATIONS   => 3;
const my $SLOW_DURATION_MS     => 300;
const my $DEFAULT_MEMORY_MIB   => 32;

subtest 'calibration retains a security floor and reports slow hosts' => sub {
    my $calibrator =
      GPForum::Service::Operations::PasswordCalibration->new( measure =>
          sub ( $memory, $iterations ) { return $memory * $iterations * 2; } );
    my $result = $calibrator->run;
    is_deeply(
        $result->{recommendation},
        {
            memory_mib   => $DEFAULT_MEMORY_MIB,
            iterations   => $DEFAULT_ITERATIONS,
            milliseconds => $EXPECTED_DURATION_MS
        },
        'highest measured cost within budget'
    );
    like( encode_json($result), qr/"within_budget":true/msx,
        'native booleans encode as JSON booleans' );
    my ( $output, $exit );
    with_replaced_subs(
        'GPForum::Service::Operations::PasswordCalibration',
        { new => sub { return $calibrator; } },
        sub {
            open my $out, '>', \$output or croak 'cannot capture calibration';
            local *STDOUT = $out;
            $exit = GPForum::Command::Doctor->new->run( '--calibrate-password',
                '--json' );
            close $out or croak 'cannot close calibration capture';
        }
    );
    is( $exit, 0, 'calibration command succeeds' );
    is( decode_json($output)->{status},
        'ok', 'calibration honors the command JSON status contract' );
    $calibrator->measure( sub { return $SLOW_DURATION_MS } );
    $result = $calibrator->run;
    ok( !$result->{within_budget}, 'cannot promise a budget below the floor' );
    is( $result->{status}, 'degraded', 'slow hosts report degraded status' );
    is( $result->{recommendation}{memory_mib},
        $MINIMUM_MEMORY_MIB, 'never weakens memory below the floor' );
    my $hash = GPForum::Service::Password->new(
        memory_mib => $MINIMUM_MEMORY_MIB,
        iterations => 2
    )->hash_password('a long password');
    ok(
        GPForum::Service::Password->new->verify_password(
            'a long password', $hash
        ),
        'existing hashes verify independently of current costs'
    );
};

subtest 'three executable architecture policies inspect code, not comments' =>
  sub {
    my $critic = Perl::Critic->new(
        -profile => q{},
        -only    => 1,
        -include => [
            qw(GPForum::ControllerPersistence GPForum::ServiceContext GPForum::ResultsetBoundary)
        ]
    );
    my $source = q{package GPForum::Controller::Example; use DBIx::Class;};
    is( scalar( $critic->critique( \$source ) ),
        1, 'controller import rejected' );
    $source =
q{package GPForum::Service::Example; use v5.40; sub run ($self, $c) { return $c; }};
    is( scalar( $critic->critique( \$source ) ),
        1, 'service controller parameter rejected' );
    $source =
q{package GPForum::Service::Example; sub run { my ($self, $controller) = @_; return $controller; }};
    is( scalar( $critic->critique( \$source ) ),
        1, 'unpacked controller parameter rejected' );
    $source =
q{package GPForum::Service::Example; sub run { return $_[0]->resultset('User'); }};
    is( scalar( $critic->critique( \$source ) ),
        1, 'service resultset rejected' );
    $source =
        "# preamble\n"
      . q{package GPForum::Infrastructure::Example; sub run { return $_[0]->resultset('User'); }};
    is( scalar( $critic->critique( \$source ) ),
        0, 'infrastructure resultset allowed' );
    $source =
qq{package GPForum::Service::Example;\n# use DBIx::Class; ->resultset('User')\nmy \$text = 'resultset';\n};
    is( scalar( $critic->critique( \$source ) ),
        0, 'comments and strings do not cause violations' );
  };

subtest 'JSON-LD uses public original content and escapes script boundaries' =>
  sub {
    my $builder = GPForum::Service::Discovery::MetadataBuilder->new(
        canonical_url => GPForum::Service::Discovery::CanonicalUrl->new(
            base_url => 'https://forum.test'
        )
    );
    my $thread = {
        thread_id  => 'one',
        slug       => 'one',
        title      => '</script><script>bad()',
        visibility => 'public'
    };
    my $posts = [
        {
            position         => 1,
            post_id          => 'first',
            visibility       => 'public',
            moderation_state => 'visible',
            body             => '<p>Entire original text</p>',
            created_at       => '2026-10-23 12:00:00+00',
            author_username  => 'Ada'
        },
        {
            position         => 2,
            post_id          => 'private',
            visibility       => 'members',
            moderation_state => 'visible',
            body             => 'Secret reply'
        }
    ];
    my $json =
      $builder->thread_metadata( $thread, {}, $posts )->{structured_data};
    unlike( $json, qr/</msx, 'no closing script delimiter can be injected' );
    unlike( $json, qr/Secret/msx, 'member-only replies do not leak' );
    is( decode_json($json)->{'@type'},
        'DiscussionForumPosting', 'correct schema type' );
    is( decode_json($json)->{datePublished},
        '2026-10-23T12:00:00+00:00', 'publication date is valid ISO 8601' );
    is(
        decode_json($json)->{text},
        'Entire original text',
        'entire text is retained'
    );
    $posts->[0]{position} = $LATER_POSITION;
    ok( !$builder->thread_metadata( $thread, {}, $posts )->{structured_data},
        'later pages do not relabel a reply as the original' );
    $thread->{visibility} = 'private';
    ok( !$builder->thread_metadata( $thread, {}, $posts )->{structured_data},
        'private thread has no structured data' );
  };

subtest 'sitemap optional dates use the protocol format' => sub {
    my $builder = GPForum::Service::Discovery::SitemapBuilder->new(
        canonical_url => GPForum::Service::Discovery::CanonicalUrl->new(
            base_url => 'https://forum.test'
        )
    );
    my $xml = $builder->render_xml(
        [
            {
                loc     => 'https://forum.test/t/one',
                lastmod => '2026-10-23 12:00:00+00'
            },
            { loc => 'https://forum.test/legal/terms' },
            { loc => 'https://forum.test/c/one', lastmod => '2026-10-23' },
        ]
    );
    like(
        $xml,
        qr{<lastmod>2026-10-23T12:00:00[+]00:00</lastmod>}msx,
        'PostgreSQL timestamp normalized'
    );
    unlike( $xml, qr{<lastmod></lastmod>}msx,
        'optional date omitted when absent' );
    like(
        $xml,
        qr{<lastmod>2026-10-23</lastmod>}msx,
        'calendar dates remain calendar dates'
    );
};

subtest 'generator creates a coherent quartet and refuses overwrites' => sub {
    my $root = path( tempdir( CLEANUP => 1 ) );
    $root->child('lib/GPForum/Infrastructure')->make_path;
    $root->child('migrations')->make_path;
    $root->child('lib/GPForum/Infrastructure/SqlFunctionCatalogue.pm')
      ->spew("const my %FUNCTION => (\n);\n");
    $root->child('migrations/1049_previous.sql')->spew('-- existing');
    my $generator =
      Mojolicious::Command::Author::generate::gpforum_service->new;
    $generator->run( 'Forum::Widget', '--root', "$root" );
    ok( -f $root->child('lib/GPForum/Service/Forum/Widget.pm'), 'service' );
    ok( -f $root->child('migrations/1050_forum_widget.sql'), 'next migration' );
    ok( -f $root->child('t/integration/postgres-generated-forum_widget.t'),
        'integration test' );
    my $generated_critic = Perl::Critic->new( -profile => '.perlcriticrc' );

    for my $file (
        $root->child('lib/GPForum/Service/Forum/Widget.pm'),
        $root->child('t/integration/postgres-generated-forum_widget.t')
      )
    {
        my @violations = $generated_critic->critique("$file");
        is_deeply( [ map { $_->policy . ': ' . $_->description } @violations ],
            [], "$file respects the repository Perl profile" );
    }

    like(
        $root->child('lib/GPForum/Infrastructure/SqlFunctionCatalogue.pm')
          ->slurp,
        qr/forum_widget[ ]=>/msx,
        'catalogue entry'
    );
    my $before = $root->child('lib/GPForum/Service/Forum/Widget.pm')->slurp;
    my $failed;
    try { $generator->run( 'Forum::Widget', '--root', "$root" ) }
    catch ($error) {
        $failed = $error
    };
    like( $failed, qr/already[ ]exists/msx, 'refuses existing name' );
    is( $root->child('lib/GPForum/Service/Forum/Widget.pm')->slurp,
        $before, 'existing service preserved' );
};

done_testing();

1;
