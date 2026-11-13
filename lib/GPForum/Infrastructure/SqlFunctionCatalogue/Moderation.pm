# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::SqlFunctionCatalogue::Moderation;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my %FUNCTION => (
    moderation_thread_transfer => {
        version    => 6,
        parameters => [
            actor        => 'uuid',
            command      => 'uuid',
            source_id    => 'uuid',
            target_id    => 'uuid',
            operation    => 'text',
            post_numbers => 'bigint[]',
            title        => 'text',
            reason       => 'text'
        ],
        json => ['result']
    },
    moderation_thread_transfer_undo => {
        version    => 6,
        parameters =>
          [ actor => 'uuid', command => 'uuid', transfer_id => 'uuid' ],
        json => ['result']
    },
    moderation_transfer_picker => {
        version    => 4,
        parameters => [
            actor          => 'uuid',
            source_id      => 'uuid',
            query          => 'text',
            after_position => 'bigint'
        ],
        json => ['result']
    },
    moderation_thread_transfers =>
      { version => 2, parameters => [ actor => 'uuid' ], json => ['result'] },

    moderation_target => {
        version    => 6,
        parameters => [ kind => 'text', target_id => 'uuid', hold => 'boolean' ]
    },
    moderation_target_update => {
        version    => 6,
        parameters =>
          [ kind => 'text', target_id => 'uuid', changes => 'jsonb' ]
    },
    moderation_action_find => {
        version    => 4,
        parameters => [
            action_id   => 'uuid',
            command_id  => 'uuid',
            action_type => 'text',
            target_type => 'text',
            target_id   => 'uuid'
        ]
    },
    moderation_action_update => {
        version    => 4,
        parameters => [ action_id => 'uuid', changes => 'jsonb' ]
    },
    moderation_report_find => {
        version    => 4,
        parameters => [
            report_id        => 'uuid',
            reporter_user_id => 'uuid',
            target_type      => 'text',
            target_id        => 'uuid',
            hold             => 'boolean'
        ]
    },
    moderation_report_update => {
        version    => 4,
        parameters => [ report_id => 'uuid', changes => 'jsonb' ]
    },
    moderation_report_queue => {
        version    => 4,
        parameters => [ status => 'text', row_limit => 'integer' ]
    },

    # ADR 0133: watched words and automod rules.
    moderation_watched_word_add => {
        version    => 2,
        parameters => [
            word_id       => 'uuid',
            phrase        => 'text',
            action        => 'text',
            replacement   => 'text',
            actor_user_id => 'uuid',
            now           => 'timestamptz',
            audit         => 'jsonb',
        ],
    },
    moderation_watched_word_remove =>
      { version => 2, parameters => [ word_id => 'uuid', audit => 'jsonb' ] },
    moderation_watched_word_list    => { version => 2, parameters => [] },
    moderation_automod_settings_set => {
        version    => 2,
        parameters => [
            link_limit       => 'integer',
            link_trust_below => 'integer',
            link_action      => 'text',
            actor_user_id    => 'uuid',
            now              => 'timestamptz',
            audit            => 'jsonb',
        ],
    },
    moderation_automod_rules => {
        version    => 4,
        parameters => [ user_id => 'uuid' ],
        json       => ['document']
    },
    moderation_automod_record => {
        version    => 4,
        parameters => [
            report          => 'jsonb',
            event           => 'jsonb',
            event_outbox_id => 'text',
            report_audit    => 'jsonb',
            audits          => 'jsonb',
        ],
    },

    # ADR 0134: the first-post review queue.
    moderation_review_hold => {
        version    => 4,
        parameters => [
            review_id          => 'uuid',
            author_user_id     => 'uuid',
            command_id         => 'text',
            kind               => 'text',
            category_id        => 'uuid',
            thread_id          => 'uuid',
            title              => 'text',
            body_source        => 'text',
            body_rendered_safe => 'text',
            visibility         => 'text',
            reply_to_post_id   => 'uuid',
            reason             => 'text',
            details            => 'jsonb',
            draft_id           => 'uuid',
            draft_revision     => 'bigint',
            now                => 'timestamptz',
            audit              => 'jsonb',
            tags               => 'text',
        ],
    },
    moderation_review_queue => {
        version    => 2,
        parameters => [ row_limit => 'integer' ],
        json       => ['details']
    },
    moderation_review_mine => {
        version    => 4,
        parameters => [
            user_id      => 'uuid',
            row_limit    => 'integer',
            member       => 'boolean',
            global_read  => 'boolean',
            category_ids => 'uuid[]',
            space_ids    => 'uuid[]'
        ]
    },
    moderation_review_take =>
      { version => 4, parameters => [ review_id => 'uuid' ] },
    moderation_review_decide => {
        version    => 2,
        parameters => [
            review_id     => 'uuid',
            status        => 'text',
            actor_user_id => 'uuid',
            reason        => 'text',
            post_id       => 'uuid',
            now           => 'timestamptz',
            audit         => 'jsonb',
        ],
    },
    moderation_review_settings_set => {
        version    => 2,
        parameters => [
            first_posts   => 'integer',
            flagged       => 'boolean',
            actor_user_id => 'uuid',
            now           => 'timestamptz',
            audit         => 'jsonb',
        ],
    },
    moderation_member_note_add => {
        version    => 2,
        parameters => [
            note_id         => 'uuid',
            subject_user_id => 'uuid',
            author_user_id  => 'uuid',
            body            => 'text',
            now             => 'timestamptz',
            audit           => 'jsonb',
        ],
    },
    moderation_member_note_edit => {
        version    => 2,
        parameters => [
            note_id         => 'uuid',
            subject_user_id => 'uuid',
            editor_user_id  => 'uuid',
            body            => 'text',
            now             => 'timestamptz',
            audit           => 'jsonb',
        ],
    },
    moderation_member_note_delete => {
        version    => 2,
        parameters =>
          [ note_id => 'uuid', subject_user_id => 'uuid', audit => 'jsonb' ],
    },
    moderation_member_notes => {
        version    => 2,
        parameters => [ subject_user_id => 'uuid', row_limit => 'integer' ]
    },
    moderation_member_notes_for_reports => {
        version    => 2,
        parameters => [ report_ids => 'uuid[]', per_member => 'integer' ]
    },

    # ADR 0139: staff read a reported message, audited.
    moderation_reported_message => {
        version    => 2,
        parameters => [ report_id => 'uuid', audit => 'jsonb' ]
    },
    moderation_suspension_find =>
      { version => 4, parameters => [ suspension_id => 'uuid' ] },

    # v5.0.0-2.3.4: the member whose suspensions change, locked first.
    moderation_lock_member =>
      { version => 2, parameters => [ user_id => 'uuid' ] },
    moderation_suspension_update => {
        version    => 4,
        parameters => [ suspension_id => 'uuid', revoked_at => 'timestamptz' ]
    },
    moderation_action_insert =>
      { version => 4, parameters => [ values => 'jsonb' ] },
    moderation_report_insert =>
      { version => 4, parameters => [ values => 'jsonb' ] },
    moderation_suspension_insert =>
      { version => 6, parameters => [ values => 'jsonb' ] },

    # Whom an actor may suspend: staff only by an admin, never oneself.
    moderation_suspension_target => {
        version    => 2,
        parameters => [ actor => 'uuid', user_id => 'uuid' ]
    },

    # v5.0.0-2.3.2: the hourly sweep queues the ends a timed suspension lacks.
    moderation_queue_suspension_ends => {
        version    => 2,
        parameters => [ now => 'timestamptz', row_limit => 'integer' ]
    },
    moderation_action_list => {
        version    => 2,
        parameters => [
            target_type => 'text',
            target_id   => 'uuid',
            after_at    => 'timestamptz',
            after_id    => 'uuid',
            row_limit   => 'integer'
        ]
    },
    moderation_suspension_list => {
        version    => 2,
        parameters => [
            user_id     => 'uuid',
            active_only => 'boolean',
            now         => 'timestamptz',
            after_at    => 'timestamptz',
            after_id    => 'uuid',
            row_limit   => 'integer'
        ]
    },
    moderation_active_suspension => {
        version    => 4,
        parameters => [
            user_id => 'uuid',
            now     => 'timestamptz',
        ],
    },
    moderation_can_participate => {
        version    => 4,
        parameters => [
            user_id => 'uuid',
            now     => 'timestamptz',
        ],
    },
);

sub entries ($class) {
    return \%FUNCTION;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::SqlFunctionCatalogue::Moderation - The PostgreSQL functions of moderation: actions, reports, suspensions, review and automod.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $entries = GPForum::Infrastructure::SqlFunctionCatalogue::Moderation->entries;

=head1 DESCRIPTION

A part of the table L<GPForum::Infrastructure::SqlFunctionCatalogue> reads:
the entries for the functions of moderation: actions, reports, suspensions, review and automod. See that module for what an
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
