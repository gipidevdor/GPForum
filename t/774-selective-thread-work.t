# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use lib 'lib', 't/lib';
use Const::Fast;
use Test::Mojo;
use Test::More;
use GPForum::Test::CommandIdempotency;
use GPForum::Test::PostFragmentServices;

use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';
const my $OK        => 200;
const my $REACTIONS => 4;

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

sub assert_response_commands( $response, $generated ) {

    my $html = $response->body;
    my @unused =
      grep { index( $html, $_ ) < 0 } @{$generated};
    is_deeply( \@unused, [],
        'every generated controller id is used in the response' );
    my %seen;
    my $dom = $response->dom;
    my @values =
      $dom->find('[name="command_id"]')->map( sub { $_->attr('value') } )->each;
    ok( @values, 'the response retains its available commands' );
    my @invalid =
      grep { !defined $_ || !length $_ || $seen{$_}++ } @values;
    is_deeply( \@invalid, [],
        'every action has a nonempty distinct command id' );
    return;
}

sub permission_page( $pages, $locked, $factory ) {
    my @rows = map {
        +{
            post_id          => $_->[0],
            author_user_id   => $_->[1],
            deleted_at       => $_->[2],
            body_source      => 'body',
            position         => 1,
            visibility       => 'public',
            moderation_state => 'visible',
        }
    } (
        [ 'own',           'member',  undef ],
        [ 'own-deleted',   'member',  '2026-11-02' ],
        [ 'other',         'another', undef ],
        [ 'other-deleted', 'another', '2026-11-02' ]
    );
    return $pages->thread_page(
        page => {
            thread => {
                thread_id => 'thread',
                locked_at => $locked ? '2026-11-02' : undef
            },
            posts => { items => \@rows }
        },
        viewer_user_id      => 'member',
        command_id_factory  => $factory,
        attachments_by_post => {
            own   => [ { attachment_id => 'owned-file' } ],
            other => [ { attachment_id => 'foreign-file' } ]
        },
    );
}

subtest 'fragments prepare only the work they render' => sub {
    my ( %counts, @generated );
    my %summary_methods;
    for my $name (qw(engagement_summary reading_summary)) {
        my $original = GPForum::ViewModel::Forum::Page->can($name);
        $summary_methods{$name} = sub (@arguments) {
            ++$counts{$name};
            return $original->(@arguments);
        };
    }
    my $mint = GPForum::Controller::Forum::Base->can('_new_command_id');
    my $path = $test->app->renderer->get_helper('ui_path');
    $test->app->helper(
        ui_path => sub ( $c, $name, @arguments ) {
            if ( $name eq 'post_react' || $name eq 'post_unreact' ) {
                ++$counts{reaction_paths};
            }
            return $path->( $c, $name, @arguments );
        }
    );
    with_replaced_subs(
        'GPForum::ViewModel::Forum::Page',
        \%summary_methods,
        sub {
            with_replaced_subs(
                'GPForum::Controller::Forum::Base',
                {
                    _new_command_id => sub (@arguments) {
                        my $id = $mint->(@arguments);
                        push @generated, $id;
                        return $id;
                    },
                },
                sub {
                    for my $user ( 'user-1', 'user-2' ) {
                        $test->get_ok("/__reaction/session/$user")
                          ->status_is($OK);
                        $test->get_ok('/t/thread-1')->status_is($OK);
                        for my $fragment ( 0, 1 ) {
                            %counts    = ();
                            @generated = ();
                            $test->get_ok(
                                '/t/thread-1' => (
                                    $fragment ? { 'HX-Request' => 'true' } : {}
                                )
                            )->status_is($OK);
                            assert_response_commands( $test->tx->res,
                                \@generated );
                            is( $counts{reaction_paths} // 0,
                                0,
                                'a warm presentation builds no reaction URLs' );
                            is(
                                $counts{engagement_summary} // 0,
                                $fragment ? 0 : 1,
'only a response with thread controls loads engagement'
                            );
                            is(
                                $counts{reading_summary} // 0,
                                $fragment ? 0 : 1,
'only a response with thread controls loads reading state'
                            );

                            if ($fragment) {
                                $test->element_exists_not('#thread-toolbar');
                                $test->element_exists_not('#reply');
                            }
                        }
                    }
                }
            );
        }
    );

};

sub assert_post_permissions( $page, $locked ) {
    my ( $own, $deleted, $other, $hidden ) = @{ $page->{posts} };
    is(
        $own->{can_edit} // 0,
        $locked ? 0 : 1,
        'lock state still controls editing'
    );
    is(
        $deleted->{can_restore} // 0,
        $locked ? 0 : 1,
        'lock state still controls restoration'
    );
    ok(
        !$own->{can_like} && !$own->{can_react},
        'own posts cannot receive likes or reactions'
    );
    ok(
        $other->{can_like} && $other->{can_react},
        'other live posts retain reactions'
    );
    ok(
        !$hidden->{can_like} && !$hidden->{can_react},
        'deleted posts cannot receive reactions'
    );
    is( $other->{attachments}[0]{delete_command_id},
        q{}, 'foreign attachments get no deletion command' );
    ok( length $other->{report_command_id},
        'reporting remains available on foreign posts' );

    for my $reaction ( @{ $other->{reactions} } ) {
        ok( length $reaction->{command_id},
            'each permitted reaction gets a command' );
    }
    my @forbidden = map { $_->{command_id} } @{ $own->{reactions} },
      @{ $hidden->{reactions} };
    is_deeply(
        \@forbidden,
        [ (q{}) x ( 2 * $REACTIONS ) ],
        'forbidden reactions mint no commands'
    );
    return;
}

subtest 'command factories follow the existing post permissions' => sub {
    my $pages = GPForum::ViewModel::Forum::Page->new;
    for my $locked ( 0, 1 ) {
        my $counter = 0;
        my $page    = permission_page( $pages, $locked,
            sub { return 'command-' . ++$counter; } );
        assert_post_permissions( $page, $locked );
    }
};

done_testing();
1;
