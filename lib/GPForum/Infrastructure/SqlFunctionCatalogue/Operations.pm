# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::SqlFunctionCatalogue::Operations;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my %FUNCTION => (

    integration_announcement_retry => {
        version    => 2,
        parameters =>
          [ actor => 'uuid', announcement => 'uuid', target_hash => 'text' ],
        json => ['result']
    },

    integration_public_categories =>
      { version => 2, parameters => [], json => ['result'] },
    integration_announcement_payload => {
        version    => 2,
        parameters => [ announcement => 'uuid' ],
        json       => ['result']
    },
    integration_public_topics =>
      { version => 2, parameters => [], json => ['result'] },
    integration_announcement_request => {
        version    => 2,
        parameters => [
            actor        => 'uuid',
            announcement => 'uuid',
            thread       => 'uuid',
            target_hash  => 'text'
        ],
        json => ['result']
    },
    integration_announcement_claim => {
        version    => 2,
        parameters => [ announcement => 'uuid' ],
        json       => ['result']
    },
    integration_announcement_finish => {
        version    => 2,
        parameters =>
          [ announcement => 'uuid', status => 'text', remote_id => 'text' ],
        json => ['result']
    },
    integration_announcement_list =>
      { version => 2, parameters => [], json => ['result'] },
    integration_feed_begin => {
        version    => 2,
        parameters => [ source_hash => 'text', source_url => 'text' ],
        json       => ['result']
    },
    integration_feed_finish => {
        version    => 2,
        parameters =>
          [ source_hash => 'text', etag => 'text', modified => 'text' ],
        json => ['result']
    },
    integration_feed_stage => {
        version    => 2,
        parameters => [
            item          => 'uuid',
            source_hash   => 'text',
            identity_hash => 'text',
            url_hash      => 'text',
            title         => 'text',
            url           => 'text'
        ],
        json => ['result']
    },
    integration_feed_queue =>
      { version => 2, parameters => [ after => 'uuid' ], json => ['result'] },
    integration_feed_find => {
        version    => 2,
        parameters => [ item => 'uuid', actor => 'uuid' ],
        json       => ['result']
    },
    integration_feed_decide => {
        version    => 2,
        parameters => [
            actor  => 'uuid',
            item   => 'uuid',
            status => 'text',
            thread => 'uuid'
        ],
        json => ['result']
    },
    ops_doctor_outbox => {
        version    => 2,
        parameters => [],
    },

    ops_partition_horizon => {
        version    => 2,
        parameters => [],
    },

    privacy_insert => {
        version    => 2,
        parameters => [ source => 'text', row => 'jsonb' ],
        json       => ['document']
    },
    privacy_find => {
        version    => 2,
        parameters => [ source => 'text', id => 'uuid', lock_row => 'boolean' ],
        json       => ['document']
    },
    privacy_release_hold => {
        version    => 2,
        parameters => [ hold_id => 'uuid', ended_at => 'timestamptz' ],
        json       => [qw(hold request)]
    },
    privacy_latest => {
        version    => 2,
        parameters => [ source => 'text', query => 'jsonb' ],
        json       => ['document']
    },
    privacy_review => {
        version    => 2,
        parameters => [
            source    => 'text',
            query     => 'jsonb',
            row_limit => 'integer',
            oldest    => 'boolean'
        ],
        json => ['document']
    },
    privacy_update => {
        version    => 4,
        parameters => [ source => 'text', id => 'uuid', changes => 'jsonb' ],
        json       => ['document']
    },
    privacy_revoke_user => {
        version    => 34,
        parameters => [ source => 'text', user_id => 'uuid', at => 'text' ]
    },
    privacy_may_export => { version => 2, parameters => [ user_id => 'uuid' ] },
    privacy_discard_exports => {
        version    => 2,
        parameters => [ user_id => 'uuid' ],
        json       => ['document']
    },
    portability_export_parts => {
        version    => 34,
        parameters => [ user_id => 'uuid' ],
        json       => ['document']
    },

    ops_publish_notification =>
      { version => 2, parameters => [ channel => 'text', payload => 'text' ] },
    ops_publish_notifications => {
        version    => 2,
        parameters => [ channel => 'text', payloads => 'text[]' ],
    },
    ops_retention_purge => {
        version    => 6,
        parameters =>
          [ source => 'text', cutoff => 'timestamptz', row_limit => 'integer' ]
    },
    ops_outbox_metrics =>
      { version => 4, parameters => [ now => 'timestamptz' ] },
    ops_readiness_probe => { version => 4, parameters => [ source => 'text' ] },
    ops_query_budget_list =>
      { version => 2, parameters => [ row_limit => 'integer' ] },
    ops_query_budget_sync => {
        version    => 2,
        parameters => [ rows => 'jsonb', endpoint_names => 'text[]' ]
    },
    ops_partition_registry => { version => 2, parameters => [] },
    ops_realtime_settled   =>
      { version => 2, parameters => [ settle_seconds => 'integer' ] },
    ops_realtime_poll => {
        version    => 6,
        json       => ['payload'],
        parameters => [
            after_next_at    => 'timestamptz',
            after_created_at => 'timestamptz',
            after_id         => 'uuid',
            settled_at       => 'timestamptz',
            settle_seconds   => 'integer',
            row_limit        => 'integer'
        ]
    },
    ops_replication_recovery => { version => 2, parameters => [] },
    ops_replication_standbys => { version => 2, parameters => [] },
    ops_replication_slots    =>
      { version => 2, parameters => [ standby => 'boolean' ] },
    ops_replication_position => { version => 2, parameters => [] },

    ops_record_event => {
        version    => 2,
        parameters => [
            event         => 'jsonb',
            outbox_id     => 'text',
            outbox_extras => 'jsonb',
            explicit      => 'boolean'
        ],
        json => ['event']
    },
    ops_record_audit => {
        version    => 2,
        parameters => [ audit => 'jsonb', explicit => 'boolean' ],
        json       => ['audit']
    },
    ops_audit_chain_verify => {
        version    => 2,
        parameters => [ chain_key => 'text' ],
    },
    ops_event_recorded => { version => 2, parameters => [ key => 'text' ] },
    ops_command_lookup => {
        version    => 2,
        parameters => [ key => 'text', command_id => 'uuid' ],
        json       => ['document']
    },
    ops_command_insert => {
        version    => 2,
        parameters => [ command => 'jsonb' ],
        json       => ['document']
    },
    ops_command_finish => {
        version    => 2,
        parameters => [ command_id => 'uuid', changes => 'jsonb' ]
    },
    ops_event_claim => {
        version    => 4,
        parameters => [
            operation      => 'text',
            key            => 'text',
            event_id       => 'text',
            now            => 'text',
            expired_before => 'text',
            token          => 'uuid'
        ]
    },
    outbox_claim_ready => {
        version    => 6,
        parameters => [
            now          => 'text',
            locked_until => 'text',
            worker_id    => 'text',
            row_limit    => 'integer'
        ],
        json => ['payload']
    },
    outbox_owned_write => {
        version    => 4,
        parameters =>
          [ outbox_id => 'uuid', worker_id => 'text', changes => 'jsonb' ]
    },
    outbox_dead_letter =>
      { version => 2, parameters => [ letter => 'jsonb' ], json => ['letter'] },
    outbox_replay_dead_letter => {
        version    => 2,
        parameters => [ input => 'jsonb', ids => 'jsonb', now => 'text' ],
        json       => ['result']
    },
    ops_worker_aggregate => {
        version    => 2,
        parameters => [ aggregate_type => 'text', aggregate_id => 'uuid' ]
    },
    ops_thread_activity =>
      { version => 4, parameters => [ thread_id => 'uuid', at => 'text' ] },
    ops_rate_limit_check => {
        version    => 2,
        parameters => [
            scope          => 'text',
            actor_hash     => 'text',
            action         => 'text',
            window_start   => 'timestamptz',
            window_seconds => 'integer',
            limit          => 'integer',
            now            => 'timestamptz',
            expires_at     => 'timestamptz',
        ],
    },
    ops_rate_limit_snapshot => {
        version    => 2,
        parameters => [
            now => 'timestamptz',
        ],
    },
);

sub entries ($class) {
    return \%FUNCTION;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::SqlFunctionCatalogue::Operations - The PostgreSQL functions of operations: the outbox, partitions, workers, privacy, portability and integrations.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $entries = GPForum::Infrastructure::SqlFunctionCatalogue::Operations->entries;

=head1 DESCRIPTION

A part of the table L<GPForum::Infrastructure::SqlFunctionCatalogue> reads:
the entries for the functions of operations: the outbox, partitions, workers, privacy, portability and integrations. See that module for what an
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
