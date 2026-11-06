# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Bootstrap::Push;

use v5.40;
use GPForum::Service::Notification::Push::Store;
use GPForum::Service::Notification::Push::Worker;

our $VERSION = '0.001';

sub register ( $, %input ) {
    my $app    = $input{application};
    my $config = $input{config};
    $app->helper(
        gp_push_store => sub ($controller) {
            return GPForum::Service::Notification::Push::Store->new(
                schema => $controller->gp_schema,
                config => $config
            );
        }
    );
    $app->helper(
        gp_push_worker => sub ($controller) {
            return GPForum::Service::Notification::Push::Worker->new(
                store => $controller->gp_push_store );
        }
    );
    return;
}

1;
