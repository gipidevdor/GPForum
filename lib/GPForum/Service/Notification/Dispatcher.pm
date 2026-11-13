# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::Dispatcher;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Keyset;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow::NotificationInbox;
use GPForum::Service::Admin::Settings;
use GPForum::Service::Clock;
use GPForum::Service::Forum::PageWindow;
use GPForum::Service::Forum::SourceThread;
use GPForum::Service::Notification::Fanout;
use GPForum::Service::Realtime::EventEnvelope;
use GPForum::Infrastructure::Id;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $DEFAULT_LIMIT    => 25;
const my @CURSOR_COLUMNS   => qw(created_at notification_id);
const my $ERROR_TEXT_LIMIT => 300;

# ADR 0078: a notification the member takes by email is queued as this
# event; Worker::Handler::NotificationMail sends it.
const my $EMAIL_REQUESTED => 'notification.email.requested';

# A badge failure is logged at most once in this many seconds per message,
# and this many messages are remembered for it.
const my $BADGE_LOG_INTERVAL => 300;
const my $BADGE_LOG_MESSAGES => 32;

# Bootstrap builds a dispatcher per request, so counters kept on one would
# die with it. These are the process's, shared by every dispatcher it builds,
# as the notifier's are.
my %PROCESS_STATS = ( badge_failures => 0 );

# The last badge failure (for /metrics) and when each message was last
# logged, the process's for the same reason: remembered on a dispatcher, it
# died with its request, and an outage that failed every badge logged a
# warning per request.
my %PROCESS_BADGE_ERRORS;

has badge_errors => sub { return \%PROCESS_BADGE_ERRORS; };
has clock        => sub { return GPForum::Service::Clock->new; };
has event_contract =>
  sub { return GPForum::Service::Realtime::EventEnvelope->new; };
has event_recorder => sub ($self) {
    return GPForum::Infrastructure::EventRecorder->new(
        id_service => $self->id_service,
        schema     => $self->schema,
    );
};
has id_service  => sub { return GPForum::Infrastructure::Id->new; };
has logger      => undef;    # optional: badge failures are dropped without one
has page_window => sub { return GPForum::Service::Forum::PageWindow->new; };
has permission_engine => undef;    # optional: no permission filter
has preference_store  => undef;    # optional: every channel enabled

# Badges go out through NOTIFY (a PgNotifier), never to one process's hub:
# a count changed by a request on one worker reached only the sockets of
# that worker, and a reader's other tabs, on other workers or nodes, kept
# the old one.
has realtime_notifier => undef;    # optional: no realtime badge

# ADR 0102: the inbox and its unread count keep only notifications whose
# source the recipient can still read. One created while a thread was public
# stayed in sight, with its actor and link, after its category turned
# private or the recipient lost their grant.
has readability => undef;    # optional: every source counts as readable
__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# ADR 0130: a reply or mention by a member the recipient ignores or blocks
# is not delivered. Service::Community::RelationStore; without it nothing is
# silenced.
has relations => undef;                           # optional: nobody is silenced
has stats     => sub { return \%PROCESS_STATS; };

# Written once, as its promise method (ADR 0177); the services it awaits
# block with it, and join a transaction with it.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(create_notification list_for_user list_page_for_user
      unread_count_for_user mark_read mark_all_read)
);
GPForum::Infrastructure::SqlFunction->blocking_parts(
    qw(event_recorder permission_engine preference_store readability
      realtime_notifier relations)
);

# ADR 0078: the member's preferences say where the notification goes, by
# its type: the inbox, email, both or neither. One that goes by email only
# is queued and answered as skipped from the inbox, with email_queued.
#
# With $scope -- the call layer of a transaction the caller holds, a
# mention's in its post's -- every read and write joins that transaction:
# the source it screens is the post not committed yet, and the badge's
# pg_notify goes out only when the post commits. Without one, the delivery
# and its queued channels commit together, and the badge is counted and
# sent once they have.
async sub create_notification_p ( $self, $input, $context = undef,
    $scope = undef )
{
    $self->_functions;
    my $reader   = $scope ? $self->_joined($scope) : $self;
    my $screened = await $reader->_screened_p( $input, $context );
    return $screened->{refused} if $screened->{refused};
    my $plan = $screened->{plan};

    my $delivered = await $self->_within_p(
        $scope, $context,
        async sub ($joined) {
            return await $joined->_delivered_p( $input, $plan, $context );
        },
        $plan->{in_app} || ( $plan->{email} && $plan->{web_push} )
    );
    return $delivered
      if !$plan->{in_app} || ref $delivered ne 'HASH' || !$delivered->{ok};

    return await $self->_with_badge_p(
        $input->{recipient_user_id},
        $delivered, !$delivered->{duplicate},
        $context,   $scope
    );
}

# The work on the caller's transaction, or else on one of its own when it
# writes more than one statement: a single API statement is atomic.
async sub _within_p ( $self, $scope, $context, $work, $several = 1 ) {
    return await $work->( $self->_joined($scope) ) if $scope;
    return await $work->($self)                    if !$several;

    return await $self->_functions->transaction_p(
        async sub ($layer) { return await $work->( $self->_joined($layer) ); },
        $context
    );
}

