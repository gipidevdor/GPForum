# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Forum::Base;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Base', -async_await;
use v5.40;
use Mojo::Promise;

use GPForum::Infrastructure::Row  qw(column_of);
use GPForum::Infrastructure::Text qw(trimmed);
use GPForum::Service::Forum::BodyLength;
use GPForum::Service::Forum::BodyRenderer;
use GPForum::Web::Access;
use GPForum::Web::ClientAddress;
use GPForum::Web::ForumAccess;
use GPForum::Web::Guard;
use GPForum::Web::Responder;
use GPForum::Web::RequestPreference;
use GPForum::Web::SecurityEvent;

our $VERSION = '0.001';

const my $HTTP_OK          => 200;
const my $HTTP_CREATED     => 201;
const my $HTTP_BAD_REQUEST => 400;
const my $HTTP_FORBIDDEN   => 403;

sub forum_access ($self) {
    return GPForum::Web::ForumAccess->new( config => $self->gp_config );
}

async sub visible_thread ($self) {
    my $thread = (
        await $self->call_p(
            $self->gp_thread_detail_reader, 'find_thread',
            $self->param('thread_id'),      $self->gp_forum_viewer
        )
    );

    if ( !$thread ) {
        $self->not_found('thread not found');
        return undef;
    }

    return $thread;
}

sub attachments_for_posts ( $self, $posts ) {
    if ( !@{$posts} ) {
        return {};
    }

    my $by_post;
    try {
        $by_post = $self->gp_attachment_store->attachments_for_posts(
            [ map { $self->_column( $_, 'post_id' ) } @{$posts} ],
            {
                viewer         => $self->gp_forum_viewer,
                viewer_user_id => $self->current_user_id,
            },
        );
    }
    catch ($error) {
        $self->app->log->warn("attachment listing degraded: $error");
        return {};
    };

    return $by_post || {};
}

async sub create_report ( $self, $input ) {
    my $reason  = trimmed( $self->param('reason') );
    my $details = trimmed( $self->param('details') );
    my $errors  = $self->forum_access->report_field_errors( $reason, $details );
    if ( %{$errors} ) {
        return { ok => 0, errors => $errors };
    }

    my $result = (
        await $self->call_p(
            $self->gp_community_workflow,
            'create_report',
            {
                command_id       => $self->command_id_param,
                reporter_user_id => $input->{reporter_user_id},
                target_type      => $input->{target_type},
                target_id        => $input->{target_id},
                reason           => $reason,
                details          => $details,
            }
        )
    );
    if ( $result->{ok} ) {
        return { ok => 1, report => $result->{stored} };
    }
    if ( $self->forum_access->is_unavailable($result) ) {
        return { ok => 0, system_error => 1 };
    }

    return {
        error  => $result->{error},
        errors => $result->{errors},
        ok     => 0,
        status => $result->{status},
    };
}

async sub report_response ( $self, $result, $thread_id, $post_id ) {
    if ( !$result->{ok} ) {
        return $self->_report_error_response($result);
    }
    if ( $self->wants_json ) {
        return $self->_report_json_response($result);
    }

    my $url = $self->url_for( 'thread', thread_id => $thread_id );
    if ($post_id) {
        $url->fragment( 'post-' . $post_id );
    }

    return (
        await $self->await_p(
            $self->_html_success( $self->forum_access->reported_status, $url )
        )
    );
}

async sub profilereport_response ( $self, $result, $username ) {
    if ( !$result->{ok} ) {
        return $self->_report_error_response($result);
    }
    if ( $self->wants_json ) {
        return $self->_report_json_response($result);
    }

    return (
        await $self->await_p(
            $self->_html_success(
                $self->forum_access->reported_status,
                $self->url_for( 'profile', username => $username ),
            )
        )
    );
}

sub _report_error_response ( $self, $result ) {
    if ( $self->forum_access->is_unavailable($result) ) {
        return $self->_service_unavailable;
    }
    if ( ( $result->{status} || q{} ) eq 'conflict' ) {
        return $self->_conflict( $result->{error} );
    }

    return $self->_bad_request( $result->{errors} );
}

sub _report_json_response ( $self, $result ) {
    return $self->render(
        json =>
          $self->gp_forum_view_model->report_response( $result->{report}, ),
        status => $HTTP_OK,
    );
}

