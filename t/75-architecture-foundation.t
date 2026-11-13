# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Mojo::File qw(path);
use Test::Fatal;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Domain::EventEnvelope;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Jobs::EventPayload;
use GPForum::Security::BrowserHeaders;
use GPForum::Infrastructure::OutboxMessageBuilder;
use GPForum::Test::Id;
use GPForum::Test::RecorderFunctions;
use GPForum::Test::Schema;
use GPForum::Theme::Registry;
use GPForum::Web::RenderPolicy;

our $VERSION = '0.001';

subtest
  'domain event envelope keeps durable and transport contracts aligned' => sub {
    my $envelope = GPForum::Domain::EventEnvelope->new;
    my $event    = $envelope->record(
        actor_id          => 'user-1',
        aggregate_id      => 'post-1',
        aggregate_type    => 'post',
        aggregate_version => 2,
        causation_id      => 'event-parent',
        correlation_id    => 'correlation-1',
        event_id          => 'event-1',
        event_type        => 'post.created',
        metadata          => { request_id => 'request-1' },
        payload           => { thread_id  => 'thread-1' },
        schema_version    => 1,
        timestamp         => '2026-05-28T08:00:00Z',
    );

    is( $event->{schema_version}, 1, 'event record preserves schema version' );
    is( $event->{metadata}{event_id},
        'event-1', 'event metadata carries event id' );
    is( $event->{metadata}{actor}{id},
        'user-1', 'event metadata carries actor id' );
    is( $event->{metadata}{transport}{listen_notify_channel},
        'gpforum_domain_events',
        'event metadata prepares LISTEN/NOTIFY channel' );

    my $payload = $envelope->transport_payload($event);
    is( $payload->{contract},
        'gpforum.domain_event', 'transport payload names event contract' );
    is( $payload->{contract_version},
        1, 'transport payload versions event contract' );
    is( $payload->{event_type},
        'post.created', 'transport keeps legacy event_type field' );
    is( $payload->{domain_payload}{thread_id},
        'thread-1', 'transport keeps legacy domain_payload field' );
    is( $payload->{aggregate}{type},
        'post', 'transport exposes structured aggregate metadata' );
    is( $payload->{transport}{nats_subject},
        'gpforum.domain_events', 'transport prepares future NATS subject' );
  };

subtest
  'event recorder appends event, outbox message, and audit through one boundary'
  => sub {
    my $log      = GPForum::Test::RecorderFunctions->new;
    my $recorder = _recorder($log);

    my $event = $recorder->record_event(
        actor_id       => 'user-1',
        aggregate_id   => 'thread-1',
        aggregate_type => 'thread',
        correlation_id => 'correlation-1',
        event_type     => 'thread.created',
        payload        => { category_id => 'category-1' },
        timestamp      => '2026-05-28T08:00:00Z',
    );
    my $first_audit = $recorder->record_audit(
        action         => 'thread.created',
        actor_id       => 'user-1',
        correlation_id => $event->{correlation_id},
        metadata       => { title => 'Welcome' },
        target_id      => 'thread-1',
        target_type    => 'thread',
    );

    is( scalar @{ $log->events }, 1, 'recorder creates one event log row' );
    is( scalar @{ $log->outbox }, 1, 'recorder creates one outbox row' );
    is( scalar @{ $log->audits }, 1, 'recorder creates one audit row' );
    is( $log->outbox->[0]{payload}{contract},
        'gpforum.domain_event', 'outbox row stores standard event contract' );
    is( $log->audits->[0]{correlation_id},
        'correlation-1', 'audit correlation matches event correlation' );
    ok(
        length $first_audit->{record_hash},
        'audit record hash is computed by recorder'
    );
    ok(
        $recorder->verify_audit_record($first_audit),
        'computed audit hash verifies against canonical record'
    );
    is( $first_audit->{previous_hash},
        undef, 'first audit row has no previous hash' );

    my $second_audit = $recorder->record_audit(
        action         => 'thread.updated',
        actor_id       => 'user-1',
        correlation_id => $event->{correlation_id},
        metadata       => { title => 'Welcome back' },
        target_id      => 'thread-1',
        target_type    => 'thread',
    );
    is( scalar @{ $log->audits }, 2, 'recorder creates a second audit row' );
    is(
        $second_audit->{previous_hash},
        $first_audit->{record_hash},
        'audit hash chain links to previous row'
    );
    isnt(
        $second_audit->{record_hash},
        $first_audit->{record_hash},
        'audit hash changes with record content'
    );

    my $third_audit = $recorder->record_audit(
        action         => 'thread.moderated',
        actor_id       => 'user-2',
        correlation_id => $event->{correlation_id},
        metadata       => { moderation_state => 'locked' },
        previous_hash  => undef,
        record_hash    => q{},
        target_id      => 'thread-1',
        target_type    => 'thread',
    );
    is(
        $third_audit->{previous_hash},
        $second_audit->{record_hash},
        'explicit blank audit hash inputs still preserve the hash chain'
    );
    ok(
        $recorder->verify_audit_record($third_audit),
        'audit verifier accepts an untampered chained record'
    );

    my %tampered_audit = %{$third_audit};
    $tampered_audit{metadata} = { moderation_state => 'visible' };
    ok(
        !$recorder->verify_audit_record( \%tampered_audit ),
        'audit verifier rejects tampered metadata'
    );
  };

