# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Bootstrap::Moderation;

use v5.40;

use GPForum::Service::Moderation::ActionStore;
use GPForum::Service::Moderation::AutomodStore;
use GPForum::Service::Moderation::ReportStore;
use GPForum::Service::Forum::ViewerResolver;
use GPForum::Service::Moderation::ReviewReader;
use GPForum::Service::Moderation::ReviewStore;
use GPForum::Service::Moderation::ReviewWorkflow;
use GPForum::Service::Moderation::SuspensionStore;
use GPForum::Service::Moderation::Workflow;

our $VERSION = '0.001';

sub register {
    my ( undef, %input ) = @_;

    my $application = $input{application};

    # ADR 0133: watched words, the link rule and automod decisions.
    $application->helper(
        gp_automod_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Moderation::AutomodStore->new(
                schema => $controller->gp_schema );
        }
    );

    # ADR 0134: posts held for review, and the staff's decisions on them.
    $application->helper(
        gp_review_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Moderation::ReviewStore->new(
                schema => $controller->gp_schema );
        }
    );
    $application->helper(
        gp_review_workflow => sub {
            my ($controller) = @_;

            return GPForum::Service::Moderation::ReviewWorkflow->new(
                logger          => $controller->app->log,
                notifications   => $controller->gp_notification_dispatcher,
                posting         => $controller->gp_posting_workflow,
                reply_links     => $controller->gp_reply_links,
                store           => $controller->gp_review_store,
                viewer_resolver => GPForum::Service::Forum::ViewerResolver->new(
                    logger => $controller->app->log,
                    schema => $controller->gp_schema,
                ),
            );
        }
    );
    $application->helper(
        gp_report_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Moderation::ReportStore->new(
                schema => $controller->gp_schema );
        }
    );
    $application->helper(
        gp_moderation_action_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Moderation::ActionStore->new(
                schema => $controller->gp_schema );
        }
    );
    $application->helper(
        gp_suspension_store => sub {
            my ($controller) = @_;

            return GPForum::Service::Moderation::SuspensionStore->new(
                schema => $controller->gp_schema );
        }
    );
    $application->helper(
        gp_moderation_review_reader => sub {
            my ($controller) = @_;

            return GPForum::Service::Moderation::ReviewReader->new(
                schema => $controller->gp_schema );
        }
    );
    $application->helper(
        gp_moderation_workflow => sub {
            my ($controller) = @_;

            return GPForum::Service::Moderation::Workflow->new(
                action_store        => $controller->gp_moderation_action_store,
                command_idempotency => $controller->gp_command_idempotency,
                logger              => $controller->app->log,
                report_store        => $controller->gp_report_store,
                suspension_store    => $controller->gp_suspension_store,
            );
        }
    );

    return;
}

1;
