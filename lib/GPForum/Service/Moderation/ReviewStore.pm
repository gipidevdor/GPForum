# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::ReviewStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
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
has recorder   => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));

# A schema without the function layer -- the in-memory doubles -- holds
# nothing: every call is unavailable.
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(hold queue mine take decide set_rule));

sub maximum_first_posts ($self) { return $MAXIMUM_FIRST; }

sub maximum_reason ($self) { return $MAXIMUM_REASON; }

# Holds a post. $input carries the author, the command id, the kind, where
# it goes, its text as composed, why it is held and the draft it was
# written in. Answers the entry: its id, its status and whether it was
# already held under that command id (replayed).
async sub hold_p ( $self, $input, $context = undef ) {
    return _held(
        await $self->_functions->row_p(
            'moderation_review_hold', $self->_hold_values($input), $context
        )
    );
}

sub _hold_values ( $self, $input ) {
    my $review_id = $self->id_service->uuid;
    my $now       = $self->clock->now_iso8601;
    return {
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
        tags               => $input->{tags} // q{},
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
    };
}

sub _held ($row) {
    $row //= {};
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
async sub queue_p ( $self, $limit = $QUEUE_LIMIT, $context = undef ) {
    return await $self->_functions->rows_p( 'moderation_review_queue',
        { row_limit => $limit }, $context );
}

# The author's own held posts: pending, and those decided lately.
async sub mine_p ( $self, $user_id, $viewer, $context = undef ) {
    return [] if !GPForum::Infrastructure::Id->is_uuid_spelling($user_id);

    return await $self->_functions->rows_p( 'moderation_review_mine',
        _mine_values( $user_id, $viewer ), $context );
}

sub _mine_values ( $user_id, $viewer ) {
    return {
        user_id      => $user_id,
        row_limit    => $QUEUE_LIMIT,
        member       => $viewer->member      ? 1 : 0,
        global_read  => $viewer->global_read ? 1 : 0,
        category_ids => $viewer->category_ids,
        space_ids    => $viewer->space_ids,
    };
}

# One held post, locked for the rest of the transaction; undef when there
# is none. The lock holds only within a transaction: call it on the store
# in_transaction_p hands its work.
async sub take_p ( $self, $review_id, $context = undef ) {
    return undef if !GPForum::Infrastructure::Id->is_uuid_spelling($review_id);

    return await $self->_functions->row_p( 'moderation_review_take',
        { review_id => $review_id }, $context );
}

# Records a decision: approved (with the post it became), rejected (with
# a reason) or withdrawn by its author. Answers the function's row: ok,
# unchanged, decided, not_found or invalid, with the entry's status.
async sub decide_p ( $self, $input, $context = undef ) {
    my ( $refusal, @call ) = $self->_decide_call($input);
    return $refusal // ( await $self->_functions->row_p( @call, $context ) )
      // { status => 'not_found' };
}

sub _decide_call ( $self, $input ) {
    my $review_id = $input->{review_id} // q{};
    return { status => 'not_found' }
      if !GPForum::Infrastructure::Id->is_uuid_spelling($review_id);
    my $decision = $input->{status} // q{};
    return { status => 'invalid' } if !exists $DECISION_ACTION{$decision};

    my $now = $self->clock->now_iso8601;
    return (
        undef,
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
    );
}

# Sets the review rule: how many first posts are held (0 is off), and
# whether flagged posts are held too. Answers ok, unchanged or invalid
# (with the field).
async sub set_rule_p ( $self, $input, $context = undef ) {
    my ( $refusal, @call ) = $self->_rule_call($input);
    return $refusal
      // _rule_answer( await $self->_functions->row_p( @call, $context ) );
}

sub _rule_call ( $self, $input ) {
    my $first = $input->{first_posts} // q{};
    return _invalid('first_posts')
      if $first !~ $FIRST_POSTS || $first > $MAXIMUM_FIRST;
    my $flagged = $input->{flagged} ? 1 : 0;

    my $now = $self->clock->now_iso8601;
    return (
        undef,
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
    );
}

sub _rule_answer ($row) {
    my $status = ( $row // {} )->{status} // 'invalid';
    return { ok => ( $status eq 'invalid' ? 0 : 1 ), status => $status };
}

# Runs the work in one transaction on the worker's pooled asynchronous
# connections: it is handed the store joined to the transaction and the
# transaction's call layer, which other stores' writes join.
async sub in_transaction_p ( $self, $work, $context = undef ) {
    return await $self->_functions->transaction_p(
        async sub ($scope) {
            return await $work->(
                ref($self)->new( %{$self}, functions => $scope ), $scope
            );
        },
        $context
    );
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

Each operation answers a promise and takes an optional query context last.
Its blocking twin, named without C<_p>, runs the same body on the blocking
call layer (ADR 0177).

=head2 hold_p

Holds a post; the author's command id keys it, so the same submission
again answers the entry it made.

=head2 queue_p

The pending posts, oldest first, with how many are pending in all; an
optional limit comes before the query context.

=head2 mine_p

The author's own held posts: pending, and decided in the last 30 days, the
place each went to read with the viewer's scopes (a place they cannot read
names no title or id). Takes the author's id and the viewer.

=head2 take_p

One held post, locked until the transaction ends: call it on the store
L</in_transaction_p> hands its work.

=head2 decide_p

Records an approval, a rejection or a withdrawal of a pending post.

=head2 set_rule_p

Sets how many first posts are held and whether flagged posts are held.

=head2 hold, queue, mine, take, decide, set_rule

The blocking twins.

=head2 in_transaction_p

Takes an asynchronous work and an optional query context, and runs the
work in one transaction on the worker's pooled asynchronous connections.
The work receives the store joined to the transaction and the
transaction's call layer, and answers a promise; its answer is the
transaction's, and a failure rolls the transaction back.

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

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