# The conflicts the functions resolve on the database -- an outbox id or an
# audit id taken, an outbox row left by an earlier write -- are
# t/integration/postgres-event-recorder.t's; a raced event id is
# t/integration/postgres-partition-conflicts.t's.
subtest 'event recorder reuses unique outbox idempotency key' => sub {
    my $log      = GPForum::Test::RecorderFunctions->new;
    my $recorder = _recorder($log);
    my %input    = (
        actor_id       => 'user-1',
        aggregate_id   => 'thread-1',
        aggregate_type => 'thread',
        correlation_id => 'correlation-1',
        event_id       => 'event-reuse-1',
        event_type     => 'thread.created',
        payload        => { category_id => 'category-1' },
        timestamp      => '2026-05-28T08:00:00Z',
    );

    my $event = $recorder->record_event(%input);
    is( $event->{event_id}, 'event-reuse-1', 'recorder stores the event id' );
    is( scalar @{ $log->events }, 1, 'recorder creates one event log row' );
    is( scalar @{ $log->outbox }, 1, 'recorder creates one outbox row' );

    my $same_event = $recorder->record_event(%input);
    ok( $same_event->{skipped},
        'already-recorded event skip does not insert a second row' );
    is( $same_event->{event_id},
        'event-reuse-1', 'already-recorded event keeps the original event id' );
    is( scalar @{ $log->events },
        1, 'already-recorded event does not insert a second event row' );
    is( scalar @{ $log->outbox },
        1, 'already-recorded event does not insert a second outbox row' );
    ok(
        $log->sent('ops_record_event')->[0]{explicit},
        'a caller\'s event id is sent as one to lock'
    );
};

subtest 'moderation write stores use the shared event recorder boundary' =>
  sub {
    for my $store (
        qw(
        ActionStore
        ReportStore
        SuspensionStore
        )
      )
    {
        my $source =
          path( 'lib/GPForum/Service/Moderation', "$store.pm" )->slurp;
        like(
            $source,
            qr/GPForum::Infrastructure::EventRecorder/msx,
            "$store depends on event recorder"
        );
        unlike( $source, qr/Outbox::MessageBuilder/msx,
            "$store does not build outbox messages directly" );
    }
  };

subtest 'privacy write stores use the shared event recorder boundary' => sub {
    for my $store (
        qw(
        DeletionWorkflow
        RetentionHoldStore
        )
      )
    {
        my $source = path( 'lib/GPForum/Service/Privacy', "$store.pm" )->slurp;

        like(
            $source,
            qr/GPForum::Infrastructure::EventRecorder/msx,
            "$store depends on event recorder"
        );
        unlike( $source, qr/Outbox::MessageBuilder/msx,
            "$store does not build outbox messages directly" );
    }
};