async sub created_thread_response ( $self, $stored ) {
    if ( $self->wants_json ) {
        return $self->render(
            json =>
              $self->gp_forum_view_model->created_thread_response($stored),
            status => $HTTP_CREATED,
        );
    }

    if ( ( $self->param('after_publish') // q{} ) eq 'attachment' ) {
        my $post_id = $self->_column( $stored->{post}, 'post_id' );
        if ($post_id) {
            return (
                await $self->await_p(
                    $self->_html_success(
                        $self->forum_access->thread_created_status,
                        $self->url_for(
                            'post_attachment_form', post_id => $post_id
                        )
                    )
                )
            );
        }
    }

    return (
        await $self->await_p(
            $self->_html_success(
                $self->forum_access->thread_created_status,
                $self->url_for(
                    'thread',
                    thread_id =>
                      $self->_column( $stored->{thread}, 'thread_id' ),
                ),
            )
        )
    );
}

sub updated_thread_response ( $self, $stored ) {
    return $self->_thread_change_response( 'updated', $stored );
}

sub moved_thread_response ( $self, $stored ) {
    return $self->_thread_change_response( 'moved', $stored );
}

async sub deleted_thread_response ( $self, $stored ) {
    if ( $self->wants_json ) {
        return $self->render(
            json =>
              $self->gp_forum_view_model->deleted_thread_response($stored),
            status => $HTTP_OK,
        );
    }

    my $status      = $self->forum_access->thread_deleted_status;
    my $category_id = $self->_column( $stored->{thread}, 'category_id' );
    if ( $self->wants_fragment ) {
        return (
            await $self->await_p(
                $self->thread_fragment( $status, header => 1 ) ) );
    }
    if ($category_id) {
        return (
            await $self->await_p(
                $self->_html_success(
                    $status,
                    $self->url_for( 'category', category_id => $category_id ),
                )
            )
        );
    }

    return (
        await $self->await_p(
            $self->_html_success( $status, $self->url_for('categories') )
        )
    );
}

sub restored_thread_response ( $self, $stored ) {
    return $self->_thread_change_response( 'restored', $stored );
}

async sub created_post_response ( $self, $stored ) {
    if ( $self->wants_json ) {
        return $self->render(
            json => $self->gp_forum_view_model->created_post_response($stored),
            status => $HTTP_CREATED,
        );
    }

    my $thread_id = $self->param('thread_id');
    my $post_id   = $self->_column( $stored->{post}, 'post_id' );
    my $status    = $self->forum_access->post_created_status;
    if ( $self->wants_fragment ) {
        return (
            await $self->await_p(
                $self->thread_fragment( $status, post_id => $post_id )
            )
        );
    }

    return (
        await $self->await_p(
            $self->_html_success(
                $status,
                $self->url_for( 'thread', thread_id => $thread_id )
                  ->fragment( 'post-' . $post_id ),
            )
        )
    );
}

sub updated_post_response ( $self, $stored ) {
    return $self->_post_change_response( 'updated', $stored );
}

sub deleted_post_response ( $self, $stored ) {
    return $self->_post_change_response( 'deleted', $stored );
}

sub restored_post_response ( $self, $stored ) {
    return $self->_post_change_response( 'restored', $stored );
}

async sub read_marker_response ( $self, $marked ) {
    if ( $self->wants_json ) {
        return $self->render(
            json   => $self->gp_forum_view_model->read_marker_response($marked),
            status => $HTTP_OK,
        );
    }

    return (
        await $self->await_p(
            $self->_html_success(
                $self->forum_access->read_marked_status,
                $self->url_for(
                    'thread', thread_id => $marked->{read_state}{thread_id},
                ),
            )
        )
    );
}

sub bookmark_action_response ( $self, $status, $bookmark ) {
    return $self->_engagement_response( 'bookmark', $status, $bookmark );
}

# A like answers with the post as the list now lists it (the fragment),
# or with the thread page at the post.
sub reaction_action_response ( $self, $status, $reaction ) {
    return $self->_engagement_response( 'reaction', $status, $reaction, 1 );
}

sub like_action_response ( $self, $status, $like ) {
    return $self->_engagement_response( 'like', $status, $like, 1 );
}

sub subscription_action_response ( $self, $status, $subscription ) {
    return $self->_engagement_response( 'subscription', $status,
        $subscription );
}

# Each public action keeps its name; only the response orchestration is shared.
async sub _thread_change_response ( $self, $action, $stored ) {
    my $response = $action . '_thread_response';
    if ( $self->wants_json ) {
        return $self->render(
            json   => $self->gp_forum_view_model->$response($stored),
            status => $HTTP_OK,
        );
    }
    my $status_method = 'thread_' . $action . '_status';
    my $status        = $self->forum_access->$status_method;
    if ( $self->wants_fragment ) {
        return await $self->await_p(
            $self->thread_fragment( $status, header => 1 ) );
    }
    return await $self->await_p(
        $self->_html_success(
            $status,
            $self->url_for(
                'thread',
                thread_id => $self->_column( $stored->{thread}, 'thread_id' )
            )
        )
    );
}

async sub _post_change_response ( $self, $action, $stored ) {
    my $response = $action . '_post_response';
    if ( $self->wants_json ) {
        return $self->render(
            json   => $self->gp_forum_view_model->$response($stored),
            status => $HTTP_OK,
        );
    }
    my $thread_id = $self->_column( $stored->{post}, 'thread_id' );
    my $post_id =
        $action ne 'deleted'
      ? $self->_column( $stored->{post}, 'post_id' )
      : undef;
    my $status_method = 'post_' . $action . '_status';
    my $status        = $self->forum_access->$status_method;
    my $location      = $self->url_for( 'thread', thread_id => $thread_id );
    if ( $action ne 'deleted' ) { $location->fragment( 'post-' . $post_id ); }
    return await $self->await_p( $self->_html_success( $status, $location ) );
}

async sub _engagement_response ( $self, $action, $status, $result,
    $at_post = 0 )
{
    my $response = $action . '_response';
    if ( $self->wants_json ) {
        return $self->render(
            json =>
              $self->gp_community_view_model->$response( $status, $result ),
            status => $HTTP_OK,
        );
    }
    my $thread_id = $at_post ? $result->{thread_id} : $self->param('thread_id');
    my $location  = $self->url_for( 'thread', thread_id => $thread_id );
    if ($at_post) { $location->fragment( 'post-' . $self->param('post_id') ); }
    return await $self->await_p( $self->_html_success( $status, $location ) );
}

sub render_payload ( $, $input ) {
    return GPForum::Web::Responder->new->payload($input);
}

# Cache options for a public page, or none: a page past the first (with a
# cursor) is not cached, since any string is a cursor and each would mint an
# entry. The key names the limit the page lists by, a thread list's page size
# unless the page passes the one it uses, and the path the route writes for
# the request unless the page passes the one that names it (a thread under
# any slug is one page). It named the path as typed: the router reads
# /c/ID/ and /c/ID with a letter written as an escape as /c/ID, and each
# spelling minted an entry of its own.
sub public_cache_options ( $self, $name, $tags, $options = {} ) {
    return undef if length( $self->param('after') // q{} );

    my $path = $options->{path} // $self->url_for->path->to_string;
    return $self->forum_access->public_cache_options(
        {
            limit  => $options->{limit} // $self->list_page_limit,
            locale => $self->ui_locale,
            name   => $name,
            path   => "$path",
            tags   => $tags,
            theme  => $self->ui_theme,
        }
    );
}

# Answers from the public cache before the page's queries run, when the
# visitor is anonymous, wants HTML and the page is cached: a hit used to
# spare only the template, after every query had run. True when answered.
# On a miss the options come back marked, so the page must hand these same
# options to render_payload: its render then stores without a second lookup.
sub served_from_public_cache ( $self, $options ) {
    return 0 if !$options;
    return 0 if GPForum::Web::RequestPreference->wants_json($self);
    return 0 if $self->wants_fragment;

    return $self->gp_public_http_cache->serve_cached( $self, $options );
}

async sub _html_success ( $self, $status, $location ) {
    if ( $self->wants_fragment ) {
        return ( await $self->await_p( $self->thread_fragment($status) ) )
          if length( $self->param('thread_id') // q{} );
        return ( await $self->await_p( $self->post_fragment($status) ) )
          if length( $self->param('post_id') // q{} );
    }

    $self->set_success_flash( $self->forum_access->write_flash_key($status) );

    return $self->redirect_to($location);
}

sub wants_fragment ($self) {
    return GPForum::Web::RequestPreference->wants_fragment($self);
}

# What a write changed on the thread page, for the page to swap in place
# when it asked from its script (HX-Request): the toolbar, where the toolbar
# asked; when the write created a post, that post for the list and a
# composer with a fresh command id for its place; when it changed the
# thread itself (header), the page's head, with the breadcrumbs, the notices
# and the composer's place out of band, since each may have changed. With
# any, the message the redirect would have flashed, for its place. A
# browser without the script gets the redirect as before.
async sub thread_fragment ( $self, $status, %option ) {
    my $viewer = $self->gp_forum_viewer;
    my $thread = (
        await $self->call_p(
            $self->gp_thread_detail_reader, 'find_thread',
            $self->param('thread_id'),      $viewer
        )
    );
    if ( !$thread ) {
        return $self->not_found('thread not found');
    }

    my $post =
      defined $option{post_id}
      ? (
        await $self->call_p(
            $self->gp_post_reader,
            'find_listed_post',
            {
                post_id      => $option{post_id},
                thread_id    => $self->param('thread_id'),
                viewer_scope => $self->gp_thread_detail_reader->post_scope(
                    $viewer, $thread
                ),
                viewer_user_id => $self->current_user_id,
            }
        )
      )
      : undef;
    my $page = {
        ok     => 1,
        thread => $thread,
        posts  => { items => [ $post // () ], next_cursor => undef },
    };

    my $fragment =
      $option{header}
      ? { breadcrumbs => 1, composer => 1, header => 1, notices => 1 }
      : defined $option{post_id} ? { composer => 1, posts => $post ? 1 : 0 }
      :                            { toolbar => 1 };

    return $self->render(
        template => 'forum/thread_fragment',
        %{
            (
                await $self->await_p(
                    $self->thread_page_payload_p(
                        $page, $self->current_user_id,
                        fragment => $fragment
                    )
                )
            )
        },
        flash_message =>
          $self->i18n( $self->forum_access->write_flash_key($status) ),
        fragment => $fragment,
        status   => $HTTP_OK,
    );
}

# What a write changed on one post, for the page to swap in place when it
# asked from its script (HX-Request): the post as the list would now list
# it, edited, hidden or restored, and the message the redirect would have
# flashed. The post's thread is read first, since the post's own state no
# longer says which one it is in: a post the viewer may not list sends them
# the redirect.
async sub post_fragment ( $self, $status ) {
    my $viewer  = $self->gp_forum_viewer;
    my $post_id = $self->param('post_id');
    my $located =
      ( await $self->call_p( $self->gp_post_reader, 'find_post', $post_id ) );
    my $thread =
      $located
      ? (
        await $self->call_p(
            $self->gp_thread_detail_reader,          'find_thread',
            $self->_column( $located, 'thread_id' ), $viewer
        )
      )
      : undef;
    if ( !$thread ) {
        return $self->not_found('post not found');
    }

    my $post = (
        await $self->call_p(
            $self->gp_post_reader,
            'find_listed_post',
            {
                post_id      => $post_id,
                thread_id    => $self->_column( $thread, 'thread_id' ),
                viewer_scope => $self->gp_thread_detail_reader->post_scope(
                    $viewer, $thread
                ),
                viewer_user_id => $self->current_user_id,
            }
        )
    );
    if ( !$post ) {
        return $self->not_found('post not found');
    }

    my $page = {
        ok     => 1,
        thread => $thread,
        posts  => { items => [$post], next_cursor => undef },
    };

    return $self->render(
        template => 'forum/thread_fragment',
        %{
            (
                await $self->await_p(
                    $self->thread_page_payload_p(
                        $page, $self->current_user_id,
                        fragment => { posts => 1 }
                    )
                )
            )
        },
        flash_message =>
          $self->i18n( $self->forum_access->write_flash_key($status) ),
        fragment => { posts => 1 },
        status   => $HTTP_OK,
    );
}

# The thread page's payload for a page the detail reader returned, with a
# command id for each action the reader may take. The reads it makes once
# it has the posts -- likes, reply targets, tags, attachment links, and a
# member's bookmark, subscription and read state -- are read in one
# statement first, and each store takes its rows from it
# (GPForum::Service::Forum::ThreadPageReads).
#
# A store that cannot even be made leaves the reads to themselves: each then
# meets it as it did, and degrades or fails the page as it did.
#
# Optional fragment parts are selected by server code. They suppress unused
# page metadata, move-category choices and composer setup; they never suppress
# authentication, thread/post visibility or per-post action permissions.
#
# The page's reads, the author's move choices and the bodies' rendering
# need nothing of one another, so they run together: the rendering's worker
# turns the bodies while the statements are out.
async sub thread_page_payload_p ( $self, $page, $user_id, %option ) {
    my $parts    = $option{fragment};
    my $renderer = GPForum::Service::Forum::BodyRenderer->new(
        math_plugins => $self->ui_integration_plugins );
    my $answers;
    ( $answers, $option{move_categories}, my $rendered ) =
      map { $_->[0] } await $self->await_p(
        Mojo::Promise->all(
            $self->_page_answers_p( $page, $user_id, $parts ),
            $self->_move_categories_p( $page, $user_id, $parts ),
            $renderer->render_many_p(
                [
                    map { $self->_column( $_, 'body_source' ) }
                      @{ $page->{posts}{items} || [] }
                ],
                $self->stash('gp_db_query_stats_token')
            ),
        )
      );
    return GPForum::Service::Forum::BodyRenderer->with_rendered(
        $rendered,
        sub {
            return GPForum::Infrastructure::SqlFunction->answering(
                $answers,
                sub {
                    return $self->_thread_page_payload( $page, $user_id,
                        %option );
                }
            );
        }
    );
}

async sub _page_answers_p ( $self, $page, $user_id, $parts ) {
    my $reads;
    try { $reads = $self->gp_thread_page_reads; }
    catch ($error) { return {}; };
    return {} if !$reads;
    my $input = {
        page           => $page,
        thread_id      => $self->param('thread_id'),
        viewer_user_id => $user_id,
        omit_thread    => $parts && !$parts->{header} && !$parts->{toolbar},
    };
    my $answers = await $self->call_p( $reads, 'answers', { %{$input} } );
    return $answers if keys %{$answers} || !$reads->functions;

    return await $self->call_p( $reads, 'individual_answers', { %{$input} } );
}

async sub _move_categories_p( $self, $page, $user_id, $parts ) {

    # Move choices are shown only to the author. Fetch them before entering
    # the synchronous, data-only answer scope used by the view models.
    my $tools = !$parts || $parts->{header} || $parts->{toolbar};
    my $moves =
         $tools
      && $user_id
      && ( $self->_column( $page->{thread}, 'author_user_id' ) // q{} ) eq
      $user_id
      && !$self->_column( $page->{thread}, 'locked_at' )
      && !$self->_column( $page->{thread}, 'deleted_at' );
    return $moves
      ? await $self->call_p( $self->gp_category_reader, 'list_categories',
        { viewer => $self->gp_forum_viewer } )
      : [];
}

sub _thread_page_payload ( $self, $page, $user_id, %option ) {

    my $parts        = $option{fragment};
    my $controls     = $self->_thread_page_controls( $page, $user_id, $parts );
    my $thread_tools = $controls->{thread_tools};
    my $command      = $controls->{command};
    my $move_command_id = $controls->{move_command_id};
    my $posts           = $page->{posts}{items};
    my $post_ids        = [ $self->_post_ids($posts) ];
    my $attachments     = $self->attachments_for_posts($posts);
    return $self->gp_forum_view_model->thread_page(
        command_id_factory        => $command,
        thread_command_id_factory => $controls->{thread_actions} ? $command
        : undef,
        attachments_by_post => $attachments,
        engagement          => $thread_tools
        ? $self->gp_forum_view_model->engagement_summary(
            command_id_factory => $command,
            bookmark_store     => $self->gp_bookmark_store,
            logger             => $self->app->log,
            subscription_store => $self->gp_subscription_store,
            thread             => $page->{thread},
            user_id            => $user_id
          )
        : { authenticated => $user_id ? 1 : 0 },
        reading => $thread_tools ? $self->gp_forum_view_model->reading_summary(
            command_id_factory => $command,
            posts              => $posts,
            read_state         => $self->gp_thread_read_state,
            thread_id          => $self->param('thread_id'),
            user_id            => $user_id
          )
        : { authenticated => $user_id ? 1 : 0 },
        omit_metadata    => $parts ? 1 : 0,
        metadata_builder => $self->gp_metadata_builder,
        page             => $page,
        reply_command_id => $controls->{reply_command_id},
        likes            => $self->_post_likes( $post_ids, $user_id ),
        reactions        => $self->_post_reactions( $post_ids, $user_id ),
        reply_targets    => $self->_reply_targets($post_ids),
        thread_tags      => $thread_tools
        ? $self->gp_tags_for_threads( [ $page->{thread} ] )
        : {},
        move_thread_command_id => $move_command_id,
        categories => length $move_command_id ? $option{move_categories}
          // $self->gp_category_reader->list_categories(
            { viewer => $self->gp_forum_viewer }
          )
        : [],
        viewer_user_id      => $user_id,
        listed_members      => $self->_listed_members($user_id),
        can_moderate_thread => $self->_can_moderate_thread,
    );
}

# Server-selected parts control presentation work only. Post visibility and
# action permissions are still evaluated for every returned post.
sub _thread_page_controls ( $self, $page, $user_id, $parts ) {
    $parts //= { header => 1, toolbar => 1, composer => 1, notices => 1 };
    my $tools   = $parts->{header} || $parts->{toolbar};
    my $command = sub { return $self->_new_command_id; };
    my $writable =
         $user_id
      && !$self->_column( $page->{thread}, 'locked_at' )
      && !$self->_column( $page->{thread}, 'deleted_at' );
    my $move = $tools
      && $writable ? $self->_thread_edit_command_id( $page, $user_id ) : q{};
    my $reply = $parts->{composer} && $writable ? $command->() : q{};
    if ( length $reply ) {
        $self->fresh_composer_draft( 'reply', $reply,
            thread_id => $self->param('thread_id') );
        $self->_quote_into_composer( $page->{posts}{items} );
        $self->_reply_into_composer( $page->{posts}{items} );
    }
    return {
        command          => $command,
        thread_tools     => $tools,
        thread_actions   => $tools || $parts->{notices},
        move_command_id  => $move,
        reply_command_id => $reply
    };
}

# The likes on the page's posts, counted for every reader, with whether the
# viewer gave one. A signed-in reader's like form under each post has a
# command id of its own (like_command_ids).
sub _post_likes ( $self, $post_ids, $user_id ) {
    return {} if !@{$post_ids};
    return $self->gp_like_store->summary_for_posts( $post_ids, $user_id );
}

# The reactions on the page's posts (ADR 0145), counted for every reader,
# with those the viewer gave; a signed-in reader's forms under each post
# have a fresh command id per permitted reaction.
sub _post_reactions ( $self, $post_ids, $user_id ) {
    return {} if !@{$post_ids};
    return $self->gp_reaction_store->reactions_for_posts( $post_ids, $user_id );
}

# Which post each post on the page answers (ADR 0132), for every reader.
sub _reply_targets ( $self, $post_ids ) {
    return {} if !@{$post_ids};
    return $self->gp_reply_links->targets_for_posts($post_ids);
}

# "Reply" under a post asks for the page with ?reply_to=POST_ID ("Quote"
# sends it too): the composer then names the post it answers and carries
# its id with the reply. A post not on this page is not answered.
sub _reply_into_composer ( $self, $posts ) {
    my $draft  = $self->stash('composer_draft') or return;
    my $wanted = $self->param('reply_to');
    return if !defined $wanted || !length $wanted;
    my ($post) =
      grep { ( column_of( $_, 'post_id' ) // q{} ) eq $wanted } @{$posts};
    return if !$post;
    $draft->{reply_to} = {
        author_username => column_of( $post, 'author_username' ),
        position        => column_of( $post, 'position' ),
        post_id         => $wanted,
    };
    return;
}

sub _post_ids ( $self, $posts ) {
    return grep { defined && length }
      map { $self->_column( $_, 'post_id' ) } @{ $posts || [] };
}

# ADR 0130: the members the reader ignores or blocks, whose posts the page
# collapses; the viewer resolver reads them with the rest of who the reader
# is, in the same query.
sub _listed_members ( $self, $user_id ) {
    return {} if !$user_id;

    return { map { $_ => 1 } @{ $self->gp_forum_viewer->listed } };
}

# The reader who moderates threads (the viewer resolver establishes it with
# the rest of who they are, in the same query) gets the staff actions on the
# page, each with a command id generated by the view model when permitted.
sub _can_moderate_thread ($self) {
    return $self->gp_forum_viewer->moderates ? 1 : 0;
}

# "Quote" under a post asks for the page with ?quote=POST_ID: a signed-in
# reader's reply then opens with that post's source quoted line by line,
# under a line naming who wrote it. A post not on this page is not quoted.
sub _quote_into_composer ( $self, $posts ) {
    my $draft  = $self->stash('composer_draft') or return;
    my $wanted = $self->param('quote');
    return if !defined $wanted || !length $wanted;
    my ($post) =
      grep { ( column_of( $_, 'post_id' ) // q{} ) eq $wanted } @{$posts};
    return if !$post;
    my $source = column_of( $post, 'body_source' );
    my $author = column_of( $post, 'author_username' );
    my $wrote  = $self->t(
        'forum.quoted_from',
        {
            author => defined $author
            ? "\@$author"
            : $self->t('forum.unknown_author')
        }
    );
    $draft->{body_source} = join q{}, "> $wrote\n",
      ( map { "> $_\n" } split /\n/msx, $source // q{} ), "\n";
    return;
}

sub fresh_composer_draft ( $self, $kind, $command_id, %context ) {
    return if !$self->current_user_id;
    $self->stash(
        composer_draft => {
            draft_id       => $self->_new_command_id,
            draft_revision => 0,
            kind           => $kind,
            command_id     => $command_id,
            %context,
        }
    );
    return;
}

sub _thread_edit_command_id ( $self, $page, $user_id ) {
    if ( !$user_id ) {
        return q{};
    }

    my $author = $self->_column( $page->{thread}, 'author_user_id' );
    if ( !$author || $author ne $user_id ) {
        return q{};
    }

    return $self->_new_command_id;
}

async sub _thread_form_bad_request ( $self, $prepared ) {
    if ( $self->wants_json ) {
        return $self->_bad_request( $prepared->{errors} );
    }

    my $categories = (
        await $self->call_p(
            $self->gp_category_reader, 'list_categories',
            { viewer => $self->gp_forum_viewer }
        )
    );
    my $values = $prepared->{values} || {};

    # The form comes back with the command id and category submitted, or a
    # fresh id and the category in the request.
    my $command_id = $values->{command_id};
    if ( !defined $command_id || !length $command_id ) {
        $command_id = $self->_new_command_id;
    }
    my $category_id = $values->{category_id};
    if ( !defined $category_id || !length $category_id ) {
        $category_id = trimmed( $self->param('category_id') );
    }

    return $self->render(
        template => 'forum/new_thread',
        status   => $HTTP_BAD_REQUEST,
        %{
            $self->gp_forum_view_model->new_thread_form(
                categories           => $categories,
                command_id           => $command_id,
                csrf_token           => $self->csrf_token,
                errors               => $prepared->{errors} || {},
                selected_category_id => $category_id,
                values               => $values,
            )
        },
    );
}

sub thread_write_failure ( $self, $result ) {
    return $self->_write_failure(
        $result,
        {
            conflict => sub {
                return $self->_conflict( $result->{error} );
            },
            invalid => async sub {
                return (
                    await $self->await_p(
                        $self->_thread_form_bad_request( $result->{prepared} )
                    )
                );
            },
            not_found => sub {
                return $self->not_found( $result->{error} );
            },
        }
    );
}

sub reply_write_failure ( $self, $result ) {
    return $self->_write_failure(
        $result,
        {
            conflict => sub {
                return $self->_conflict( $result->{error} );
            },
            forbidden => sub {
                return $self->_forbidden( $result->{error} );
            },
            invalid => sub {
                return $self->_bad_request( $result->{prepared}{errors} );
            },
            not_found => sub {
                return $self->not_found( $result->{error} );
            },
        }
    );
}

sub _write_failure ( $self, $result, $handlers ) {
    if ( $self->forum_access->is_unavailable($result) ) {
        return $self->_service_unavailable;
    }
    $self->body_refusal( ( $result->{prepared} // {} )->{errors} );

    my $status  = $result->{status} || q{};
    my $handler = $handlers->{$status};
    if ($handler) {
        return $handler->();
    }

    return $self->system_failure;
}

# ADR 0140: a body past the one maximum length is refused in the reader's
# language, on the body field; the message, or undef for any other errors.
sub body_refusal ( $self, $errors ) {
    return undef if ref $errors ne 'HASH';
    return undef
      if ( $errors->{body_source} // q{} ) ne
      GPForum::Service::Forum::BodyLength->too_long_error;

    return $errors->{body_source} = $self->i18n( 'forum.body_too_long',
        { limit => GPForum::Service::Forum::BodyLength->maximum } );
}

async sub _allowed ( $self, $user_id, $action ) {
    my $decision = await $self->call_p(
        $self->gp_rate_limiter,
        'check',
        $self->forum_access->write_rate_input(
            {
                action      => $action,
                actor_id    => $user_id,
                trust_level => $self->gp_forum_viewer->trust_level,
            }
        )
    );

    return $decision->{ok};
}

async sub read_allowed ( $self, $action ) {
    my $user_id  = $self->current_user_id;
    my $actor_id = $user_id || GPForum::Web::ClientAddress->of( $self->tx );
    my $decision = (
        await $self->call_p(
            $self->gp_rate_limiter,
            'check',
            $self->forum_access->read_rate_input(
                {
                    action      => $action,
                    actor_id    => $actor_id,
                    trust_level => $self->gp_forum_viewer->trust_level,
                }
            )
        )
    );

    return $decision->{ok};
}

# The member a write is made by, or undef once the request has been answered:
# a bad CSRF token, no member signed in, over the rate limit, or suspended
# from an action that needs participation.
async sub write_user_id ( $self, $action ) {
    if ( GPForum::Web::Access->new->csrf_invalid($self) ) {
        $self->_csrf_failure;
        return undef;
    }

    my $user_id = $self->current_user_id;
    if ( !$user_id ) {
        $self->_unauthorized;
        return undef;
    }
    if ( !( await $self->await_p( $self->_allowed( $user_id, $action ) ) ) ) {
        $self->_rate_limited;
        return undef;
    }
    if ( !$self->forum_access->requires_participation($action) ) {
        return $user_id;
    }

    my $decision = (
        await $self->call_p(
            $self->gp_suspension_store,
            'can_participate', $user_id
        )
    );
    if ( !$decision->{ok} ) {
        GPForum::Web::SecurityEvent->new->record_event(
            $self,
            'suspended_user_block',
            {
                action => $action,
                status => $HTTP_FORBIDDEN,
            }
        );
        $self->_forbidden('user is suspended');
        return undef;
    }

    return $user_id;
}

sub search_filters ($self) {
    my %filters;
    for my $field ( $self->forum_access->search_filter_fields ) {
        my $value = trimmed( $self->param($field) );
        if ( length $value ) {
            $filters{$field} = $value;
        }
    }

    return \%filters;
}

sub _column ( $, $row, $name ) {
    return column_of( $row, $name );
}

sub _new_command_id ($self) {
    return $self->gp_id->uuid;
}

sub is_non_negative_integer ( $self, $value ) {
    return $self->forum_access->is_non_negative_integer($value);
}

sub bounded_limit ( $self, $value, $default, $maximum ) {
    return $self->forum_access->bounded_limit(
        {
            default => $default,
            maximum => $maximum,
            value   => $value,
        }
    );
}

sub list_page_limit ($self) {
    return $self->forum_access->list_page_limit( $self->param('limit') );
}

sub _bad_request ( $self, $errors ) {
    return GPForum::Web::Guard->new->bad_request(
        $self,
        {
            error  => 'The submitted forum request was invalid.',
            errors => $errors,
            title  => 'Invalid request',
        }
    );
}

sub _csrf_failure ($self) {
    return GPForum::Web::SecurityEvent->new->csrf_failure($self);
}

sub _unauthorized ($self) {
    return GPForum::Web::SecurityEvent->new->unauthorized($self);
}

sub _forbidden ( $self, $error ) {
    return GPForum::Web::SecurityEvent->new->forbidden( $self,
        { error => $error } );
}

sub _rate_limited ($self) {
    return GPForum::Web::SecurityEvent->new->rate_limited($self);
}

sub _conflict ( $self, $error ) {
    return GPForum::Web::Guard->new->conflict(
        $self,
        {
            error => $error || 'idempotency conflict',
            title => 'Conflict',
        }
    );
}

sub _service_unavailable ($self) {
    return GPForum::Web::Guard->new->service_unavailable($self);
}

1;

__END__

=head1 NAME

GPForum::Controller::Forum::Base - Shared forum HTTP helpers.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    use Mojo::Base 'GPForum::Controller::Forum::Base';
use v5.40;

=head1 DESCRIPTION

Owns CSRF, auth, rate-limit checks, Guard errors, and response helpers used
by forum read, write, community, and search controllers. Rate-limit hashes,
report field errors, and integer limits live on
L<GPForum::Web::ForumAccess>.

=head1 SUBROUTINES/METHODS

=head2 write_user_id

Returns the authenticated actor after CSRF, rate-limit, and suspension
checks, or renders the matching HTTP error.

=head2 body_refusal

Takes a hash of field errors. When the body field holds the too-long refusal
of L<GPForum::Service::Forum::BodyLength>, replaces it with the message in
the reader's language and returns that message; otherwise returns undef.

=head2 fresh_composer_draft

Stashes a new draft identifier, revision zero, publication command identifier,
and supplied composer context for a signed-in author without a database read.

=head1 DIAGNOSTICS

HTTP errors are rendered through L<GPForum::Web::Guard>.

=head1 CONFIGURATION AND ENVIRONMENT

Uses forum helpers registered during application startup.

=head1 DEPENDENCIES

Uses L<GPForum::Controller::Base>, L<GPForum::Web::Access>,
L<GPForum::Web::ForumAccess>, L<GPForum::Web::Guard>,
L<GPForum::Web::Responder>, and L<GPForum::Web::SecurityEvent>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Helpers are HTTP-oriented and must not talk to DBIx::Class resultsets.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
