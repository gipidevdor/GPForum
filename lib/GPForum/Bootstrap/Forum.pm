# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Bootstrap::Forum;

use GPForum::Service::Operations::ReputationRate;
use GPForum::Service::Forum::PostSigner;
use GPForum::Service::Identity::MailReplyToken;
use GPForum::Service::Identity::MailIn;
use Mojo::URL;

use v5.40;

use GPForum::Infrastructure::Antivirus;
use GPForum::Infrastructure::ImageTool;
use GPForum::Service::Attachment::Delivery;
use GPForum::Service::Attachment::FilesystemStorage;
use GPForum::Service::Attachment::IntentBuilder;
use GPForum::Service::Attachment::MediaProcessor;
use GPForum::Service::Attachment::Store;
use GPForum::Service::Attachment::UploadPipeline;
use GPForum::Service::Attachment::Workflow;
use GPForum::Service::Community::AvatarStore;
use GPForum::Service::Community::Avatars;
use GPForum::Service::Community::BookmarkStore;
use GPForum::Service::Community::BookmarkFolders;
use GPForum::Service::Community::LikeStore;
use GPForum::Service::Community::ReactionStore;
use GPForum::Infrastructure::Row;
use GPForum::Service::Forum::ReplyLinks;
use GPForum::Service::Forum::ThreadTags;
use GPForum::Service::Community::FeedReader;
use GPForum::Service::Community::MentionReader;
use GPForum::Service::Community::MentionStore;
use GPForum::Service::Community::MessageStore;
use GPForum::Service::Community::RelationStore;
use GPForum::Service::Community::Workflow;
use GPForum::Service::Forum::CategoryReader;
use GPForum::Service::Forum::DraftStore;
use GPForum::Service::Forum::HomePageReader;
use GPForum::Service::Forum::PostComposer;
use GPForum::Service::Forum::PostPosition;
use GPForum::Service::Forum::PostReader;
use GPForum::Service::Forum::PostStore;
use GPForum::Service::Forum::PostingAutomod;
use GPForum::Service::Forum::PostingReview;
use GPForum::Service::Forum::PostingWorkflow;
use GPForum::Service::Forum::ReadState;
use GPForum::Service::Forum::ReadWorkflow;
use GPForum::Service::Forum::Readability;
use GPForum::Service::Forum::ThreadComposer;
use GPForum::Service::Forum::ThreadPageReads;
use GPForum::Service::Forum::ThreadDetailReader;
use GPForum::Service::Forum::ThreadReader;
use GPForum::Service::Forum::ThreadStore;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Forum::ViewerResolver;
use GPForum::Service::Moderation::AutomodStore;
use GPForum::Service::Moderation::ReviewStore;
use GPForum::Service::Notification::Dispatcher;
use GPForum::Service::Notification::CategorySubscriptions;
use GPForum::Service::Notification::RecipientPolicy;
use GPForum::Service::Notification::PreferenceStore;
use GPForum::Service::Notification::Renderer;
use GPForum::Service::Notification::UnsubscribeToken;
use GPForum::Service::Notification::SubscriptionStore;
use GPForum::Service::Notification::Workflow;
use GPForum::Service::Search::PermissionEngine;
use GPForum::Service::Search::Searcher;
use GPForum::Web::PublicHttpCache;

our $VERSION = '0.001';

sub register ( $, %input ) {
    my $protocol_config = $input{config};
    $input{application}->helper(
        gp_reputation_rate => sub ($controller) {
            return GPForum::Service::Operations::ReputationRate->new(
                schema => $controller->gp_schema );
        }
    );
    my $signer = GPForum::Service::Forum::PostSigner->new(
        key_file => $input{config}->post_signing_key );
    $input{application}->helper( gp_post_signer => sub { return $signer; } );
    $input{application}->helper(
        gp_mail_reply_tokens => sub ($controller) {
            return GPForum::Service::Identity::MailReplyToken->new(
                secrets => $controller->app->secrets,
                domain  =>
                  Mojo::URL->new( $protocol_config->public_base_url )->host
            );
        }
    );
    $input{application}->helper(
        gp_mail_in => sub ($controller) {
            return GPForum::Service::Identity::MailIn->new(
                schema          => $controller->gp_schema,
                tokens          => $controller->gp_mail_reply_tokens,
                viewer_resolver => GPForum::Service::Forum::ViewerResolver->new(
                    schema => $controller->gp_schema
                ),
                suspension_store => $controller->gp_suspension_store,
                rate_limiter     => $controller->gp_rate_limiter,
                reputation_rate  => $controller->gp_reputation_rate,
                workflow         => $controller->gp_posting_workflow
            );
        }
    );
    my $application = $input{application};
    my $config      = $input{config};

    $application->helper(
        gp_category_subscriptions => sub ($controller) {
            return GPForum::Service::Notification::CategorySubscriptions->new(
                schema => $controller->gp_schema );
        }
    );
    _register_forum_helpers( $application, $config );
    _register_attachment_helpers($application);
    _register_community_helpers($application);
    _register_notification_helpers($application);
    _register_search_helpers( $application, $config );

    return;
}