# The dispatcher with its reads and writes on a transaction's call layer,
# and those of every collaborator that reads or writes.
sub _joined ( $self, $layer ) {
    return GPForum::Infrastructure::SqlFunction->joined( $self, $layer );
}

# The refusal a notification meets before anything is written, in order --
# the permission (ADR 0102), the member's preferences, the recipient's
# relation to the actor (ADR 0130) -- or the delivery plan it goes by. Each
# step is read through its collaborator's promise method when it has one.
async sub _screened_p ( $self, $input, $context ) {
    my $engine = $self->permission_engine;
    my @source = (
        $input->{recipient_user_id}, $input->{source_type},
        $input->{source_id},         $input->{payload} || {},
    );
    my $permitted =
       !$engine ? 1
      : $engine->can('can_notify_p')
      ? await $engine->can_notify_p( @source, $context )
      : $engine->can_notify(@source);
    return { refused => { ok => 0, skipped => 'permission_denied' } }
      if !$permitted;
    my $plan = await $self->_delivery_plan_p( $input, $context );
    return { refused =>
          { ok => 0, skipped => 'channel_disabled', channel => 'in_app' } }
      if !$plan->{in_app} && !$plan->{email} && !$plan->{web_push};
    my $relations = $self->relations;
    my @relation  = (
        $input->{recipient_user_id},
        $input->{notification_type},
        ( $input->{payload} || {} )->{actor_id},
    );
    my $silenced =
       !$relations ? 0
      : $relations->can('silences_p')
      ? await $relations->silences_p( @relation, $context )
      : $relations->silences(@relation);
    return { refused => { ok => 0, skipped => 'member_relation' } }
      if $silenced;

    return { plan => $plan };
}

# The plan the preference store reads, or the in-app channel alone from a
# store that has no plan. A store that fails reads as the inbox only, as a
# failed channel read always did: a notification is not lost to it.
async sub _delivery_plan_p ( $self, $input, $context ) {
    my $store     = $self->preference_store;
    my $recipient = $input->{recipient_user_id};
    my $type      = $input->{notification_type};
    return { in_app => 1, email => 0 }
      if !$store || !defined $recipient || !length $recipient;

    my $plan;
    try {
        $plan =
          $store->can('delivery_plan_p')
          ? await $store->delivery_plan_p( $recipient, $type, $context )
          : $store->can('delivery_plan')
          ? $store->delivery_plan( $recipient, $type )
          : {
            in_app => $store->channel_enabled( $recipient, 'in_app' ) ? 1 : 0,
            email  => 0
          };
    }
    catch ($error) {
        return { in_app => 1, email => 0 };
    };

    return $plan;
}

# The delivery and the channels queued with it: in the inbox, or only by
# mail or push. An inbox row already there is answered as a duplicate:
# api.notification_deliver keys it by recipient and notification, so it is
# another delivery of the same notification.
async sub _delivered_p ( $self, $input, $plan, $context ) {
    if ( $plan->{in_app} ) {
        my $delivered = (
            await $self->_functions->row_p(
                'notification_deliver',
                $self->delivery_call( $input, $self->clock->now_iso8601 ),
                $context
            )
        )->{result};
        return $delivered if ref $delivered ne 'HASH' || !$delivered->{ok};
        await $self->_queue_channels_p( $input, $plan, $context );
        return { %{$delivered}, _queued_flags($plan) };
    }
    await $self->_queue_channels_p( $input, $plan, $context );

    return _external_answer($plan);
}

# The mail is an event in the outbox, named by the notification's own key:
# a retried delivery records it once. A push job is committed with the
# notification, never sent by this path.
async sub _queue_channels_p ( $self, $input, $plan, $context ) {
    if ( $plan->{email} ) {
        await $self->event_recorder->record_event_p(
            { $self->_email_event($input) }, $context );
    }
    if ( $plan->{web_push} ) {
        my $call = $self->delivery_call( $input, $self->clock->now_iso8601 );
        await $self->_functions->row_p( 'notification_push_enqueue',
            { notification => $call->{notification} }, $context );
    }
    return;
}

sub _queued_flags ($plan) {
    return (
        ( $plan->{email}    ? ( email_queued    => 1 ) : () ),
        ( $plan->{web_push} ? ( web_push_queued => 1 ) : () ),
    );
}

# The answer to a notification that goes only by mail or push.
sub _external_answer ($plan) {
    return {
        ok      => 0,
        skipped => 'channel_disabled',
        channel => 'in_app',
        _queued_flags($plan),
    };
}

# The mail event as api.ops_record_event takes it, drawn and not sent: the
# fan-out queues many in one statement.
sub email_call ( $self, $input ) {
    return $self->event_recorder->event_call( $self->_email_event($input) );
}

