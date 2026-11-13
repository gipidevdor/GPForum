# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::SqlFunctionCatalogue::Forum;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# A reply command's post, body and revision as api.forum_create_reply_v4
# takes them, and the ids and the time the write records under.
const my @REPLY_COMMAND => (
    post_id             => 'text',
    thread_id           => 'text',
    author_user_id      => 'text',
    current_body_id     => 'text',
    current_revision_id => 'text',
    position            => 'bigint',
    visibility          => 'text',
    moderation_state    => 'text',
    version             => 'bigint',
    visibility_version  => 'bigint',
    permission_version  => 'bigint',
    hidden_at           => 'text',
    locked_at           => 'text',
    deleted_at          => 'text',
    deleted_by          => 'text',
    body_id             => 'text',
    body_post_id        => 'text',
    body_format         => 'text',
    body_source         => 'text',
    body_rendered_safe  => 'text',
    source_hash         => 'text',
    revision_id         => 'text',
    revision_post_id    => 'text',
    revision_body_id    => 'text',
    editor_user_id      => 'text',
    revision_number     => 'integer',
    edit_reason         => 'text',
);
const my @REPLY_RECORD => (
    correlation_id => 'text',
    event_id       => 'text',
    outbox_id      => 'text',
    audit_id       => 'text',
    recorded_at    => 'text',
);