sub _register_forum_helpers {
    my ( $application, $config ) = @_;

    $application->helper(
        gp_draft_store => sub {
            my ($controller) = @_;
            return GPForum::Service::Forum::DraftStore->new(
                schema => $controller->gp_schema );
        }
    );

    $application->helper(
        gp_public_http_cache => sub {
            my ($controller) = @_;

            return GPForum::Web::PublicHttpCache->new(
                cache       => $controller->gp_local_cache,
                ttl_seconds => $config->category_cache_ttl_seconds,
            );
        }
    );

    # The request's reader for visibility (ADR 0102), resolved once and kept
    # on the stash: an anonymous request pays no query, a signed-in one one.
    $application->helper(
        gp_forum_viewer => sub {
            my ($controller) = @_;

            my $cached = $controller->stash('gp.forum_viewer');
            return $cached if $cached;

            my $user_id = $controller->session('user_id');
            my $viewer =
              defined $user_id && length $user_id
              ? GPForum::Service::Forum::ViewerResolver->new(
                logger => $controller->app->log,
                schema => $controller->gp_schema,
              )->resolve($user_id)
              : GPForum::Service::Forum::Viewer->anonymous;
            $controller->stash( 'gp.forum_viewer' => $viewer );

            return $viewer;
        }
    );
    $application->helper(
        gp_category_reader => sub {
            my ($controller) = @_;

            return GPForum::Service::Forum::CategoryReader->new(
                cache             => $controller->gp_local_cache,
                cache_ttl_seconds => $config->category_cache_ttl_seconds,
                schema            => $controller->gp_schema,
            );
        }
    );
    $application->helper(
        gp_thread_reader => sub {
            my ($controller) = @_;

            return GPForum::Service::Forum::ThreadReader->new(
                schema => $controller->gp_schema );
        }
    );
    $application->helper(
        gp_home_page_reader => sub {
            my ($controller) = @_;

            return GPForum::Service::Forum::HomePageReader->new(
                category_reader => $controller->gp_category_reader,
                thread_reader   => $controller->gp_thread_reader,
            );
        }
    );
    $application->helper(
        gp_post_reader => sub {
            my ($controller) = @_;

            return GPForum::Service::Forum::PostReader->new(
                schema => $controller->gp_schema );
        }
    );
    $application->helper(
        gp_thread_detail_reader => sub {
            my ($controller) = @_;

            return GPForum::Service::Forum::ThreadDetailReader->new(
                schema      => $controller->gp_schema,
                post_reader => $controller->gp_post_reader,
            );
        }
    );
    $application->helper(
        gp_thread_composer => sub {
            my ($controller) = @_;

            return GPForum::Service::Forum::ThreadComposer->new(
                post_signer => $controller->gp_post_signer,
                id_service  => $controller->gp_id
            );
        }
    );
    $application->helper(
        gp_thread_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Forum::ThreadStore->new(
                clock      => $controller->gp_clock,
                schema     => $controller->gp_schema,
                id_service => $controller->gp_id,
            );
        }
    );
    $application->helper(
        gp_post_composer => sub {
            my ($controller) = @_;

            return GPForum::Service::Forum::PostComposer->new(
                post_signer => $controller->gp_post_signer,
                id_service  => $controller->gp_id
            );
        }
    );
    $application->helper(
        gp_post_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Forum::PostStore->new(
                clock      => $controller->gp_clock,
                schema     => $controller->gp_schema,
                id_service => $controller->gp_id,
            );
        }
    );
    $application->helper(
        gp_post_position => sub {
            my ($controller) = @_;

            return GPForum::Service::Forum::PostPosition->new(
                schema => $controller->gp_schema );
        }
    );
    $application->helper(
        gp_thread_read_state => sub {
            my ($controller) = @_;

            return GPForum::Service::Forum::ReadState->new(
                schema => $controller->gp_schema, );
        }
    );
    $application->helper(
        gp_thread_read_workflow => sub {
            my ($controller) = @_;

            return GPForum::Service::Forum::ReadWorkflow->new(
                command_idempotency => $controller->gp_command_idempotency,
                logger              => $controller->app->log,
                read_state          => $controller->gp_thread_read_state,
            );
        }
    );
    $application->helper(
        gp_posting_workflow => sub {
            my ($controller) = @_;

            return GPForum::Service::Forum::PostingWorkflow->new(
                automod => GPForum::Service::Forum::PostingAutomod->new(
                    logger => $controller->app->log,
                    store  => GPForum::Service::Moderation::AutomodStore->new(
                        schema => $controller->gp_schema
                    ),
                ),
                review => GPForum::Service::Forum::PostingReview->new(
                    logger => $controller->app->log,
                    store  => GPForum::Service::Moderation::ReviewStore->new(
                        schema => $controller->gp_schema
                    ),
                ),
                category_reader      => $controller->gp_category_reader,
                command_idempotency  => $controller->gp_command_idempotency,
                logger               => $controller->app->log,
                mention_store        => $controller->gp_mention_store,
                post_composer        => $controller->gp_post_composer,
                post_reader          => $controller->gp_post_reader,
                post_store           => $controller->gp_post_store,
                thread_composer      => $controller->gp_thread_composer,
                thread_detail_reader => $controller->gp_thread_detail_reader,
                thread_store         => $controller->gp_thread_store,
            );
        }
    );

    return;
}