# The mail event's fields, as record_event takes them. It carries what the
# mail says and links to, never the address, which the worker reads when it
# sends.
sub _email_event ( $self, $input ) {
    my $key     = 'notification.email:' . _idempotency_key($input);
    my $payload = $input->{payload} || {};

    return (
        event_type        => $EMAIL_REQUESTED,
        aggregate_type    => 'user',
        aggregate_id      => $input->{recipient_user_id},
        aggregate_version => 1,
        actor_id        => $payload->{actor_id} // $input->{recipient_user_id},
        event_id        => _notification_id_for($key),
        idempotency_key => $key,
        payload         => {
            recipient_user_id => $input->{recipient_user_id},
            notification_type => $input->{notification_type},
            source_type       => $input->{source_type},
            source_id         => $input->{source_id},
            thread_id         => $payload->{thread_id},
            post_id           => $payload->{post_id},
            reason            => $payload->{reason},

            # ADR 0139: a direct message's mail links to its conversation.
            map { defined $payload->{$_} ? ( $_ => $payload->{$_} ) : () }
              qw(conversation_id),
        },
    );
}

# The delivery as api.notification_deliver takes it, stamped $at: the key,
# the notification row and the inbox row. Drawn and not sent, so the fan-out
# sends many in one statement.
sub delivery_call ( $self, $input, $at ) {
    my $idempotency_key = _idempotency_key($input);
    my $notification_id = $input->{notification_id}
      || _notification_id_for($idempotency_key);

    return {
        idempotency_key => $idempotency_key,
        notification    =>
          _notification_row( $input, $idempotency_key, $notification_id, $at ),
        inbox => {
            created_at        => $at,
            notification_id   => $notification_id,
            recipient_user_id => $input->{recipient_user_id},
            rank_score        => $input->{rank_score} || 0,
            read_at           => undef
        },
    };
}

sub _notification_row ( $input, $idempotency_key, $notification_id,
    $created_at )
{
    return {
        created_at        => $created_at,
        notification_id   => $notification_id,
        notification_type => $input->{notification_type},
        payload           => {
            %{ $input->{payload} || {} }, idempotency_key => $idempotency_key,
        },
        recipient_user_id => $input->{recipient_user_id},
        source_id         => $input->{source_id},
        source_type       => $input->{source_type},
    };
}

# The fan-out is four statements however many the recipients
# (Service::Notification::Fanout, migration 1036): the candidates with
# everything the screening reads, where the source sits, the deliveries, the
# badges.
sub fanout_to_subscribers ( $self, $input ) {
    $self->_functions;
    my $fanout =
      GPForum::Service::Notification::Fanout->new( dispatcher => $self )
      ->run($input);
    for my $uncounted ( @{ $fanout->{uncounted} } ) {
        $self->_badge_failed($uncounted);
    }
    $self->_badges( $fanout->{badges} );

    return $fanout->{results};
}

# The badges of a fan-out, one per notification created, in one NOTIFY
# statement (the notifier's notify_many), or one each for a notifier without
# it. A failure is counted and logged as one badge's is.
sub _badges ( $self, $badges ) {
    my $notifier = $self->realtime_notifier;
    return if !$notifier || !@{$badges};

    my @events =
      map {
        $self->event_contract->notification_badge(
            @{$_}{qw(user_id unread_count)} )
      } @{$badges};
    my ( $sent, $error );
    try {
        $sent =
            $notifier->can('notify_many')
          ? $notifier->notify_many( \@events )
          : _each_notified( $notifier, \@events );
    }
    catch ($caught) {
        $error = $caught;
    };
    if ( !defined $error && ref $sent eq 'HASH' && !$sent->{ok} ) {
        $error = 'badge NOTIFY failed: ' . ( $sent->{reason} || 'unknown' );
    }
    if ( defined $error ) {
        $self->_badge_failed($error);
    }

    return;
}

# Each badge sent on its own; the first failure is the answer.
sub _each_notified ( $notifier, $events ) {
    for my $event ( @{$events} ) {
        my $sent = $notifier->notify($event);
        return $sent if ref $sent eq 'HASH' && !$sent->{ok};
    }

    return { ok => 1 };
}

async sub list_for_user_p ( $self, $user_id, $limit, $context = undef ) {
    return await $self->_inbox_p( $user_id, undef,
        { limit => $limit || $DEFAULT_LIMIT }, $context );
}

# The inbox page and its badge read on the worker's pooled leases. Before
# them call_p ran each blocking read in a forked child that opened a
# connection of its own, one child at a time per worker: two forks and two
# new connections a page.
async sub list_page_for_user_p ( $self, $user_id, $options, $context = undef ) {
    my $page =
      $self->page_window->plan( { %{$options}, sort => 'timestamp' } );
    my $rows = await $self->_inbox_p( $user_id, $options->{viewer},
        { limit => $page->{fetch_rows}, after => $page->{after} }, $context );

    return $self->page_window->page( $rows, $page->{limit}, \@CURSOR_COLUMNS );
}

# The member's inbox rows, newest first, within $window (limit, after).
async sub _inbox_p ( $self, $user_id, $viewer, $window, $context ) {
    my $functions = $self->_functions;
    my $source =
      await $self->_source_parameters_p( $user_id, $viewer, $context );
    my $rows =
      await $functions->rows_p( 'notification_list_inbox',
        _inbox_values( $source, $window ), $context );

    return $self->_inbox_rows($rows);
}