const my %FUNCTION => (
    forum_protocol_unsigned_bodies =>
      { version => 4, parameters => [ after => 'uuid' ] },
    forum_protocol_attest_body => {
        version    => 2,
        parameters => [
            body_id  => 'uuid',
            post_id  => 'uuid',
            source   => 'text',
            envelope => 'jsonb'
        ]
    },
    forum_sitemap_count => { version => 2, parameters => [] },
    forum_sitemap_page => { version => 2, parameters => [ page => 'integer' ] },
    forum_protocol_signature => {
        version    => 2,
        parameters => [ body_id => 'uuid' ],
        json       => ['envelope']
    },
    forum_protocol_signatures => {
        version    => 2,
        parameters => [ body_ids => 'uuid[]' ],
        json       => ['envelope']
    },
    forum_protocol_member =>
      { version => 2, parameters => [ user_id => 'uuid', email => 'text' ] },
    forum_thread_redirect =>
      { version => 2, parameters => [ actor => 'uuid', thread_id => 'uuid' ] },
    forum_poll_read => {
        version    => 4,
        parameters => [ actor => 'uuid', thread_id => 'uuid' ],
        json       => ['result']
    },
    forum_poll_change => {
        version    => 8,
        parameters => [
            actor     => 'uuid',
            command   => 'uuid',
            thread_id => 'uuid',
            operation => 'text',
            values    => 'jsonb'
        ],
        json => ['result']
    },
    forum_draft_find => {
        version    => 2,
        parameters =>
          [ owner_user_id => 'uuid', draft_id => 'uuid', now => 'timestamptz' ],
        json => ['draft'],
    },
    forum_draft_list => {
        version    => 2,
        parameters => [ owner_user_id => 'uuid', now => 'timestamptz' ],
        json       => ['draft'],
    },
    forum_draft_save => {
        version    => 4,
        parameters => [
            owner_user_id  => 'uuid',
            draft_id       => 'uuid',
            draft_revision => 'bigint',
            kind           => 'text',
            category_id    => 'uuid',
            thread_id      => 'uuid',
            title          => 'text',
            body_source    => 'text',
            visibility     => 'text',
            command_id     => 'text',
            now            => 'timestamptz'
        ],
        json => ['draft'],
    },
    forum_draft_remove => {
        version    => 2,
        parameters => [
            owner_user_id  => 'uuid',
            draft_id       => 'uuid',
            draft_revision => 'bigint',
            now            => 'timestamptz'
        ],
        json => ['draft'],
    },
    forum_draft_purge => {
        version    => 2,
        parameters => [ now => 'timestamptz', row_limit => 'integer' ],
    },
    forum_active_announcements =>
      { version => 2, parameters => [ row_limit => 'integer' ] },

    forum_read_state => {
        version    => 2,
        parameters => [ user_id => 'uuid', thread_id => 'uuid' ]
    },
    forum_mark_read =>
      { version => 2, parameters => [ row => 'jsonb' ], json => ['result'] },

    # The thread actions as one call each (ADR 0126, section 5): the command
    # log and the work, with the answer the workflow records. p_answer is a
    # refusal decided before the call, recorded without the work.
    forum_read_marker_command => {
        version    => 2,
        parameters => [ log => 'jsonb', answer => 'jsonb', row => 'jsonb' ],
        json       => ['response']
    },
    forum_link_reply => {
        version    => 4,
        parameters => [ post_id => 'uuid', reply_to_post_id => 'uuid' ]
    },
    forum_reply_targets =>
      { version => 2, parameters => [ post_ids => 'uuid[]' ] },
    forum_set_thread_tags => {
        version    => 4,
        parameters =>
          [ thread_id => 'uuid', slugs => 'text[]', names => 'text[]' ]
    },
    forum_thread_tags =>
      { version => 2, parameters => [ thread_ids => 'uuid[]' ] },
    forum_filter_tagged_threads => {
        version    => 2,
        parameters => [
            tag_slugs       => 'text[]',
            tag_match       => 'text',
            category_id     => 'uuid',
            member          => 'boolean',
            global_read     => 'boolean',
            scope_user_id   => 'uuid',
            category_ids    => 'uuid[]',
            space_ids       => 'uuid[]',
            row_limit       => 'integer',
            after_activity  => 'timestamptz',
            after_thread_id => 'uuid'
        ],
    },
    forum_list_tagged_threads => {
        version    => 2,
        parameters => [
            tag_slug      => 'text',
            category_id   => 'uuid',
            member        => 'boolean',
            global_read   => 'boolean',
            scope_user_id => 'uuid',
            category_ids  => 'uuid[]',
            space_ids     => 'uuid[]',
            row_limit     => 'integer'
        ]
    },
    forum_list_tags => {
        version    => 2,
        parameters => [
            member        => 'boolean',
            global_read   => 'boolean',
            scope_user_id => 'uuid',
            category_ids  => 'uuid[]',
            space_ids     => 'uuid[]',
            row_limit     => 'integer'
        ]
    },
    forum_resolve_viewer => {
        version    => 10,
        parameters => [
            user_id => 'uuid',
        ],
        json => ['grants'],
    },
    forum_store_write => {
        version    => 8,
        parameters =>
          [ store_type => 'text', command => 'jsonb', record => 'jsonb' ],
        json => ['stored'],
    },
    forum_write_command => {
        version    => 10,
        parameters => [
            log            => 'jsonb',
            answer         => 'jsonb',
            store_type     => 'text',
            command        => 'jsonb',
            record         => 'jsonb',
            draft_id       => 'uuid',
            draft_revision => 'bigint',
        ],
        json => [qw(response stored)],
    },
    forum_find_category => {
        version    => 2,
        parameters => [ category_id => 'uuid' ],
    },
    forum_list_categories => {
        version    => 4,
        parameters => [
            member       => 'boolean',
            global_read  => 'boolean',
            category_ids => 'uuid[]',
            space_ids    => 'uuid[]',
            row_limit    => 'integer'
        ],
    },
    forum_list_category_threads => {
        version    => 4,
        parameters => [
            category_id     => 'uuid',
            member          => 'boolean',
            global_read     => 'boolean',
            scope_user_id   => 'uuid',
            viewer_user_id  => 'uuid',
            after_pinned    => 'boolean',
            after_activity  => 'timestamptz',
            after_thread_id => 'uuid',
            row_limit       => 'integer'
        ],
    },
    forum_list_public_threads => {
        version    => 6,
        parameters => [
            member          => 'boolean',
            global_read     => 'boolean',
            category_ids    => 'uuid[]',
            space_ids       => 'uuid[]',
            after_activity  => 'timestamptz',
            after_thread_id => 'uuid',
            row_limit       => 'integer'
        ],
    },
    forum_find_post => {
        version    => 2,
        parameters => [ post_id => 'uuid' ],
    },
    forum_post_context => {
        version    => 2,
        parameters => [ post_id => 'uuid' ],
        json       => [qw(post thread)],
    },
    forum_find_visible_post => {
        version    => 2,
        parameters => [ post_id => 'uuid' ],
    },
    forum_find_listed_post => {
        version    => 4,
        parameters => [
            post_id        => 'uuid',
            thread_id      => 'uuid',
            member         => 'boolean',
            global_read    => 'boolean',
            scope_user_id  => 'uuid',
            viewer_user_id => 'uuid'
        ],
    },
    forum_thread_placement => {
        version    => 2,
        parameters => [ source_id => 'uuid' ],
    },
    forum_post_placement => {
        version    => 2,
        parameters => [ source_id => 'uuid' ],
    },
    forum_thread_page_snapshot => {
        version    => 2,
        parameters => [
            thread_id        => 'uuid',
            viewer_user_id   => 'uuid',
            member           => 'boolean',
            global_read      => 'boolean',
            category_ids     => 'uuid[]',
            space_ids        => 'uuid[]',
            after_position   => 'bigint',
            after_post_id    => 'uuid',
            page_limit       => 'integer',
            link_target_type => 'text',
            links_per_post   => 'integer',
        ],
        json => [qw(thread_head posts page_reads)],
    },
    forum_thread_page_head => {
        version    => 2,
        parameters => [ thread_id => 'uuid' ],
    },
    forum_thread_page_posts => {
        version    => 4,
        parameters => [
            thread_id      => 'uuid',
            standing       => 'text',
            viewer_user_id => 'uuid',
            after_position => 'bigint',
            after_post_id  => 'uuid',
            row_limit      => 'integer',
        ],
    },

    # The seven reads a thread page makes once it has its
    # posts, in one call (GPForum::Service::Forum::ThreadPageReads).
    forum_thread_page_reads => {
        version    => 8,
        parameters => [
            thread_id              => 'uuid',
            post_ids               => 'uuid[]',
            viewer_user_id         => 'uuid',
            engagement_target_type => 'text',
            link_target_type       => 'text',
            link_post_ids          => 'uuid[]',
            link_row_limit         => 'integer',
        ],
    },
    forum_create_reply => {
        version    => 8,
        parameters => [
            idempotency_key        => 'text',
            command_type           => 'text',
            actor_id               => 'text',
            request_hash           => 'text',
            command_id             => 'text',
            command_correlation_id => 'text',
            command_at             => 'text',
            answer                 => 'jsonb',
            store_refusals         => 'jsonb',
            @REPLY_COMMAND,
            @REPLY_RECORD,
            draft_id       => 'uuid',
            draft_revision => 'bigint',
            post_signature => 'jsonb',
        ],
        json => ['response'],
    },
);

sub entries ($class) {
    return \%FUNCTION;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::SqlFunctionCatalogue::Forum - The PostgreSQL functions of the forum: categories, threads, posts, read state and the thread page.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $entries = GPForum::Infrastructure::SqlFunctionCatalogue::Forum->entries;

=head1 DESCRIPTION

A part of the table L<GPForum::Infrastructure::SqlFunctionCatalogue> reads:
the entries for the functions of the forum: categories, threads, posts, read state and the thread page. See that module for what an
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