sub _register_attachment_helpers {
    my ($application) = @_;

    my $attachment_storage;

    # The system antivirus the configuration names (ADR 0108), or undef when
    # the operator turned scanning off. Built once: a scanner holds only its
    # socket path or command, and connects per scan.
    my ( $antivirus, $antivirus_built );
    $application->helper(
        gp_antivirus => sub {
            my ($controller) = @_;

            if ( !$antivirus_built ) {
                $antivirus = GPForum::Infrastructure::Antivirus->from_config(
                    $controller->gp_config );
                $antivirus_built = 1;
            }
            return $antivirus;
        }
    );
    $application->helper(
        gp_attachment_storage => sub {
            my ($controller) = @_;

            $attachment_storage ||=
              GPForum::Service::Attachment::FilesystemStorage->new(
                root => $controller->gp_config->attachment_root );
            return $attachment_storage;
        }
    );
    $application->helper(
        gp_attachment_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Attachment::Store->new(
                clock       => $controller->gp_clock,
                id_service  => $controller->gp_id,
                readability => GPForum::Service::Forum::Readability->new(
                    schema => $controller->gp_schema
                ),
                schema => $controller->gp_schema,
            );
        }
    );
    $application->helper(
        gp_attachment_upload_pipeline => sub {
            my ($controller) = @_;

            return GPForum::Service::Attachment::UploadPipeline->new(
                antivirus      => $controller->gp_antivirus,
                intent_builder =>
                  GPForum::Service::Attachment::IntentBuilder->new(
                    clock      => $controller->gp_clock,
                    id_service => $controller->gp_id,
                  ),
                storage => $controller->gp_attachment_storage,
                store   => $controller->gp_attachment_store,
            );
        }
    );
    $application->helper(
        gp_attachment_delivery => sub {
            my ($controller) = @_;

            return GPForum::Service::Attachment::Delivery->new(
                storage => $controller->gp_attachment_storage,
                store   => $controller->gp_attachment_store,
            );
        }
    );
    $application->helper(
        gp_attachment_workflow => sub {
            my ($controller) = @_;

            return GPForum::Service::Attachment::Workflow->new(
                command_idempotency => $controller->gp_command_idempotency,
                delivery            => $controller->gp_attachment_delivery,
                logger              => $controller->app->log,
                pipeline    => $controller->gp_attachment_upload_pipeline,
                post_reader => $controller->gp_post_reader,
                store       => $controller->gp_attachment_store,
            );
        }
    );
    $application->helper(
        gp_media_processor => sub {
            my ($controller) = @_;

            return GPForum::Service::Attachment::MediaProcessor->new(
                avatars    => $controller->gp_avatars,
                image_tool => $controller->gp_image_tool,
                storage    => $controller->gp_attachment_storage,
                store      => $controller->gp_attachment_store,
            );
        }
    );

    # ADR 0144: members' profile pictures, cropped by the system's image
    # tool (built once: it holds only its program's path).
    my ( $image_tool, $image_tool_built );
    $application->helper(
        gp_image_tool => sub {
            my ($controller) = @_;

            if ( !$image_tool_built ) {
                $image_tool = GPForum::Infrastructure::ImageTool->from_config(
                    $controller->gp_config );
                $image_tool_built = 1;
            }
            return $image_tool;
        }
    );
    $application->helper(
        gp_avatar_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Community::AvatarStore->new(
                clock      => $controller->gp_clock,
                id_service => $controller->gp_id,
                schema     => $controller->gp_schema,
            );
        }
    );
    $application->helper(
        gp_avatars => sub {
            my ($controller) = @_;

            return GPForum::Service::Community::Avatars->new(
                attachments => $controller->gp_attachment_store,
                image_tool  => $controller->gp_image_tool,
                logger      => $controller->app->log,
                pipeline    => $controller->gp_attachment_upload_pipeline,
                storage     => $controller->gp_attachment_storage,
                store       => $controller->gp_avatar_store,
            );
        }
    );

    return;
}

