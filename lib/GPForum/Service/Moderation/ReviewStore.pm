# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::ReviewStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

# ADR 0134: what a held post is audited as, and the rule's bounds.
const my $TARGET         => 'held_post';
const my $RULE_TARGET    => 'automod_rule';
const my $SETTINGS_SET   => 'review.rule_set';
const my $SCHEMA         => 1;
const my $MAXIMUM_FIRST  => 20;
const my $MAXIMUM_REASON => 500;
const my $QUEUE_LIMIT    => 50;
const my $FIRST_POSTS    => qr/\A \d{1,2} \z/amsx;
const my %DECISION_ACTION => (
    approved  => 'review.approved',
    rejected  => 'review.rejected',
    withdrawn => 'review.withdrawn',
);

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };
has recorder   => sub ($self) {
    return GPForum::Infrastructure::EventRecorder->new(
        id_service => $self->id_service,
        schema     => $self->schema,
    );
};
__PACKAGE__->requires(qw(schema));

# A schema without the function layer -- the in-memory doubles -- holds
# nothing: every call is unavailable.
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

sub maximum_first_posts ($self) { return $MAXIMUM_FIRST; }

sub maximum_reason ($self) { return $MAXIMUM_REASON; }

# Holds a post. $input carries the author, the command id, the kind, where
# it goes, its text as composed, why it is held and the draft it was
# written in. Answers the entry: its id, its status and whether it was
# already held under that command id (replayed).
sub hold ( $self, $input ) {
    my $review_id = $self->id_service->uuid;
    my $now       = $self->clock->now_iso8601;
    my $row       = $self->_functions->row(
        'moderation_review_hold',
        {
            review_id          => $review_id,
            author_user_id     => $input->{author_user_id},
            command_id         => $input->{command_id},
            kind               => $input->{kind},
            category_id        => _uuid_or_undef( $input->{category_id} ),
            thread_id          => _uuid_or_undef( $input->{thread_id} ),
            title              => $input->{title} // q{},
            body_source        => $input->{body_source},
            body_rendered_safe => $input->{body_rendered_safe},
            visibility         => $input->{visibility},
            reply_to_post_id   => _uuid_or_undef( $input->{reply_to_post_id} ),
            reason             => $input->{reason},
            details            => $input->{details} // {},
            draft_id           => _uuid_or_undef( $input->{draft_id} ),
            draft_revision     => $input->{draft_revision},
            now                => $now,
            audit              => $self->_audit(
                'review.held',
                $input->{author_user_id},
                $TARGET,
                $review_id,
                {
                    author_user_id => $input->{author_user_id},
                    command_type   => $input->{command_type},
                    kind           => $input->{kind},
                    reason         => $input->{reason},
                    details        => $input->{details} // {},
                },
                $now,
            ),
        }
    ) // {};
    my $status = $row->{status} // 'invalid';
    return { ok => 0, status => 'invalid' } if $status eq 'invalid';

    return {
        ok            => 1,
        status        => $status,
        review_id     => $row->{review_id},
        review_status => $row->{review_status},
        replayed      => $status eq 'replayed' ? 1 : 0,
    };
}

# The pending posts staff review, oldest first.
sub queue ( $self, $limit = $QUEUE_LIMIT ) {
    return $self->_functions->rows( 'moderation_review_queue',
        { row_limit => $limit } );
}

# The author's own held posts: pending, and those decided lately.
sub mine ( $self, $user_id, $viewer, $limit = $QUEUE_LIMIT ) {
    return [] if !GPForum::Infrastructure::Id->is_uuid_spelling($user_id);

    return $self->_functions->rows(
        'moderation_review_mine',
        {
            user_id      => $user_id,
            row_limit    => $limit,
            member       => $viewer->member      ? 1 : 0,
            global_read  => $viewer->global_read ? 1 : 0,
            category_ids => $viewer->category_ids,
            space_ids    => $viewer->space_ids,
        }
    );
}

# One held post, locked for the rest of the transaction; undef when there
# is none.
sub take ( $self, $review_id ) {
    return undef if !GPForum::Infrastructure::Id->is_uuid_spelling($review_id);

    return $self->_functions->row( 'moderation_review_take',
        { review_id => $review_id } );
}