# The count stops past 99, which the inbox shows as "more than 99": each
# unread row costs a readability lookup, so an uncapped count grew with the
# backlog on every delivery.
async sub unread_count_for_user_p (
    $self, $user_id,
    $viewer = undef,
    $context = undef
  )
{
    my $functions = $self->_functions;
    my $source =
      await $self->_source_parameters_p( $user_id, $viewer, $context );
    my $row =
      await $functions->row_p( 'notification_unread_count', $source, $context );
    return $row ? $row->{unread_count} : 0;
}

# The read is one statement, then the badge -- the count and its NOTIFY --
# once it committed. The id comes from the URL. One that is not a uuid is
# simply not a notification; sent to the uuid column it failed the whole
# statement, which answered 503 and logged an error for a mistyped link.
async sub mark_read_p ( $self, $notification_id, $recipient_user_id,
    $context = undef )
{
    my $functions = $self->_functions;
    return { ok => 0, error => 'not_found' }
      if !GPForum::Infrastructure::Id->is_uuid($notification_id);
    my $row = await $functions->row_p(
        'notification_mark_read',
        {
            notification_id   => $notification_id,
            recipient_user_id => $recipient_user_id,
            read_at           => $self->clock->now_iso8601,
        },
        $context
    );
    return await $self->_with_badge_p( $recipient_user_id, $row->{result}, 1,
        $context );
}

# The unread rows the inbox shows are marked: a notification whose source
# the reader can no longer read stays unread and out of sight, and is not
# counted as marked.
async sub mark_all_read_p ( $self, $recipient_user_id, $context = undef ) {
    my $functions = $self->_functions;
    my $read_at   = $self->clock->now_iso8601;
    my $values =
      await $self->_source_parameters_p( $recipient_user_id, undef, $context );
    $values->{user_id} = delete $values->{recipient_user_id};
    my $row = await $functions->row_p( 'notification_mark_all_read',
        { %{$values}, read_at => $read_at }, $context );
    return await $self->_with_badge_p( $recipient_user_id, $row->{result}, 1,
        $context );
}

# The badge for a write already committed, so the write's answer stands
# whatever happens here. A count that failed was once raised past the
# commit: a mark-read that had been stored answered as a failure. A failed
# count or NOTIFY is logged and counted instead (the count is then undef),
# and the next snapshot corrects the badge. A delivery that was a duplicate
# sends no badge ($notify false), though its count is read.
#
# pg_notify is transactional: under an outer transaction PostgreSQL holds
# the badge until that commits and drops it on rollback. There the count and
# its NOTIFY run in a savepoint, so a statement that fails here does not
# abort the transaction the caller still has to commit; the count already
# read is kept. That transaction is $scope when the caller hands it, or one
# a blocking caller holds unseen -- a mention inside the command log's --
# which the blocking layer says is open. With none open, the
# badge goes out in autocommit, after its write committed.
# A NOTIFY the notifier could not send is raised only to roll it back.
async sub _with_badge_p ( $self, $recipient_user_id, $result, $notify,
    $context, $scope = undef )
{
    return $result if ref $result ne 'HASH' || !$result->{ok};
    my $count;
    my $badge = async sub ($dispatcher) {
        $count =
          await $dispatcher->unread_count_for_user_p( $recipient_user_id,
            undef, $context );
        my $notifier = $dispatcher->realtime_notifier;
        return 1 if !$notify || !$notifier;
        my $event =
          $dispatcher->event_contract->notification_badge( $recipient_user_id,
            $count );
        my $sent =
          $notifier->can('notify_p')
          ? await $notifier->notify_p( $event, $context )
          : $notifier->notify($event);
        if ( ref $sent eq 'HASH' && !$sent->{ok} ) {
            GPForum::X::Unavailable->throw( message => 'badge NOTIFY failed: '
                  . ( $sent->{reason} || 'unknown' ) );
        }
        return 1;
    };
    my $layer = $scope // _open_blocking_layer( $self->_functions );
    try {
        if ($layer) {
            await $layer->transaction_p(
                async sub ($savepoint) {
                    return await $badge->( $self->_joined($savepoint) );
                },
                $context
            );
        }
        else { await $badge->($self); }
    }
    catch ($error) {
        $self->_badge_failed($error);
    };
    $result->{unread_count} = $count;
    return $result;
}

# The call layer itself when it blocks inside an open transaction; undef
# for the pooled one, and for none open.
sub _open_blocking_layer ($functions) {
    return $functions->blocking && $functions->in_transaction
      ? $functions
      : undef;
}

