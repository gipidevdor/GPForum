# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::AutomodStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::Service::Moderation::Automod;
use GPForum::Service::Moderation::Event;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

# ADR 0133: the audit actions of the rules staff change.
const my $WORD_ADDED   => 'automod.word_added';
const my $WORD_REMOVED => 'automod.word_removed';
const my $LINKS_SET    => 'automod.link_rule_set';
const my $TARGET       => 'automod_rule';
const my $SCHEMA       => 1;

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };
has automod    => sub { return GPForum::Service::Moderation::Automod->new; };
has events     => sub { return GPForum::Service::Moderation::Event->new; };
has recorder   => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));

# A schema without the function layer -- the in-memory doubles -- has no
# rules: a write is not screened, and staff changes are unavailable.
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# The rules a write by the author is screened by, or undef with no function
# layer.
sub rules_for ( $self, $user_id ) {
    return undef if !$self->functions;
    my $row = $self->functions->row( 'moderation_automod_rules',
        { user_id => _uuid_or_undef($user_id) } );

    return $row ? $row->{document} : undef;
}

# The rules and the word list on the worker's pooled asynchronous
# connections, not a forked child with a connection of its own each.
async sub rules_for_p ( $self, $user_id, $context = undef ) {
    return undef if !$self->functions;
    my $row = await $self->functions->row_p( 'moderation_automod_rules',
        { user_id => _uuid_or_undef($user_id) }, $context );

    return $row ? $row->{document} : undef;
}

sub words ($self) {
    return [] if !$self->functions;

    return $self->functions->rows( 'moderation_watched_word_list', {} );
}

async sub words_p ( $self, $context = undef ) {
    return [] if !$self->functions;

    return await $self->functions->rows_p( 'moderation_watched_word_list', {},
        $context );
}

# Adds a watched word. Answers ok with the word, or a refusal: invalid
# (with the field), duplicate or limit.
sub add_word ( $self, $input ) {
    return $self->_settle( $self->_add_word_call($input) );
}

# The same staff change on the worker's pooled asynchronous connections,
# not a forked child with a connection of its own; as are remove_word_p
# and set_link_rule_p.
async sub add_word_p ( $self, $input, $context = undef ) {
    return $self->add_word($input) if !$self->functions;
    return await $self->_settle_p( $context, $self->_add_word_call($input) );
}

# Takes a watched word off the list; one not listed is no error.
sub remove_word ( $self, $input ) {
    return $self->_settle( $self->_remove_word_call($input) );
}

async sub remove_word_p ( $self, $input, $context = undef ) {
    return $self->remove_word($input) if !$self->functions;
    return await $self->_settle_p( $context, $self->_remove_word_call($input) );
}

# Sets the link rule: an empty limit turns it off. Answers ok, unchanged
# or invalid (with the field).
sub set_link_rule ( $self, $input ) {
    return $self->_settle( $self->_link_rule_call($input) );
}

async sub set_link_rule_p ( $self, $input, $context = undef ) {
    return $self->set_link_rule($input) if !$self->functions;
    return await $self->_settle_p( $context, $self->_link_rule_call($input) );
}

# A staff change is a refusal, or undef with the function's name, its
# values and the sub that answers from the function's row.
sub _settle ( $self, $refusal, $name = undef, $values = undef, $answer = undef )
{
    return $refusal if $refusal;
    return $answer->( $self->_functions->row( $name, $values ) );
}

async sub _settle_p (
    $self, $context, $refusal,
    $name   = undef,
    $values = undef,
    $answer = undef
  )
{
    return $refusal if $refusal;
    return $answer->(
        await $self->_functions->row_p( $name, $values, $context ) );
}

