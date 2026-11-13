# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::SqlFunctionCatalogue::Community;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my %FUNCTION => (
    community_follow_change => {
        version    => 2,
        parameters => [
            actor     => 'uuid',
            command   => 'uuid',
            username  => 'text',
            operation => 'text'
        ],
        json => ['result']
    },
    community_follow_state =>
      { version => 2, parameters => [ actor => 'uuid', target => 'uuid' ] },
    community_followed_users =>
      { version => 2, parameters => [ actor => 'uuid' ] },
    community_follow_feed => {
        version    => 4,
        parameters => [
            actor        => 'uuid',
            member       => 'boolean',
            global_read  => 'boolean',
            category_ids => 'uuid[]',
            space_ids    => 'uuid[]',
            after_at     => 'timestamptz',
            after_id     => 'uuid',
            row_limit    => 'integer'
        ]
    },

    community_list_bookmarks => {
        version    => 4,
        parameters => [
            user_id          => 'uuid',
            filter_sources   => 'boolean',
            member           => 'boolean',
            global_read      => 'boolean',
            viewer_user_id   => 'uuid',
            category_ids     => 'uuid[]',
            space_ids        => 'uuid[]',
            target_type      => 'text',
            after_created_at => 'timestamp with time zone',
            after_id         => 'uuid',
            row_limit        => 'integer',
            folder           => 'text'
        ]
    },
    community_list_feed => {
        version    => 4,
        parameters => [
            user_id          => 'uuid',
            filter_sources   => 'boolean',
            member           => 'boolean',
            global_read      => 'boolean',
            viewer_user_id   => 'uuid',
            category_ids     => 'uuid[]',
            space_ids        => 'uuid[]',
            after_created_at => 'timestamp with time zone',
            after_id         => 'uuid',
            row_limit        => 'integer'
        ]
    },
    community_list_mentions => {
        version    => 4,
        parameters => [
            user_id          => 'uuid',
            filter_sources   => 'boolean',
            member           => 'boolean',
            global_read      => 'boolean',
            viewer_user_id   => 'uuid',
            category_ids     => 'uuid[]',
            space_ids        => 'uuid[]',
            after_created_at => 'timestamp with time zone',
            after_id         => 'uuid',
            row_limit        => 'integer'
        ]
    },
    community_set_bookmark_folder => {
        version    => 2,
        parameters =>
          [ bookmark_id => 'uuid', user_id => 'uuid', folder => 'text' ]
    },
    community_list_bookmark_folders => {
        version    => 4,
        parameters => [
            user_id        => 'uuid',
            filter_sources => 'boolean',
            member         => 'boolean',
            global_read    => 'boolean',
            viewer_user_id => 'uuid',
            category_ids   => 'uuid[]',
            space_ids      => 'uuid[]',
            target_type    => 'text'
        ]
    },
    community_save_bookmark => {
        version    => 2,
        parameters => [ row => 'jsonb', restore => 'boolean' ],
        json       => ['result']
    },
    community_bookmark_command => {
        version    => 2,
        parameters => [ log => 'jsonb', answer => 'jsonb', row => 'jsonb' ],
        json       => ['response']
    },
    community_target_command => {
        version    => 2,
        parameters => [ log => 'jsonb', answer => 'jsonb', row => 'jsonb' ],
        json       => ['response']
    },
    community_like_command => {
        version    => 2,
        parameters => [ log => 'jsonb', answer => 'jsonb', row => 'jsonb' ],
        json       => ['response']
    },
    community_unlike_command => {
        version    => 2,
        parameters => [ log => 'jsonb', answer => 'jsonb', row => 'jsonb' ],
        json       => ['response']
    },
    community_like_post => {
        version    => 2,
        parameters => [ row => 'jsonb' ],
        json       => ['result']
    },
    community_unlike_post => {
        version    => 2,
        parameters => [ row => 'jsonb' ],
        json       => ['result']
    },
    community_post_likes => {
        version    => 2,
        parameters => [ post_ids => 'uuid[]', viewer_user_id => 'uuid' ]
    },
    community_post_reactions => {
        version    => 2,
        parameters => [ post_ids => 'uuid[]', viewer_user_id => 'uuid' ]
    },
    community_react_post => {
        version    => 2,
        parameters => [ row => 'jsonb' ],
        json       => ['result']
    },
    community_unreact_post => {
        version    => 2,
        parameters => [ row => 'jsonb' ],
        json       => ['result']
    },
    community_react_command => {
        version    => 2,
        parameters => [ log => 'jsonb', answer => 'jsonb', row => 'jsonb' ],
        json       => ['response']
    },
    community_unreact_command => {
        version    => 2,
        parameters => [ log => 'jsonb', answer => 'jsonb', row => 'jsonb' ],
        json       => ['response']
    },
    community_subscribe_command => {
        version    => 2,
        parameters => [ log => 'jsonb', answer => 'jsonb', row => 'jsonb' ],
        json       => ['response']
    },
    community_relation_set => {
        version    => 2,
        parameters => [
            owner_user_id => 'uuid',
            username      => 'text',
            kind          => 'text',
            now           => 'timestamptz',
        ],
    },
    community_relation_remove => {
        version    => 2,
        parameters => [ owner_user_id => 'uuid', username => 'text' ],
    },
    community_relation_list =>
      { version => 2, parameters => [ owner_user_id => 'uuid' ] },
    community_relation_between => {
        version    => 2,
        parameters => [ owner_user_id => 'uuid', other_user_id => 'uuid' ],
    },

    # ADR 0139: direct messages between two members.
    community_message_start =>
      { version => 2, parameters => [ row => 'jsonb' ] },
    community_message_reply =>
      { version => 2, parameters => [ row => 'jsonb' ] },
    community_message_inbox => {
        version    => 2,
        parameters => [
            user_id   => 'uuid',
            after_at  => 'timestamptz',
            after_id  => 'uuid',
            row_limit => 'integer'
        ]
    },
    community_message_conversation => {
        version    => 2,
        parameters => [ conversation_id => 'uuid', user_id => 'uuid' ]
    },
    community_message_list => {
        version    => 2,
        parameters => [
            conversation_id => 'uuid',
            user_id         => 'uuid',
            before_position => 'bigint',
            row_limit       => 'integer'
        ]
    },
    community_message_mark_read => {
        version    => 2,
        parameters => [
            conversation_id => 'uuid',
            user_id         => 'uuid',
            now             => 'timestamptz'
        ]
    },
    community_message_conversation_with => {
        version    => 2,
        parameters => [ user_id => 'uuid', username => 'text' ]
    },
    community_message_for_report => {
        version    => 2,
        parameters => [ message_id => 'uuid', user_id => 'uuid' ]
    },
    community_message_participant => {
        version    => 2,
        parameters => [ message_id => 'uuid', user_id => 'uuid' ]
    },

    # Members' profile pictures (ADR 0144).
    community_avatar_offer => {
        version    => 2,
        parameters => [
            user_id       => 'uuid',
            attachment_id => 'uuid',
            now           => 'timestamptz'
        ]
    },
    community_avatar_settle => {
        version    => 2,
        parameters => [
            user_id       => 'uuid',
            attachment_id => 'uuid',
            outcome       => 'text',
            now           => 'timestamptz'
        ]
    },
    community_avatar_remove => {
        version    => 2,
        parameters =>
          [ user_id => 'uuid', attachment_id => 'uuid', audit => 'jsonb' ]
    },
    community_avatar_status =>
      { version => 2, parameters => [ user_id => 'uuid' ] },
    community_avatar_image => {
        version    => 2,
        parameters => [ user_id => 'uuid', variant_type => 'text' ]
    },
    community_avatar_objects => {
        version    => 2,
        parameters => [ user_id => 'uuid', attachment_id => 'uuid' ]
    },
    community_find_bookmark => {
        version    => 2,
        parameters =>
          [ user_id => 'uuid', target_type => 'text', target_id => 'uuid' ]
    },
    community_stamp_bookmark => {
        version    => 4,
        parameters => [
            user_id     => 'uuid',
            target_type => 'text',
            target_id   => 'uuid',
            column      => 'text',
            stamped_at  => 'text'
        ],
        json => ['result']
    },
    community_project_feed => {
        version    => 2,
        parameters => [ row => 'jsonb', user_ids => 'uuid[]' ],
        json       => ['result']
    },
    community_remove_feed => {
        version    => 2,
        parameters => [ item_type => 'text', item_id => 'uuid' ],
        json       => ['result']
    },
    community_remove_thread_feed => {
        version    => 2,
        parameters => [ thread_id => 'uuid' ],
        json       => ['result']
    },
    community_resolve_mention_users =>
      { version => 2, parameters => [ usernames => 'text[]' ] },
    community_create_mention =>
      { version => 2, parameters => [ row => 'jsonb' ], json => ['result'] },
    community_record_reputation =>
      { version => 2, parameters => [ row => 'jsonb' ], json => ['result'] },
);

sub entries ($class) {
    return \%FUNCTION;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::SqlFunctionCatalogue::Community - The PostgreSQL functions of the community: messages, relations, reports, avatars and protocol targets.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $entries = GPForum::Infrastructure::SqlFunctionCatalogue::Community->entries;

=head1 DESCRIPTION

A part of the table L<GPForum::Infrastructure::SqlFunctionCatalogue> reads:
the entries for the functions of the community: messages, relations, reports, avatars and protocol targets. See that module for what an
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