# Every failure is counted, and kept as the last one for /metrics; it is
# logged once in five minutes per message, not on every badge. In an outage
# every write's badge fails the same way, and a warning per request buried
# the first one under the flood.
#
# A badge that goes out does not re-arm the warning: under load some counts
# still finish, and re-arming on each of them logged nearly every failure of
# the outage. The line logged again says how many failed the same way in
# between, which is all a worker, serving no /metrics, tells of them.
sub _badge_failed ( $self, $error ) {
    my $message = _badge_error_text($error);
    $self->stats->{badge_failures} += 1;
    $self->badge_errors->{last} =
      { at => $self->clock->now_iso8601, message => $message };

    my $logger = $self->logger;
    return if !$logger;

    my $now    = $self->clock->now_epoch;
    my $logged = $self->badge_errors->{logged} //= {};
    my $seen   = $logged->{$message};
    if ( $seen && $now - $seen->{at} < $BADGE_LOG_INTERVAL ) {
        $seen->{suppressed} += 1;
        return;
    }

    my $suppressed = $seen ? $seen->{suppressed} : 0;
    if ( !$seen ) {
        _forget_logged( $logged, $now );
    }
    $logged->{$message} = { at => $now, suppressed => 0 };
    $logger->warn( "notification badge not sent: $message"
          . ( $suppressed ? " ($suppressed more since last logged)" : q{} ) );

    return;
}

# The messages are remembered within a bound: past it the stale ones go,
# and when every one is recent, all of them (each is then logged again).
sub _forget_logged ( $logged, $now ) {
    return if keys %{$logged} < $BADGE_LOG_MESSAGES;

    for my $message ( keys %{$logged} ) {
        if ( $now - $logged->{$message}{at} >= $BADGE_LOG_INTERVAL ) {
            delete $logged->{$message};
        }
    }
    if ( keys %{$logged} >= $BADGE_LOG_MESSAGES ) {
        %{$logged} = ();
    }

    return;
}

# The first line that says something, without the statement DBI appends to
# it or the source line a croak does: the statement carries the bind values -- the member's id -- so with it every
# member's badge read as a new message, and /metrics would have shown whose
# count failed. A count that cannot reconnect fails with DBI's connect
# error, which repeats the DSN, an inline password and all: that is
# redacted as the settings page redacts it, before the cut, so the cut
# cannot leave half of it.
sub _badge_error_text ($error) {
    my ($line) = grep { /\S/msx } split /\n/msx, "$error";
    $line //= q{};
    $line =~ s/\s* \[for [ ] Statement [ ] .*\z//msx;
    $line =~ s/\s+ at [ ] \S+ [ ] line [ ] \d+ [.]? \z//msx;
    $line =~ s/\A\s+|\s+\z//gmsx;
    $line = GPForum::Service::Admin::Settings->new->redact( $line, [] );

    return
      length $line > $ERROR_TEXT_LIMIT
      ? substr( $line, 0, $ERROR_TEXT_LIMIT )
      : $line;
}

sub snapshot ($self) {
    my $last_error = $self->badge_errors->{last};
    my %snapshot   = %{ $self->stats };
    $snapshot{last_badge_error} = $last_error ? { %{$last_error} } : undef;

    return \%snapshot;
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'notifications need the PostgreSQL function layer' );
}

sub _inbox_values ( $source, $options ) {
    my $after = $options->{after} || {};
    return {
        %{$source},
        after_created_at      => $after->{sort_value},
        after_notification_id => $after->{id},
        row_limit             => $options->{limit} || $DEFAULT_LIMIT,
    };
}

sub _inbox_rows ( $self, $rows ) {
    return [
        map {
            GPForum::Infrastructure::ResultRow::NotificationInbox->from( $_,
                $self->readability ? 1 : 0 )
        } @{$rows}
    ];
}

# The recipient as the inbox functions see them: with a readability, the
# viewer given, or else the recipient resolved; without one, every source
# counts.
async sub _source_parameters_p ( $self, $user_id, $viewer, $context ) {
    my $readability = $self->readability;
    if ( $readability && !ref $viewer ) {
        $viewer =
          await $readability->viewer_resolver->resolve_p( $user_id, $context );
    }
    return {
        recipient_user_id => $user_id,
        filter_sources    => $readability ? 1                     : 0,
        member            => $viewer      ? $viewer->member       : 0,
        global_read       => $viewer      ? $viewer->global_read  : 0,
        viewer_user_id    => $viewer      ? $viewer->user_id      : undef,
        category_ids      => $viewer      ? $viewer->category_ids : [],
        space_ids         => $viewer      ? $viewer->space_ids    : [],
    };
}

# The resultset of an inbox page, kept only for the query-plan evidence
# (Benchmark::QueryPlanEndpoints), which EXPLAINs it beside
# api.notification_list_inbox.
sub inbox_resultset ( $self, $user_id, $options ) {
    my $query = {
        'me.recipient_user_id' => $user_id,
        %{ $self->_readable_sources( $user_id, $options->{viewer} ) },
    };
    if ( $options->{after} ) {
        GPForum::Infrastructure::Keyset->after(
            $query,
            {
                direction => 'desc',
                id   => [ 'me.notification_id', $options->{after}{id} ],
                sort => [ 'me.created_at',      $options->{after}{sort_value} ],
            }
        );
    }

    return $self->schema->resultset('NotificationInbox')->search_rs(
        $query,
        {
            order_by => [
                { -desc => 'me.created_at' },
                { -desc => 'me.notification_id' },
            ],
            prefetch => 'notification',
            GPForum::Service::Forum::SourceThread->attributes(
                $self->readability, 'notification.source_type',
                'notification.source_id'
            ),
            rows => $options->{limit} || $DEFAULT_LIMIT,
        }
    );
}