sub _add_word_call ( $self, $input ) {
    my $automod     = $self->automod;
    my $phrase      = $automod->phrase( $input->{phrase} );
    my $replacement = $automod->replacement( $input->{replacement} );
    my $action      = $input->{action} // q{};
    return _invalid('phrase')      if !defined $phrase;
    return _invalid('action')      if !$automod->is_action($action);
    return _invalid('replacement') if !defined $replacement;
    if ( $action ne 'replace' ) {
        $replacement = q{};
    }

    my $word = {
        word_id     => $self->id_service->uuid,
        phrase      => $phrase,
        action      => $action,
        replacement => $replacement,
    };
    my $now = $self->clock->now_iso8601;
    return (
        undef,
        'moderation_watched_word_add',
        {
            %{$word},
            actor_user_id => $input->{actor_user_id},
            now           => $now,
            audit         => $self->_audit(
                $WORD_ADDED,
                $input->{actor_user_id},
                $word->{word_id},
                {
                    phrase      => $phrase,
                    action      => $action,
                    replacement => $replacement,
                },
                $now,
            ),
        },
        sub ($row) {
            my $status = ( $row || {} )->{status} // 'invalid';
            return { ok => 0, status => $status } if $status ne 'ok';
            return { ok => 1, status => 'ok', word => $word };
        },
    );
}