subtest 'portability export writes use the shared event recorder boundary' =>
  sub {
    my $source =
      path('lib/GPForum/Service/Portability/ExportBundleBuilder.pm')->slurp;

    like(
        $source,
        qr/GPForum::Infrastructure::EventRecorder/msx,
        'export bundle builder depends on event recorder'
    );
    unlike( $source, qr/Outbox::MessageBuilder/msx,
        'export bundle builder does not build outbox messages directly' );
  };

subtest 'attachment lifecycle writes use the shared event recorder boundary' =>
  sub {
    my $source = path('lib/GPForum/Service/Attachment/Store.pm')->slurp;

    like(
        $source,
        qr/GPForum::Infrastructure::EventRecorder/msx,
        'attachment store depends on event recorder'
    );
    unlike( $source, qr/Outbox::MessageBuilder/msx,
        'attachment store does not build outbox messages directly' );
    unlike(
        $source,
        qr/resultset[(]'EventLog'[)]->create/msx,
        'attachment store does not write EventLog directly'
    );
    unlike(
        $source,
        qr/resultset[(]'OutboxMessage'[)]->create/msx,
        'attachment store does not write OutboxMessage directly'
    );
  };

subtest 'admin role audit writes use the shared event recorder boundary' =>
  sub {
    for my $store (
        qw(
        RoleBindingStore
        RoleCatalog
        )
      )
    {
        my $source = path( 'lib/GPForum/Service/Admin', "$store.pm" )->slurp;

        like(
            $source,
            qr/GPForum::Infrastructure::EventRecorder/msx,
            "$store depends on event recorder"
        );
        unlike(
            $source,
            qr/resultset[(]'AuditLog'[)]->create/msx,
            "$store does not write AuditLog directly"
        );
    }
  };

subtest 'service layer routes core event and audit writes through recorder' =>
  sub {
    my @files = grep { "$_" =~ /[.]pm\z/msx }
      path('lib/GPForum/Service')->list_tree->each;

    for my $file (@files) {
        my $source = $file->slurp;
        unlike(
            $source,
            qr/resultset[(]'(EventLog|OutboxMessage|AuditLog)'[)]->create/msx,
            "$file does not write event, outbox, or audit rows directly"
        );
    }
  };

subtest 'outbox message builder preserves worker compatibility' => sub {
    my $builder = GPForum::Infrastructure::OutboxMessageBuilder->new(
        id_service => GPForum::Test::Id->new, );
    my $message = $builder->for_event(
        {
            actor_id          => 'user-1',
            aggregate_id      => 'post-1',
            aggregate_type    => 'post',
            aggregate_version => 1,
            correlation_id    => 'correlation-1',
            event_id          => 'event-1',
            event_type        => 'post.created',
            idempotency_key   => 'post.created:post-1',
            metadata          => {},
            payload           => { thread_id => 'thread-1' },
            schema_version    => 1,
        }
    );

    is( $message->{queue}, 'events', 'outbox queue is unchanged' );
    is( $message->{job_type}, 'domain_event.dispatch',
        'outbox job type is unchanged' );
    is( $message->{payload}{event_type},
        'post.created', 'worker-compatible event_type remains top-level' );
    is( $message->{payload}{domain_payload}{thread_id},
        'thread-1', 'worker-compatible domain payload remains top-level' );
    is( $message->{payload}{metadata}{transport}{minion_job},
        'domain_event.dispatch', 'payload carries transport metadata' );
};

subtest 'job event payload normalizes structured envelopes for workers' => sub {
    my $payload = GPForum::Jobs::EventPayload->new->normalize(
        {
            actor     => { id => 'user-1' },
            aggregate => {
                id      => 'post-1',
                type    => 'post',
                version => 1,
            },
            event_type => 'post.created',
            payload    => { thread_id => 'thread-1' },
        }
    );

    is( $payload->{actor_id}, 'user-1', 'job payload exposes legacy actor id' );
    is( $payload->{aggregate_id},
        'post-1', 'job payload exposes legacy aggregate id' );
    is( $payload->{domain_payload}{thread_id},
        'thread-1', 'job payload exposes legacy domain payload' );
};