# The recipient's own viewer when the request has one; resolved otherwise.
sub _readable_sources ( $self, $user_id, $viewer ) {
    return {} if !$self->readability;

    return {
        -and => [
            $self->readability->sources_condition(
                $viewer // $user_id, 'notification.source_type',
                'notification.source_id'
            )
        ]
    };
}

sub _idempotency_key ($input) {
    return join q{:}, $input->{idempotency_key},
      $input->{recipient_user_id} || q{}
      if defined $input->{idempotency_key};

    my $payload  = $input->{payload}    || {};
    my $event_id = $payload->{event_id} || q{};

    return join q{:},
      'notification',
      $input->{recipient_user_id} || q{},
      $input->{notification_type} || q{},
      $input->{source_type}       || q{},
      $input->{source_id}         || q{},
      $event_id;
}

# A notification's id, named by its idempotency key, so a delivery done twice
# is one notification.
sub _notification_id_for ($idempotency_key) {
    return GPForum::Infrastructure::Id->named_uuid($idempotency_key);
}

1;

__END__

=head1 NAME

GPForum::Service::Notification::Dispatcher - Delivers notifications to a member's inbox, lists it, marks it read and counts what is unread.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $policy = GPForum::Service::Notification::RecipientPolicy->new(
        schema => $schema );
    my $dispatcher = GPForum::Service::Notification::Dispatcher->new(
        permission_engine => $policy,
        preference_store  => $preference_store,
        readability       => $policy,
        realtime_notifier => $pg_notifier,
        relations         => $relation_store,
        schema            => $schema,
    );
    my $delivery = await $dispatcher->create_notification_p(
        {
            recipient_user_id => $user_id,
            notification_type => 'mention',
            source_type       => 'post',
            source_id         => $post_id,
            payload           => { thread_id => $thread_id },
        }
    );
    my $fanout = $dispatcher->fanout_to_subscribers(
        {
            target_type                => 'thread',
            target_id                  => $thread_id,
            source_type                => 'post',
            source_id                  => $post_id,
            notification_type          => 'reply',
            excluded_recipient_user_id => $author_id,
            idempotency_key            => "notification.reply:$event_id",
            payload                    => { event_id => $event_id },
        }
    );
    my $page = await $dispatcher->list_page_for_user_p( $user_id,
        { after => $cursor, limit => 25, viewer => $viewer } );
    await $dispatcher->mark_read_p( $notification_id, $user_id );

    # A command or a worker: the same operation, answered when it returns.
    my $unread = $dispatcher->unread_count_for_user( $user_id, $viewer );

=head1 DESCRIPTION

A notification is a C<notifications> row and the recipient's
C<notification_inbox> row; reading it adds a C<notification_reads> row and
stamps the inbox's C<read_at>. Every read and write is a PostgreSQL
function of the call layer (C<functions>); each operation is written once,
as its C<_p> method, and its blocking twin is that method run on the
blocking call layer (ADR 0177). Without the function layer every operation
raises L<GPForum::X::Unavailable>.

Delivery is idempotent. Each delivery has an idempotency key: the caller's
C<idempotency_key> joined with the recipient, or, without one, the
recipient, type, source and the payload's C<event_id>. Unless the caller
passes a C<notification_id>, the id is a uuid named by that key, so a
retried delivery finds the inbox row it made the first time and is
reported as a C<duplicate> instead of notifying twice. The outbox relies on
this to retry a fan-out safely. C<api.notification_deliver> writes both
rows, and a unique conflict with a concurrent delivery is answered with the
row that won. C<notifications> is partitioned by C<created_at> and keyed
on the id and that time, so a notification row already stored under the
id, at whatever time, is reused, its C<created_at> given to the inbox row
(ADR 0116).

A recipient is notified only if the C<permission_engine> agrees (ADR 0102:
only about a source they can read) and their C<in_app> channel is enabled
in the C<preference_store>. The inbox and the unread count keep only
notifications whose source the reader can still read, judged by
C<readability> in the query. A reply or mention by a member the recipient
ignores or blocks is skipped as C<member_relation> when C<relations> is set
(ADR 0130); other notification types are never silenced. Each collaborator
is asked through its C<_p> method when it has one, and the blocking twins
run those on the blocking layer too (C<blocking_parts>).

After a delivery or a read commits, the recipient's new unread count is
sent as a C<notification.badge> event through C<realtime_notifier>, a
L<GPForum::Service::Realtime::PgNotifier>, so it reaches the member's
sockets on every node. Under an outer transaction PostgreSQL holds that
NOTIFY until the outer commit. The count is capped: past 99 it stops at
100, which the inbox shows as "more than 99".

