# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::AutomodStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
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
has recorder   => sub ($self) {
    return GPForum::Infrastructure::EventRecorder->new(
        id_service => $self->id_service,
        schema     => $self->schema,
    );
};
__PACKAGE__->requires(qw(schema));

# A schema without the function layer -- the in-memory doubles -- has no
# rules: a write is not screened, and staff changes are unavailable.
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

# The rules a write by the author is screened by, or undef with no function
# layer.
sub rules_for ( $self, $user_id ) {
    return undef if !$self->functions;
    my $row = $self->functions->row( 'moderation_automod_rules',
        { user_id => _uuid_or_undef($user_id) } );

    return $row ? $row->{document} : undef;
}

sub words ($self) {
    return [] if !$self->functions;

    return $self->functions->rows( 'moderation_watched_word_list', {} );
}

# Adds a watched word. Answers ok with the word, or a refusal: invalid
# (with the field), duplicate or limit.
sub add_word ( $self, $input ) {
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

    my $word_id = $self->id_service->uuid;
    my $now     = $self->clock->now_iso8601;
    my $row     = $self->_functions->row(
        'moderation_watched_word_add',
        {
            word_id       => $word_id,
            phrase        => $phrase,
            action        => $action,
            replacement   => $replacement,
            actor_user_id => $input->{actor_user_id},
            now           => $now,
            audit         => $self->_audit(
                $WORD_ADDED,
                $input->{actor_user_id},
                $word_id,
                {
                    phrase      => $phrase,
                    action      => $action,
                    replacement => $replacement,
                },
                $now,
            ),
        }
    ) || { status => 'invalid' };
    my $status = $row->{status} // 'invalid';
    return { ok => 0, status => $status } if $status ne 'ok';

    return {
        ok     => 1,
        status => 'ok',
        word   => {
            word_id     => $word_id,
            phrase      => $phrase,
            action      => $action,
            replacement => $replacement,
        },
    };
}

# Takes a watched word off the list; one not listed is no error.
sub remove_word ( $self, $input ) {
    my $word_id = $input->{word_id} // q{};
    return { ok => 1, status => 'ok', removed => 0 }
      if !GPForum::Infrastructure::Id->is_uuid_spelling($word_id);

    my $row = $self->_functions->row(
        'moderation_watched_word_remove',
        {
            word_id => $word_id,
            audit   => $self->_audit(
                $WORD_REMOVED, $input->{actor_user_id},
                $word_id, {},
                $self->clock->now_iso8601,
            ),
        }
    );

    return { ok => 1, status => 'ok', removed => 0 + ( $row->{removed} // 0 ) };
}

# Sets the link rule: an empty limit turns it off. Answers ok, unchanged
# or invalid (with the field).
sub set_link_rule ( $self, $input ) {
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

    my $now = $self->clock->now_iso8601;
    my $row = $self->_functions->row(
        'moderation_automod_settings_set',
        {
            link_limit       => $limit,
            link_trust_below => $below,
            link_action      => $action,
            actor_user_id    => $input->{actor_user_id},
            now              => $now,
            audit            => $self->_audit(
                $LINKS_SET,
                $input->{actor_user_id},
                undef,
                {
                    link_limit       => $limit,
                    link_trust_below => $below,
                    link_action      => $action,
                },
                $now,
            ),
        }
    ) || { status => 'invalid' };
    my $status = $row->{status} // 'invalid';

    return { ok => ( $status eq 'invalid' ? 0 : 1 ), status => $status };
}

# Records the decisions of one write in one call: the system's report
# when the content is flagged (with its report.created event and audit),
# and the audit of every decision. Answers the report's id and whether it
# was created (an open system report on the target is reused).
sub record_decisions ( $self, $input ) {
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

    my $row = $self->_functions->row(
        'moderation_automod_record',
        {
            report          => $report,
            event           => $event ? $event->{event}     : undef,
            event_outbox_id => $event ? $event->{outbox_id} : undef,
            report_audit    => $report_audit,
            audits          => [
                map { $self->recorder->audit_call( %{$_} )->{audit} }
                  @{ $input->{audits} // [] }
            ],
        }
    ) // {};

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

=head2 words

The list as the admin console shows it.

=head2 add_word

Adds a watched word: ok with the word, or invalid (naming the field),
duplicate or limit.

=head2 remove_word

Removes a watched word; C<removed> says whether it was listed.

=head2 set_link_rule

Sets the link rule: ok, unchanged, or invalid naming the field.

=head2 record_decisions

Records a write's decisions: the system report when flagged, and the audit
of each decision.

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

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