sub _remove_word_call ( $self, $input ) {
    my $word_id = $input->{word_id} // q{};
    return { ok => 1, status => 'ok', removed => 0 }
      if !GPForum::Infrastructure::Id->is_uuid_spelling($word_id);

    return (
        undef,
        'moderation_watched_word_remove',
        {
            word_id => $word_id,
            audit   => $self->_audit(
                $WORD_REMOVED, $input->{actor_user_id},
                $word_id, {},
                $self->clock->now_iso8601,
            ),
        },
        sub ($row) {
            return {
                ok      => 1,
                status  => 'ok',
                removed => 0 + ( $row->{removed} // 0 )
            };
        },
    );
}

sub _link_rule_call ( $self, $input ) {
    my $automod = $self->automod;
    my $limit   = $automod->link_limit( $input->{link_limit} );
    my $below   = $automod->trust_level( $input->{link_trust_below} );
    my $action  = $input->{link_action} // q{};
    return _invalid('link_limit')       if !defined $limit;
    return _invalid('link_trust_below') if !defined $below;
    return _invalid('link_action')      if !$automod->is_link_action($action);
    if ( $limit eq q{} ) {
        $limit = undef;
    }

    my $rule = {
        link_limit       => $limit,
        link_trust_below => $below,
        link_action      => $action,
    };
    my $now = $self->clock->now_iso8601;
    return (
        undef,
        'moderation_automod_settings_set',
        {
            %{$rule},
            actor_user_id => $input->{actor_user_id},
            now           => $now,
            audit         => $self->_audit(
                $LINKS_SET, $input->{actor_user_id},
                undef, { %{$rule} },
                $now,
            ),
        },
        sub ($row) {
            my $status = ( $row || {} )->{status} // 'invalid';
            return {
                ok     => ( $status eq 'invalid' ? 0 : 1 ),
                status => $status
            };
        },
    );
}

# Records the decisions of one write in one call: the system's report
# when the content is flagged (with its report.created event and audit),
# and the audit of every decision. Answers the report's id and whether it
# was created (an open system report on the target is reused).
sub record_decisions ( $self, $input ) {
    return _decisions_recorded(
        $self->_functions->row(
            'moderation_automod_record', $self->_decisions_values($input)
        )
    );
}

# The same call on a pooled asynchronous connection, or on the transaction
# $functions belongs to (the write's own, when the write is recorded with
# its decisions).
async sub record_decisions_p ( $self, $input, $context = undef,
    $functions = undef )
{
    return $self->record_decisions($input)
      if !$functions && !$self->functions;
    $functions //= $self->functions;
    return _decisions_recorded(
        await $functions->row_p(
            'moderation_automod_record', $self->_decisions_values($input),
            $context
        )
    );
}

sub _decisions_values ( $self, $input ) {
    my ( $report, $event, $report_audit );
    if ( my $flag = $input->{report} ) {
        $report = {
            report_id        => $self->id_service->uuid,
            reporter_user_id => undef,
            target_type      => $flag->{target_type},
            target_id        => $flag->{target_id},
            reason           => $flag->{reason},
            details          => $flag->{details} // q{},
            status           => 'open',
            created_at       => $self->clock->now_iso8601,
        };
        my $recorded = {
            correlation_id => $self->id_service->uuid,
            report         => $report,
        };
        $event = $self->recorder->event_call(
            %{ $self->events->report_created_envelope($recorded) } );
        $report_audit = $self->recorder->audit_call(
            %{ $self->events->report_created_audit($recorded) } )->{audit};
    }

    return {
        report          => $report,
        event           => $event ? $event->{event}     : undef,
        event_outbox_id => $event ? $event->{outbox_id} : undef,
        report_audit    => $report_audit,
        audits          => [
            map { $self->recorder->audit_call( %{$_} )->{audit} }
              @{ $input->{audits} // [] }
        ],
    };
}

sub _decisions_recorded ($row) {
    $row //= {};
    return {
        report_id => $row->{report_id},
        flagged   => $row->{flagged} ? 1 : 0,
    };
}

# Runs the code in one transaction of the store's schema.
sub in_transaction ( $self, $code ) {
    return $self->schema->txn_do($code);
}

sub _audit ( $self, $action, $actor_id, $target_id, $metadata, $now ) {
    return $self->recorder->audit_call(
        action         => $action,
        actor_id       => $actor_id,
        created_at     => $now,
        metadata       => $metadata,
        schema_version => $SCHEMA,
        target_id      => $target_id,
        target_type    => $TARGET,
    )->{audit};
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'automod rules need the PostgreSQL function layer' );
}

sub _invalid ($field) {
    return { ok => 0, status => 'invalid', field => $field };
}

sub _uuid_or_undef ($value) {
    return GPForum::Infrastructure::Id->is_uuid_spelling( $value // q{} )
      ? $value
      : undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Moderation::AutomodStore - Watched words, the link rule and automod decisions.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Moderation::AutomodStore->new(
        schema => $schema );
    my $rules = $store->rules_for($author_user_id);
    $store->add_word(
        { actor_user_id => $staff, phrase => 'spam*', action => 'flag' } );

=head1 DESCRIPTION

The storage of ADR 0133 through the C<api.moderation_watched_word_*>,
C<api.moderation_automod_settings_set>, C<api.moderation_automod_rules>
and C<api.moderation_automod_record> functions: Perl validates and builds
the audit records and the report's event; each function changes the rules
or records the decisions and their audit in one transaction.

=head1 SUBROUTINES/METHODS

=head2 rules_for

The watched words, the link rule and the author's trust level, or undef
with no function layer.

=head2 rules_for_p

L</rules_for> as a promise, with an optional query context last, read on
the worker's pooled asynchronous connections.

=head2 words

The list as the admin console shows it.

=head2 words_p

L</words> as a promise, with an optional query context, read on the
worker's pooled asynchronous connections.

=head2 add_word

Adds a watched word: ok with the word, or invalid (naming the field),
duplicate or limit.

=head2 add_word_p

L</add_word> as a promise, with an optional query context last, written
on the worker's pooled asynchronous connections.

=head2 remove_word

Removes a watched word; C<removed> says whether it was listed.

=head2 remove_word_p

L</remove_word> as a promise, with an optional query context last,
written on the worker's pooled asynchronous connections.

=head2 set_link_rule

Sets the link rule: ok, unchanged, or invalid naming the field.

=head2 set_link_rule_p

L</set_link_rule> as a promise, with an optional query context last,
written on the worker's pooled asynchronous connections.

=head2 record_decisions

Records a write's decisions: the system report when flagged, and the audit
of each decision.

=head2 record_decisions_p

L</record_decisions> as a promise, with an optional query context and an
optional call layer last: on the worker's pooled asynchronous connections,
or inside the transaction the given call layer belongs to.

=head2 in_transaction

Runs the code inside one transaction of the store's schema.

=head1 DIAGNOSTICS

A write on a schema without the function layer throws
L<GPForum::X::Unavailable>; database errors propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>, L<GPForum::Infrastructure::EventRecorder>.

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