# Records a decision: approved (with the post it became), rejected (with
# a reason) or withdrawn by its author. Answers the function's row: ok,
# unchanged, decided, not_found or invalid, with the entry's status.
sub decide ( $self, $input ) {
    my $review_id = $input->{review_id} // q{};
    return { status => 'not_found' }
      if !GPForum::Infrastructure::Id->is_uuid_spelling($review_id);
    my $decision = $input->{status} // q{};
    return { status => 'invalid' } if !exists $DECISION_ACTION{$decision};

    my $now = $self->clock->now_iso8601;
    return $self->_functions->row(
        'moderation_review_decide',
        {
            review_id     => $review_id,
            status        => $decision,
            actor_user_id => $input->{actor_user_id},
            reason        => $input->{reason} // q{},
            post_id       => _uuid_or_undef( $input->{post_id} ),
            now           => $now,
            audit         => $self->_audit(
                $DECISION_ACTION{$decision},
                $input->{actor_user_id},
                $TARGET,
                $review_id,
                {
                    reason  => $input->{reason} // q{},
                    post_id => $input->{post_id},
                },
                $now,
            ),
        }
    ) // { status => 'not_found' };
}

# Sets the review rule: how many first posts are held (0 is off), and
# whether flagged posts are held too. Answers ok, unchanged or invalid
# (with the field).
sub set_rule ( $self, $input ) {
    my $first = $input->{first_posts} // q{};
    return _invalid('first_posts')
      if $first !~ $FIRST_POSTS || $first > $MAXIMUM_FIRST;
    my $flagged = $input->{flagged} ? 1 : 0;

    my $now = $self->clock->now_iso8601;
    my $row = $self->_functions->row(
        'moderation_review_settings_set',
        {
            first_posts   => 0 + $first,
            flagged       => $flagged,
            actor_user_id => $input->{actor_user_id},
            now           => $now,
            audit         => $self->_audit(
                $SETTINGS_SET,
                $input->{actor_user_id},
                $RULE_TARGET,
                undef,
                {
                    review_first_posts => 0 + $first,
                    review_flagged     => $flagged,
                },
                $now,
            ),
        }
    ) // { status => 'invalid' };
    my $status = $row->{status} // 'invalid';

    return { ok => ( $status eq 'invalid' ? 0 : 1 ), status => $status };
}

# Runs the code in one transaction of the store's schema.
sub in_transaction ( $self, $code ) {
    return $self->schema->txn_do($code);
}

sub _audit ( $self, $action, $actor_id, $type, $target_id, $metadata, $now ) {
    return $self->recorder->audit_call(
        action         => $action,
        actor_id       => $actor_id,
        created_at     => $now,
        metadata       => $metadata,
        schema_version => $SCHEMA,
        target_id      => $target_id,
        target_type    => $type,
    )->{audit};
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'the review queue needs the PostgreSQL function layer' );
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

GPForum::Service::Moderation::ReviewStore - Posts held for review, and the review rule.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Moderation::ReviewStore->new(
        schema => $schema );
    my $held = $store->hold( { author_user_id => $id, kind => 'reply', ... } );
    my $queue = $store->queue;

=head1 DESCRIPTION

The storage of ADR 0134 through the C<api.moderation_review_*> functions:
a held post is kept outside threads and posts until staff decide it.
Perl builds the audit records and reads the results; each function
changes the queue and records its audit in one transaction.

=head1 SUBROUTINES/METHODS

=head2 hold

Holds a post; the author's command id keys it, so the same submission
again answers the entry it made.

=head2 queue

The pending posts, oldest first, with how many are pending in all.

=head2 mine

The author's own held posts: pending, and decided in the last 30 days, the
place each went to read with the viewer's scopes (a place they cannot read
names no title or id).

=head2 take

One held post, locked until the transaction ends.

=head2 decide

Records an approval, a rejection or a withdrawal of a pending post.

=head2 set_rule

Sets how many first posts are held and whether flagged posts are held.

=head2 in_transaction

Runs code in one transaction of the store's schema.

=head2 maximum_first_posts

The largest number of first posts held: 20.

=head2 maximum_reason

The longest rejection reason: 500 characters.

=head1 DIAGNOSTICS

Without the PostgreSQL function layer every call raises
L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Infrastructure::EventRecorder>.

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