sub _register_community_helpers {
    my ($application) = @_;

    $application->helper(
        gp_bookmark_folders => sub {
            my ($controller) = @_;

            return GPForum::Service::Community::BookmarkFolders->new(
                schema => $controller->gp_schema );
        }
    );
    $application->helper(
        gp_bookmark_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Community::BookmarkStore->new(
                readability => GPForum::Service::Forum::Readability->new(
                    schema => $controller->gp_schema
                ),
                schema => $controller->gp_schema,
            );
        }
    );
    $application->helper(
        gp_reply_links => sub {
            my ($controller) = @_;

            return GPForum::Service::Forum::ReplyLinks->new(
                schema => $controller->gp_schema );
        }
    );
    $application->helper(
        gp_thread_tags => sub {
            my ($controller) = @_;

            return GPForum::Service::Forum::ThreadTags->new(
                schema => $controller->gp_schema );
        }
    );

    # The tags of the threads a page lists, by thread id (ADR 0135): a hint
    # on each row, so a read that fails shows none and says so in the log.
    $application->helper(
        gp_tags_for_threads => sub {
            my ( $controller, $threads ) = @_;

            my @ids =
              map { GPForum::Infrastructure::Row->column( $_, 'thread_id' ) }
              @{ $threads || [] };
            my $tags = {};
            try {
                $tags = $controller->gp_thread_tags->tags_for_threads( \@ids );
            }
            catch ($error) {
                my ($reason) = split /\n/msx, "$error";
                $controller->app->log->warn("thread tags degraded: $reason");
            };
            return $tags;
        }
    );
    $application->helper(
        gp_reaction_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Community::ReactionStore->new(
                schema => $controller->gp_schema );
        }
    );
    $application->helper(
        gp_like_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Community::LikeStore->new(
                schema => $controller->gp_schema );
        }
    );
    $application->helper(
        gp_community_workflow => sub {
            my ($controller) = @_;

            return GPForum::Service::Community::Workflow->new(
                bookmark_store      => $controller->gp_bookmark_store,
                command_idempotency => $controller->gp_command_idempotency,
                like_store          => $controller->gp_like_store,
                reaction_store      => $controller->gp_reaction_store,
                logger              => $controller->app->log,
                report_store        => $controller->gp_report_store,
                subscription_store  => $controller->gp_subscription_store,
            );
        }
    );

    # Migration 124: the reads a thread page makes once it has its posts,
    # in one statement, each answered to the store that makes it.
    $application->helper(
        gp_thread_page_reads => sub {
            my ($controller) = @_;

            return GPForum::Service::Forum::ThreadPageReads->new(
                attachment_store   => $controller->gp_attachment_store,
                bookmark_store     => $controller->gp_bookmark_store,
                like_store         => $controller->gp_like_store,
                reaction_store     => $controller->gp_reaction_store,
                logger             => $controller->app->log,
                read_state         => $controller->gp_thread_read_state,
                reply_links        => $controller->gp_reply_links,
                schema             => $controller->gp_schema,
                subscription_store => $controller->gp_subscription_store,
                thread_tags        => $controller->gp_thread_tags,
            );
        }
    );
    $application->helper(
        gp_feed_reader => sub {
            my ($controller) = @_;

            return GPForum::Service::Community::FeedReader->new(
                readability => GPForum::Service::Forum::Readability->new(
                    schema => $controller->gp_schema
                ),
                schema => $controller->gp_schema,
            );
        }
    );

    # ADR 0130: the members a member ignores or blocks.
    $application->helper(
        gp_relation_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Community::RelationStore->new(
                schema => $controller->gp_schema );
        }
    );

    # ADR 0139: direct messages, screened as a reply is (ADR 0133).
    $application->helper(
        gp_message_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Community::MessageStore->new(
                schema  => $controller->gp_schema,
                automod => GPForum::Service::Forum::PostingAutomod->new(
                    logger => $controller->app->log,
                    store  => GPForum::Service::Moderation::AutomodStore->new(
                        schema => $controller->gp_schema
                    ),
                ),
            );
        }
    );
    $application->helper(
        gp_mention_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Community::MentionStore->new(
                notification_dispatcher =>
                  $controller->gp_notification_dispatcher,
                readability => GPForum::Service::Forum::Readability->new(
                    schema => $controller->gp_schema
                ),
                relations => $controller->gp_relation_store,
                schema    => $controller->gp_schema,
            );
        }
    );
    $application->helper(
        gp_mention_reader => sub {
            my ($controller) = @_;

            return GPForum::Service::Community::MentionReader->new(
                readability => GPForum::Service::Forum::Readability->new(
                    schema => $controller->gp_schema
                ),
                schema => $controller->gp_schema,
            );
        }
    );

    return;
}

