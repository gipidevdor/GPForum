# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::SqlFunctionCatalogue::Notification;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my %FUNCTION => (
    notification_push_refresh => {
        version    => 2,
        parameters => [ lease_id => 'uuid' ],
        json       => [ 'viewer', 'placement' ]
    },
    notification_push_finish_batch =>
      { version => 2, parameters => [ outcomes => 'jsonb' ] },
    notification_push_register => {
        version    => 2,
        parameters => [
            user_id         => 'uuid',
            session_id      => 'uuid',
            subscription_id => 'uuid',
            endpoint_hash   => 'text',
            envelope        => 'text',
            provider        => 'text',
            key_id          => 'text',
            kinds           => 'text[]',
            challenge_hash  => 'text',
            activation      => 'text'
        ],
        json => ['result'],
    },
    notification_push_confirm => {
        version    => 2,
        parameters => [
            user_id         => 'uuid',
            session_id      => 'uuid',
            subscription_id => 'uuid',
            challenge_hash  => 'text'
        ],
        json => ['result'],
    },
    notification_push_devices =>
      { version => 2, parameters => [ user_id => 'uuid' ], },
    notification_push_revoke => {
        version    => 2,
        parameters => [ user_id => 'uuid', subscription_id => 'uuid' ],
        json       => ['result'],
    },
    notification_push_enqueue =>
      { version => 2, parameters => [ notification => 'jsonb' ], },
    notification_push_claim => {
        version    => 2,
        parameters =>
          [ lease_id => 'uuid', limit => 'integer', per_provider => 'integer' ],
        json => [ 'viewer', 'placement' ],
    },
    notification_push_finish => {
        version    => 2,
        parameters => [
            delivery_id => 'bigint',
            lease_id    => 'uuid',
            outcome     => 'text',
            retry_after => 'integer'
        ],
    },
    notification_push_cleanup    => { version => 2, parameters => [], },
    notification_category_follow => {
        version    => 2,
        parameters => [
            actor       => 'uuid',
            command     => 'uuid',
            category_id => 'uuid',
            operation   => 'text'
        ],
        json => ['result']
    },
    notification_save_subscription => {
        version    => 2,
        parameters => [ row => 'jsonb', restore => 'boolean' ],
        json       => ['result']
    },
    notification_find_subscription => {
        version    => 2,
        parameters =>
          [ user_id => 'uuid', target_type => 'text', target_id => 'uuid' ]
    },
    notification_stamp_subscription => {
        version    => 2,
        parameters => [
            id          => 'uuid',
            by_target   => 'boolean',
            user_id     => 'uuid',
            target_type => 'text',
            target_id   => 'uuid',
            column      => 'text',
            stamped_at  => 'text'
        ],
        json => ['result']
    },
    notification_subscribers => {
        version    => 6,
        parameters => [
            target_type       => 'text',
            target_id         => 'uuid',
            notification_type => 'text'
        ]
    },
    notification_list_preferences =>
      { version => 2, parameters => [ user_id => 'uuid' ] },
    notification_set_preference =>
      { version => 2, parameters => [ row => 'jsonb' ], json => ['result'] },

    # ADR 0078: notification preferences by kind, and the unsubscribe link.
    notification_type_preferences =>
      { version => 4, parameters => [ user_id => 'uuid' ] },
    notification_set_type_preferences => {
        version    => 4,
        parameters =>
          [ user_id => 'uuid', preferences => 'jsonb', now => 'timestamptz' ]
    },
    notification_delivery_plan => {
        version    => 6,
        parameters => [ user_id => 'uuid', notification_type => 'text' ]
    },
    notification_unsubscribe => {
        version    => 4,
        parameters => [
            user_id => 'uuid',
            scope   => 'text',
            now     => 'timestamptz',
            audit   => 'jsonb'
        ]
    },

    # ADR 0078: the daily and weekly email digest.
    notification_digest_due => {
        version    => 4,
        parameters => [
            now           => 'timestamptz',
            after_start   => 'timestamptz',
            after_user_id => 'uuid',
            row_limit     => 'integer'
        ]
    },
    notification_digest_items => {
        version    => 4,
        parameters => [
            user_id      => 'uuid',
            period_start => 'timestamptz',
            period_end   => 'timestamptz',
            member       => 'boolean',
            global_read  => 'boolean',
            category_ids => 'uuid[]',
            space_ids    => 'uuid[]',
            row_limit    => 'integer'
        ]
    },
    notification_digest_record => {
        version    => 6,
        parameters => [
            user_id       => 'uuid',
            frequency     => 'text',
            period_start  => 'timestamptz',
            period_end    => 'timestamptz',
            thread_count  => 'integer',
            now           => 'timestamptz',
            event         => 'jsonb',
            outbox_id     => 'text',
            outbox_extras => 'jsonb',
            explicit      => 'boolean'
        ]
    },
    notification_digest_plan => {
        version    => 4,
        parameters => [ user_id => 'uuid', now => 'timestamptz' ]
    },
    notification_digest_unsubscribe => {
        version    => 2,
        parameters =>
          [ user_id => 'uuid', now => 'timestamptz', audit => 'jsonb' ]
    },
    notification_digest_purge => {
        version    => 2,
        parameters => [ before => 'timestamptz', row_limit => 'integer' ]
    },
    notification_digest_claim => {
        version    => 2,
        parameters => [
            user_id      => 'uuid',
            frequency    => 'text',
            period_start => 'timestamptz',
            event_id     => 'uuid',
            now          => 'timestamptz'
        ]
    },
    notification_digest_release => {
        version    => 2,
        parameters => [
            user_id      => 'uuid',
            frequency    => 'text',
            period_start => 'timestamptz',
            event_id     => 'uuid'
        ]
    },
    notification_deliver => {
        version    => 2,
        parameters => [
            notification    => 'jsonb',
            inbox           => 'jsonb',
            idempotency_key => 'text'
        ],
        json => ['result']
    },
    notification_fanout_candidates => {
        version    => 6,
        parameters => [
            target_type       => 'text',
            target_id         => 'uuid',
            notification_type => 'text',
            actor_id          => 'uuid',
            excluded_user_id  => 'uuid',
        ],
        json => ['grants'],
    },
    notification_fanout_page => {
        version    => 2,
        parameters => [
            target_type       => 'text',
            target_id         => 'uuid',
            notification_type => 'text',
            actor_id          => 'uuid',
            excluded_user_id  => 'uuid',
            after_user_id     => 'uuid',
            through_user_id   => 'uuid',
            row_limit         => 'integer',
        ],
        json => ['grants'],
    },
    notification_fanout_deliver => {
        version    => 4,
        parameters => [ recipients => 'jsonb' ],
        json       => ['result'],
    },
    notification_mark_read => {
        version    => 2,
        parameters => [
            notification_id   => 'uuid',
            recipient_user_id => 'uuid',
            read_at           => 'text'
        ],
        json => ['result']
    },
    notification_mark_all_read => {
        version    => 4,
        parameters => [
            user_id        => 'uuid',
            filter_sources => 'boolean',
            member         => 'boolean',
            global_read    => 'boolean',
            viewer_user_id => 'uuid',
            category_ids   => 'uuid[]',
            space_ids      => 'uuid[]',
            read_at        => 'text'
        ],
        json => ['result']
    },
    notification_list_inbox => {
        version    => 8,
        parameters => [
            recipient_user_id     => 'uuid',
            filter_sources        => 'boolean',
            member                => 'boolean',
            global_read           => 'boolean',
            viewer_user_id        => 'uuid',
            category_ids          => 'uuid[]',
            space_ids             => 'uuid[]',
            after_created_at      => 'timestamptz',
            after_notification_id => 'uuid',
            row_limit             => 'integer'
        ],
    },
    notification_unread_count => {
        version    => 8,
        parameters => [
            recipient_user_id => 'uuid',
            filter_sources    => 'boolean',
            member            => 'boolean',
            global_read       => 'boolean',
            viewer_user_id    => 'uuid',
            category_ids      => 'uuid[]',
            space_ids         => 'uuid[]'
        ]
    },
);

sub entries ($class) {
    return \%FUNCTION;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::SqlFunctionCatalogue::Notification - The PostgreSQL functions of notifications: the inbox, preferences, digests, fan-out and Web Push.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $entries = GPForum::Infrastructure::SqlFunctionCatalogue::Notification->entries;

=head1 DESCRIPTION

A part of the table L<GPForum::Infrastructure::SqlFunctionCatalogue> reads:
the entries for the functions of notifications: the inbox, preferences, digests, fan-out and Web Push. See that module for what an
entry holds and for ADR 0126.

=head1 SUBROUTINES/METHODS

=head2 entries

The hash reference of entries, by name, read-only.

=head1 DIAGNOSTICS

None of its own.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Const::Fast.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