subtest 'browser security headers are testable outside bootstrap' => sub {
    my $headers = GPForum::Security::BrowserHeaders->new;
    my $csp     = $headers->content_security_policy;

    like( $csp, qr/default-src [ ] 'self'/msx, 'CSP keeps default-src self' );
    like( $csp, qr/script-src [ ] 'self'/msx,  'CSP declares script source' );
    like( $csp, qr/style-src [ ] 'self'/msx,   'CSP declares style source' );
    like( $csp, qr/object-src [ ] 'none'/msx,  'CSP forbids object content' );
    like(
        $headers->hsts_policy,
        qr/\A max-age= [[:digit:]]+ ; [ ] includeSubDomains \z/msx,
        'HSTS policy is a max-age includeSubDomains header'
    );
    ok( !$headers->include_hsts,
        'HSTS is off until secure transport is enabled' );
};

subtest 'SSR render policy centralizes raw HTML decisions' => sub {
    my $policy = GPForum::Web::RenderPolicy->new;

    is(
        $policy->trusted_html(
            context => 'search.snippet',
            html    => '<mark>Forum</mark>',
        ),
        '<mark>Forum</mark>',
        'trusted search snippets can pass through the policy'
    );
    like(
        exception {
            $policy->trusted_html(
                context => 'unknown',
                html    => '<script>alert(1)</script>',
            );
        },
        qr/untrusted [ ] html [ ] context/msx,
        'unknown raw HTML contexts are rejected'
    );
    is(
        $policy->attribute( name => 'aria-label', value => 'A&B' ),
        ' aria-label="A&amp;B"',
        'attribute helper escapes values'
    );
    for my $unsafe ( 'on click', '1x', q{x"y}, "d\N{U+00E4}ta" ) {
        my $error = exception { $policy->attribute( name => $unsafe ) };
        isa_ok( $error, 'GPForum::X::Argument', "attribute name '$unsafe'" );
        like(
            "$error",
            qr/unsafe [ ] attribute [ ] name/msx,
            'names the unsafe attribute'
        );
    }
};

subtest 'theme registry exposes explicit theme contracts' => sub {
    my $registry = GPForum::Theme::Registry->new;

    is_deeply(
        $registry->supported_themes,
        [qw(auto default dark high_contrast)],
        'theme registry names automatic, light, dark and high contrast themes'
    );
    is_deeply(
        $registry->theme_colors('auto'),
        [
            { color => '#f2f2f7', media => '(prefers-color-scheme: light)' },
            { color => '#000000', media => '(prefers-color-scheme: dark)' },
        ],
        'the automatic theme names a browser colour for light and for dark'
    );
    is_deeply(
        $registry->theme_colors('dark'),
        [ { color => '#000000' } ],
        'a theme with one palette names one'
    );
    is( $registry->color_scheme('auto'),
        'light dark', 'the automatic theme may be either scheme' );
    ok( $registry->supported('dark'), 'dark theme is supported' );
    is( $registry->theme_color('unknown'),
        '#f2f2f7', 'unknown theme falls back safely to default color' );
    is( $registry->theme('high_contrast')->{foreground},
        '#000000', 'high contrast theme exposes readable foreground token' );
    is( $registry->color_scheme('dark'),
        'dark', 'dark theme exposes browser color scheme metadata' );
    is( $registry->token( 'default', 'primary' ),
        '#00509e', 'theme registry exposes semantic tokens by name' );
    is_deeply(
        [ map { $_->[0] } @{ $registry->css_variables('default') } ],
        [ map { "color-$_" =~ s/_/-/gmsxr } @{ $registry->token_names } ],
        'theme registry exports CSS variable names for every token'
    );
    is( $registry->theme_options('dark')->[2]{current},
        1, 'theme options mark the current theme' );
};

done_testing();

# The recorder on its functions over rows kept in memory.
sub _recorder {
    my ($log) = @_;

    return GPForum::Infrastructure::EventRecorder->new(
        functions  => $log,
        id_service => GPForum::Test::Id->new,
        schema     => GPForum::Test::Schema->new,
    );
}

1;