sub _register_notification_helpers {
    my ($application) = @_;

    $application->helper(
        gp_subscription_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Notification::SubscriptionStore->new(
                schema => $controller->gp_schema );
        }
    );
    $application->helper(
        gp_notification_preference_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Notification::PreferenceStore->new(
                schema => $controller->gp_schema );
        }
    );
    $application->helper(
        gp_notification_dispatcher => sub {
            my ($controller) = @_;

            # ADR 0102: only recipients who can read the source are notified,
            # and the inbox shows only what they can still read.
            my $policy = GPForum::Service::Notification::RecipientPolicy->new(
                schema => $controller->gp_schema );

            # The application's log, in the web and the worker processes: a
            # badge that failed after a write was counted and logged nowhere.
            return GPForum::Service::Notification::Dispatcher->new(
                logger            => $controller->app->log,
                permission_engine => $policy,
                preference_store  =>
                  $controller->gp_notification_preference_store,
                readability        => $policy,
                realtime_notifier  => $controller->gp_realtime_pg_notifier,
                relations          => $controller->gp_relation_store,
                schema             => $controller->gp_schema,
                subscription_store => $controller->gp_subscription_store,
            );
        }
    );
    $application->helper(
        gp_notification_workflow => sub {
            my ($controller) = @_;

            return GPForum::Service::Notification::Workflow->new(
                command_idempotency => $controller->gp_command_idempotency,
                dispatcher          => $controller->gp_notification_dispatcher,
                logger              => $controller->app->log,
                preference_store    =>
                  $controller->gp_notification_preference_store,
            );
        }
    );

    # ADR 0078: the signed links that stop a kind of notification email.
    $application->helper(
        gp_unsubscribe_tokens => sub {
            my ($controller) = @_;

            return GPForum::Service::Notification::UnsubscribeToken->new(
                secrets => $controller->app->secrets );
        }
    );
    $application->helper(
        gp_notification_renderer => sub {
            my ($controller) = @_;

            return GPForum::Service::Notification::Renderer->new(
                i18n => $controller->i18n_service );
        }
    );

    return;
}

sub _register_search_helpers {
    my ( $application, $config ) = @_;

    # Search's own statement timeout and candidate cap (8.10): a word most
    # documents hold is ranked over the newest matches only, and whatever
    # still runs long is cancelled before it holds a web worker for the
    # statement_timeout every other query gets.
    $application->helper(
        gp_search_service => sub {
            my ($controller) = @_;

            return GPForum::Service::Search::Searcher->new(
                candidate_limit   => $config->search_candidate_limit,
                permission_engine =>
                  GPForum::Service::Search::PermissionEngine->new(
                    schema => $controller->gp_schema
                  ),
                schema               => $controller->gp_schema,
                statement_timeout_ms => $config->search_statement_timeout_ms,
            );
        }
    );

    return;
}

1;