The badge comes after the write, and the write's answer stands whatever
happens to it. A count that fails, or a NOTIFY the notifier could not send,
is counted in C<badge_failures>, kept as the C<last_badge_error>, logged
as a warning through C<logger> at most once in five minutes per message,
and left to the next snapshot; the result's C<unread_count> is then undef
when the count itself failed. A badge that goes out in between does not
re-arm the warning, and the line logged again ends with how many failed the
same way since, C<(N more since last logged)>. The message is the error's
first line without the statement and bind values DBI appends, so the
failures of one outage read as one message whoever's badge it was, and with
an inline password (the DSN DBI's connect error repeats) redacted as
L<GPForum::Service::Admin::Settings/redact> redacts it. Under a
transaction -- the one the caller hands C<create_notification_p>, or, on
the blocking layer, any the caller holds -- the count and the NOTIFY run
in a savepoint, so a failed statement there does not abort the transaction
the caller still has to commit.

Every collaborator but C<schema> is optional: without C<permission_engine>
or C<preference_store> everyone is notified, without C<readability> nothing
is filtered, and without C<realtime_notifier> no badge is sent.

=head1 SUBROUTINES/METHODS

=head2 create_notification_p

Takes a hash reference with C<recipient_user_id>, C<notification_type>,
C<source_type>, C<source_id>, an optional C<payload> hash reference and
optional C<idempotency_key>, C<notification_id> and C<rank_score> (default
0), then an optional query context and an optional transaction call layer
(the scope a L<GPForum::Infrastructure::SqlFunction/transaction_p> work
receives). Answers C<< { ok => 0, skipped => 'permission_denied' } >> when
the C<permission_engine> refuses, and
C<< { ok => 0, skipped => 'channel_disabled', channel => 'in_app' } >> when
the recipient takes this type neither in the inbox nor by email nor by push
(the preference store's C<delivery_plan>, ADR 0078; a store without one is
asked C<channel_enabled> for C<in_app>), and
C<< { ok => 0, skipped => 'member_relation' } >> when the actor is on the
recipient's ignore or block list. A type the recipient takes by email is
queued as a C<notification.email.requested> event, its id named by the
notification's key so that a retry records it once, and the answer carries
C<< email_queued => 1 >>; one taken by push queues a push job and carries
C<< web_push_queued => 1 >>. Without the inbox, the answer is the
C<channel_disabled> skip above with those flags. Otherwise the rows and the
queued channels are written in one transaction and the answer is
C<< { ok => 1, duplicate, idempotency_key, notification, inbox,
unread_count } >>: C<notification> and C<inbox> are hash references of the
stored fields, the notification's C<payload> carrying the
C<idempotency_key>, both with the C<created_at> of a notification row
already stored under the id. C<duplicate> is 1 when the recipient already
had this notification; then no badge is sent, though C<unread_count> is
still read. C<unread_count> is undef when the count failed after the write
(see L</DESCRIPTION>).

With the transaction call layer the screening, the rows, the queued
channels and the badge all join the caller's transaction, the badge in a
savepoint of it, so a mention is screened against the post its write has
not committed yet and its badge is sent only on commit.

=head2 delivery_call

Takes what C<create_notification_p> takes and the time to stamp the rows
with. Returns the delivery as C<api.notification_deliver> takes it, drawn
and not sent: C<idempotency_key>, C<notification> and C<inbox>.

=head2 email_call

Takes what C<create_notification_p> takes. Returns the mail event the
member's plan would queue, as C<api.ops_record_event> takes it and
L<GPForum::Infrastructure::EventRecorder/event_call> draws it, not sent.

=head2 fanout_to_subscribers

Takes the same hash reference as C<create_notification_p>, without
C<recipient_user_id> but with C<target_type> and C<target_id>, whose
subscribers for this C<notification_type> are the recipients, and an
optional C<excluded_recipient_user_id> (the actor) left out. The fan-out is
four statements however many the recipients
(L<GPForum::Service::Notification::Fanout>): the candidates with their
plans, relations and viewers, where the source sits, the deliveries, the
badges; the screening is C<create_notification_p>'s, and a page of
deliveries that fails does not stop the others. The badges go out in one
NOTIFY statement when the notifier has C<notify_many>. Returns
C<< { ok => 1, attempted, created, duplicates, failed, skipped } >>:
C<attempted> a count, the others array references of the per-recipient
results, C<failed> holding C<< { recipient_user_id, error } >>. It is a
blocking method; there is no promise twin.

=head2 list_for_user_p

Takes a user id, a row limit (default 25) and an optional query context.
Answers an array reference of the member's inbox rows
(L<GPForum::Infrastructure::ResultRow::NotificationInbox>), newest first,
with their notification, judged readable for the member.

=head2 list_page_for_user_p

Takes a user id, a hash reference with C<after> (the cursor string from
the URL), C<limit> (bounded by L<GPForum::Service::Forum::PageWindow>, 25
by default) and C<viewer> (the reader to judge readability for; resolved
from the user id when it is not given), and an optional query context.
Answers the page hash reference from
L<GPForum::Service::Forum::PageWindow/page>: C<items>, C<has_next> and
C<next_cursor>, the cursor over C<created_at> and C<notification_id>. A
cursor that does not decode gives the first page.

=head2 unread_count_for_user_p

Takes a user id, an optional viewer (resolved from the user id when not
given) and an optional query context. Answers the number of unread
notifications the inbox would show, at most 100.

=head2 mark_read_p

Takes a notification id, the recipient's user id and an optional query
context, and marks that notification read in one statement. Answers
C<< { ok => 0, error => 'not_found' } >> when the id is not a uuid or the
recipient has no such notification. Otherwise answers
C<< { ok => 1, duplicate, notification_id, recipient_user_id, read_at,
unread_count } >>, with C<duplicate> 1 and the earlier C<read_at> when it
was already read. A badge with the new count is sent in both cases;
C<unread_count> is undef when that count failed after the commit.

=head2 mark_all_read_p

Takes the recipient's user id and an optional query context, and marks
every unread notification the inbox shows read, with one timestamp, in one
statement. Notifications whose source the member can no longer read stay
unread. Answers C<< { ok => 1, duplicate, marked_count, read_at,
recipient_user_id, unread_count } >>, C<duplicate> being 1 when there was
nothing to mark, and sends a badge; C<unread_count> is undef when that
count failed after the commit.

=head2 create_notification, list_for_user, list_page_for_user, unread_count_for_user, mark_read, mark_all_read

Each is its C<_p> method run on the blocking call layer (ADR 0177),
answering the value instead of a promise.

=head2 snapshot

Returns C<< { badge_failures, last_badge_error } >>: the number of badges
that could not be counted or sent after a write, and the last of those
failures, C<< { at, message } >> (C<at> from the C<clock>), or undef when
there was none. Both are kept per process and shared by every dispatcher it
builds, since Bootstrap builds one per request; the metrics snapshot
reports them as C<notifications>. A test passes its own C<stats> and
C<badge_errors> hash references.

=head2 inbox_resultset

Takes a user id and a hash reference with optional C<viewer>, C<after> (an
already decoded C<< { sort_value, id } >>) and C<limit> (default 25).
Returns the unexecuted C<NotificationInbox> resultset of an inbox page:
the member's notifications with a readable source, ordered by
C<created_at> and then C<notification_id>, descending, with the
notification prefetched and, when C<readability> is set, the thread it is
about (L<GPForum::Service::Forum::SourceThread>). Kept only for the
query-plan evidence, which EXPLAINs it beside C<api.notification_list_inbox>;
no operation runs it.

=head1 DIAGNOSTICS

Every operation but C<delivery_call>, C<email_call>, C<snapshot> and
C<inbox_resultset> raises L<GPForum::X::Unavailable> when the function
layer is missing. Database errors of the delivery and the reads propagate;
in a transaction they roll it back. Nothing after the write is raised: a
badge whose count or NOTIFY failed (a NOTIFY the notifier refused is a
L<GPForum::X::Unavailable>, raised only to roll its savepoint back) is
counted in C<badge_failures> and logged at C<warn> level, C<notification
badge not sent:> and the error's first line (at most 300 characters,
without DBI's C<[for Statement ...]>, an inline password C<[redacted]>), at
most once in five minutes per message, with C<(N more since last logged)>
when others failed the same way in between; the rows are written and the
next snapshot corrects the badge. A blocking twin croaks when the promise
method waited on the event loop
(L<GPForum::Infrastructure::SqlFunction/settled>).

=head1 CONFIGURATION AND ENVIRONMENT

None. C<clock>, C<id_service>, C<event_contract>, C<event_recorder> and
C<page_window> default to L<GPForum::Service::Clock>,
L<GPForum::Infrastructure::Id>, L<GPForum::Service::Realtime::EventEnvelope>,
L<GPForum::Infrastructure::EventRecorder> and
L<GPForum::Service::Forum::PageWindow>. C<logger> is optional (anything
with a C<warn> method; Bootstrap passes the application's log, in the web
and the worker processes alike); without it a failed badge is only
counted.

=head1 DEPENDENCIES

L<Const::Fast>, L<GPForum::Base>, L<GPForum::Infrastructure::Id>,
L<GPForum::Infrastructure::Keyset>, L<GPForum::Infrastructure::SqlFunction>
(the call layer and the blocking twins),
L<GPForum::Infrastructure::ResultRow::NotificationInbox>,
L<GPForum::Infrastructure::EventRecorder> (the queued mail),
L<GPForum::X::Unavailable>, L<GPForum::Service::Admin::Settings> (its
C<redact>), L<GPForum::Service::Clock>, L<GPForum::Service::Forum::PageWindow>,
L<GPForum::Service::Forum::SourceThread>,
L<GPForum::Service::Notification::Fanout>,
L<GPForum::Service::Realtime::EventEnvelope>; passed in:
L<GPForum::Service::Notification::RecipientPolicy> (as C<permission_engine>
and C<readability>), L<GPForum::Service::Notification::PreferenceStore>,
L<GPForum::Service::Community::RelationStore>,
L<GPForum::Service::Realtime::PgNotifier>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A preference store that dies is read as the inbox alone. The counters are
per process: C</metrics> reports a web process's, and a worker process,
which serves no C</metrics>, reports its badge failures only in its log.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
