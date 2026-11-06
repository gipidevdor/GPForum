# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use lib 'lib', 't/lib';
use Const::Fast;
use Test::Mojo;
use Test::More;
use Test::Fatal                 qw(exception);
use Mojo::Util                  qw(encode);
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use GPForum::Test::LogLines;
use GPForum::Web::PostFragments;
use GPForum::Test::CommandIdempotency;
use GPForum::Test::PostFragmentServices;

our $VERSION = '0.001';
const my $OK              => 200;
const my $SERVER_ERROR    => 500;
const my $REACTION_ROUTES => 8;
const my $REACTIONS       => 4;

my $test     = Test::Mojo->new('GPForum');
my $services = GPForum::Test::PostFragmentServices->new;
for my $helper (
    qw(gp_category_reader gp_thread_reader gp_thread_detail_reader
    gp_thread_composer gp_thread_store gp_post_reader gp_post_composer
    gp_post_store gp_thread_read_state gp_mention_store gp_mention_reader
    gp_bookmark_store gp_bookmark_folders gp_like_store gp_reaction_store
    gp_reply_links gp_thread_tags gp_subscription_store gp_notification_dispatcher
    gp_search_service gp_rate_limiter gp_suspension_store gp_attachment_store)
  )
{
    $test->app->helper( $helper => sub { return $services; } );
}
$test->app->helper(
    gp_command_idempotency => sub {
        return GPForum::Test::CommandIdempotency->new;
    }
);
my $routes = $test->app->routes;
$routes->get('/__reaction/session/:user')->to(
    cb => sub ($c) {
        $c->session( user_id => $c->param('user') );
        return $c->render( text => 'ready' );
    }
);

subtest 'command generator failures propagate; read failures still degrade' =>
  sub {
    my $pages     = GPForum::ViewModel::Forum::Page->new;
    my $logger    = GPForum::Test::LogLines->new;
    my $generated = 0;
    my %input     = (
        user_id            => 'user-2',
        thread             => { thread_id => 'thread-1' },
        bookmark_store     => $services,
        subscription_store => $services,
        logger             => $logger,
        command_id_factory =>
          sub { ++$generated; die "command generator failed\n"; },
    );
    like(
        exception { $pages->engagement_summary(%input) },
        qr/command[ ]generator[ ]failed/msx,
        'a command failure is not converted into a successful degraded summary'
    );
    is( $generated, 1, 'the failed factory is called once' );
    is_deeply( $logger->lines, [],
        'command failure is not mislabeled as a failed read' );
    $generated = 0;
    with_replaced_subs(
        'GPForum::ViewModel::Forum::Page',
        {
            _engagement_lookup => sub { die "read failed\n"; },
        },
        sub {
            my $result = $pages->engagement_summary( %input,
                command_id_factory =>
                  sub { ++$generated; return 'report-only'; } );
            is( $result->{status}, 'degraded',
                'actual read failure retains its fallback' );
            is( $generated, 1,
'unavailable state generates only the independent report command'
            );
            is( $result->{thread_report_command_id},
                'report-only', 'reporting remains usable' );
            is( $result->{subscribe_command_id},
                q{}, 'unknown subscription state gets no command' );
            like(
                exception { $pages->engagement_summary(%input) },
                qr/command[ ]generator[ ]failed/msx,
                'a command failure also propagates after a read failure'
            );
            like(
                $logger->lines->[0],
                qr/engagement[ ]summary[ ]degraded:[ ]read[ ]failed/msx,
                'actual read failure is logged'
            );
        }
    );
  };

subtest 'HTTP response fails instead of serving empty action commands' => sub {
    $test->get_ok('/__reaction/session/user-2')->status_is($OK);
    my $summary = GPForum::ViewModel::Forum::Page->can('engagement_summary');
    with_replaced_subs(
        'GPForum::ViewModel::Forum::Page',
        {
            engagement_summary => sub ( $self, %input ) {
                return $summary->(
                    $self, %input,
                    command_id_factory =>
                      sub { die "command generator failed\n"; }
                );
            },
        },
        sub {
            $test->get_ok('/t/thread-1')->status_is($SERVER_ERROR);
            $test->element_exists_not('#thread-toolbar form');
        }
    );
    $test->get_ok('/t/thread-1')->status_is($OK);
    $test->element_exists('#thread-toolbar input[name="command_id"][value]');
};

sub fragment_bytes($parts) {
    return length encode(
        'UTF-8', join q{},
        values %{ $parts->{paths} },
        map { $parts->{$_} } grep { $_ ne 'paths' } keys %{$parts}
    );
}

subtest 'reaction paths are lazy and remain within the entry size bound' =>
  sub {
    my $c        = $test->app->build_controller;
    my $paths    = 0;
    my $original = $test->app->renderer->get_helper('ui_path');
    $test->app->helper(
        ui_path => sub ( $controller, $name, @arguments ) {
            if ( $name eq 'post_react' || $name eq 'post_unreact' ) {
                ++$paths;
            }
            return $original->( $controller, $name, @arguments );
        }
    );
    my $cache = GPForum::Web::PostFragments->new;
    my $post =
      { post_id => 'post-review', position => 1, author_user_id => 'author' };
    my $base = $cache->render( $c, $post );
    is( $paths, 0, 'ineligible cold render builds no reaction paths' );
    ok(
        !exists $base->{paths}{'post_react:heart'},
        'base entry contains no unused reaction paths'
    );
    my $expanded = $cache->render( $c, { %{$post}, can_react => 1 } );
    is( $paths, $REACTION_ROUTES,
        'an eligible reader lazily builds both routes for each reaction' );
    ok(
        exists $expanded->{paths}{'post_react:heart'},
        'expanded presentation has its reaction route'
    );
    ok(
        !exists $base->{paths}{'post_react:heart'},
        'expansion does not mutate the base object'
    );
    $paths = 0;
    $cache->render( $c, { %{$post}, can_react => 1 } );
    $cache->render( $c, $post );
    is( $paths, 0,
'later eligible and ineligible readers reuse static paths without rebuilding'
    );
    is( scalar keys %{ $cache->entries },
        1, 'permission state is not part of the shared cache key' );
    ok( !exists $expanded->{can_react},
        'permission state is never stored in the presentation' );

    my $bounded =
      GPForum::Web::PostFragments->new( max_bytes => fragment_bytes($base) );
    $bounded->render( $c, $post );
    is( scalar keys %{ $bounded->entries },
        1, 'the base entry fits and is cached before expansion' );
    my $larger = $bounded->render( $c, { %{$post}, can_react => 1 } );
    ok(
        exists $larger->{paths}{'post_react:heart'},
        'oversized expansion remains usable for this render'
    );

    for my $entry ( values %{ $bounded->entries } ) {
        cmp_ok( fragment_bytes($entry), '<=', $bounded->max_bytes,
            'stored entry does not exceed its size budget' );
        ok(
            !exists $entry->{paths}{'post_react:heart'},
            'oversized paths are not added to the cached base'
        );
    }
  };

done_testing();
1;
