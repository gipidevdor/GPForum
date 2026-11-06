# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::AsyncResult;
use Mojo::Base -base;
use v5.40;
has 'schema';

sub inbox ($self) {
    require GPForum::Infrastructure::ResultRow::NotificationInbox;
    return GPForum::Infrastructure::ResultRow::NotificationInbox->from(
        {
            recipient_user_id   => 'recipient',
            notification_id     => 'notification',
            notification_type   => 'direct_message',
            source_type         => 'conversation',
            source_id           => 'conversation',
            payload             => { body => 'message' },
            source_thread_title => 'prefetched title',
        }
    );
}

sub invalid ($self) {
    require GPForum::X::Argument;
    GPForum::X::Argument->throw( message => 'invalid endpoint' );
}
our $VERSION = '0.001';
1;
