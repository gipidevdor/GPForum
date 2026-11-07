# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Base;

use Mojo::Base 'Mojolicious::Controller', -async_await;
use v5.40;
use Scalar::Util qw(blessed);
use English      qw(-no_match_vars);

use Const::Fast;

use GPForum::Infrastructure::Text qw(trimmed);
use GPForum::Infrastructure::AsyncWork;
use GPForum::Infrastructure::RequestPromise;
use GPForum::Infrastructure::FileAsset;
use GPForum::Web::MediaResponse;
use GPForum::Log;
use GPForum::Web::Access;
use GPForum::Web::Guard;
use GPForum::Web::Responder;
use GPForum::Web::SecurityEvent;

our $VERSION = '0.001';

const my $HTTP_FORBIDDEN => 403;

sub async_work ($self) {
    return GPForum::Infrastructure::AsyncWork->shared;
}

sub await_p ( $self, @values ) {
    my $promise =
      GPForum::Infrastructure::RequestPromise->new->controller($self);
    if (   @values == 1
        && blessed( $values[0] )
        && $values[0]->isa('Mojo::Promise')
        && $values[0]->AWAIT_IS_READY )
    {
        # A cache hit has no asynchronous boundary to restore. Keep it ready
        # instead of manufacturing a relay and an extra event-loop turn.
        my ( @ready, $error );
        try { @ready = $values[0]->AWAIT_GET; }
        catch ($caught) { $error = $caught; };
        return defined $error
          ? $promise->reject($error)
          : $promise->resolve(@ready);
    }
    return $promise->resolve(@values);
}

sub call_p ( $self, $service, $method, @arguments ) {
    if ( !$self->stash('mojo.finished') ) { $self->render_later; }
    my $context = $self->stash('gp_db_query_stats_token');
    my $promise = $self->within_request(
        sub {
            my $async = $method . '_p';
            return $service->$async( @arguments, $context )
              if $service->can($async);
            my $abandoned = 0;
            $self->tx->on( finish => sub { $abandoned = 1; return; } );
            return $service->async_call_p( $method, \@arguments, $context,
                sub { return $abandoned; } )
              if $service->can('async_call_p');
            return $self->async_work->service_result_p( $service, $method,
                \@arguments, $context, sub { return $abandoned; } );
        }
    );
    return $self->await_p($promise);
}

sub file_p ( $self, $path, $type = undef ) {
    $self->render_later;
    return GPForum::Infrastructure::FileAsset->from_path_p($path)->then(
        sub ($asset) {
            return if $self->stash('mojo.finished');
            if (   !defined $type
                && !defined $self->res->headers->content_type
                && "$path" =~ /[.]([[:alnum:]]+)\z/msx )
            {
                $type = $self->app->types->type($1);
            }
            if ( defined $type ) { $self->res->headers->content_type($type); }
            return GPForum::Web::MediaResponse->new->render( $self, $asset,
                $asset->size . q{-} . $asset->mtime );
        }
    );
}

sub respond_p ( $self, $promise, $respond, $failure = undef ) {
    $self->render_later;
    my $finished = 0;
    $self->tx->on( finish => sub { $finished = 1; return; } );
    $promise->then(
        sub (@values) {
            return if $finished;
            my $work = sub { return $respond->(@values); };
            return $self->within_request($work);
        }
    )->catch(
        sub ($error) {
            return if $finished;
            my $work = sub {
                return $failure->($error) if $failure;
                return GPForum::Web::Guard->new->service_unavailable($self);
            };
            return $self->within_request($work);
        }
    );
    return;
}

sub work_p ( $self, $service, $method, $input ) {
    my $abandoned = 0;
    $self->tx->on( finish => sub { $abandoned = 1; return; } );
    return $self->async_work->service_p(
        $service, $method, $input,
        $self->stash('gp_db_query_stats_token'),
        sub { return $abandoned; }
    );
}

sub work_args_p ( $self, $service, $method, $arguments ) {
    my $abandoned = 0;
    $self->tx->on( finish => sub { $abandoned = 1; return; } );
    return $self->async_work->service_args_p(
        $service, $method, $arguments,
        $self->stash('gp_db_query_stats_token'),
        sub { return $abandoned; }
    );
}

sub within_request ( $self, $work ) {
    local $GPForum::Infrastructure::PgStorage::HTTP_PID = $PROCESS_ID;
    my $stats =
        $self->app->renderer->get_helper('gp_db_query_stats')
      ? $self->gp_db_query_stats
      : undef;
    my $scoped = sub {
        return GPForum::Log->in_context( $self->stash('gp_log_context'),
            $work );
    };
    return $stats
      ? $stats->in_context( $self->stash('gp_db_query_stats_token'), $scoped )
      : $scoped->();
}

# A write's command id: the Forum-style command_id field, or the older
# idempotency_key; empty when neither is given.
sub command_id_param ($self) {
    my $command_id = trimmed( $self->param('command_id') );
    if ( length $command_id ) {
        return $command_id;
    }

    return trimmed( $self->param('idempotency_key') );
}

# undef for an empty filter, never an empty list, so a hash built from it
# keeps its pairs.
sub optional_param ( $self, $name ) {
    my $value = trimmed( $self->param($name) );
    if ( length $value ) {
        return $value;
    }

    return undef;
}

sub render_payload ( $self, $input ) {
    return GPForum::Web::Responder->new->payload(
        {
            controller => $self,
            payload    => $input->{payload},
            status     => $input->{status},
            template   => $input->{template},
        }
    );
}

sub global_permission_scope {
    return {
        resource_id => undef,
        space_id    => undef,
    };
}

# Whether a writer may take part: a suspended member may not (ADR 0102).
# The refusal is recorded as a suspended_user_block under the action tried
# and answered 403; a store that cannot say answers 503, as an unreachable
# write does. True when they may.
async sub participating ( $self, $user_id, $action ) {
    my $decision;
    try {
        $decision = (
            await $self->call_p(
                $self->gp_suspension_store,
                'can_participate', $user_id
            )
        );
    }
    catch ($error) {
        $self->app->log->error("participation check failed: $error");
        GPForum::Web::Guard->new->service_unavailable($self);
        return 0;
    };
    return 1 if $decision->{ok};

    GPForum::Web::SecurityEvent->new->record_event( $self,
        'suspended_user_block',
        { action => $action, status => $HTTP_FORBIDDEN } );
    GPForum::Web::Guard->new->forbidden( $self,
        { error => 'user is suspended' } );

    return 0;
}

sub set_success_flash ( $self, $flash_key ) {
    if ( !$flash_key ) {
        return;
    }

    $self->flash( success => $self->t($flash_key) );

    return;
}

# What every area's controllers asked of their own copy: whether the
# request wants JSON, who is signed in, and the not-found and failure
# answers.
sub wants_json ($self) {
    return GPForum::Web::Access->new->wants_json($self);
}

sub current_user_id ($self) {
    return GPForum::Web::Access->new->user_id($self);
}

sub not_found ( $self, $error ) {
    return GPForum::Web::Guard->new->not_found( $self, $error );
}

sub system_failure ($self) {
    return GPForum::Web::Guard->new->system_failure($self);
}

1;

__END__

=head1 NAME

GPForum::Controller::Base - Request helpers every GPForum controller base
shares.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    use Mojo::Base 'GPForum::Controller::Base', -signatures;
use v5.40;

    my $command_id = $self->command_id_param;
    my $after      = $self->optional_param('after');

=head1 DESCRIPTION

The admin, attachment, forum, identity, moderation, notification and privacy
controller bases inherit from this class instead of each carrying its own
copy of these helpers. A base whose rule differs, such as the forum's
C<render_payload>, overrides it.

=head1 SUBROUTINES/METHODS

=head2 command_id_param

Returns the trimmed C<command_id> parameter, or the trimmed
C<idempotency_key> when C<command_id> is empty; an empty string when neither
is given.

=head2 optional_param

Returns the trimmed parameter, or undef when it is missing or blank. It is
undef, not an empty list, in list context too.

=head2 render_payload

Renders a payload hash as JSON or through its template, following the
request, via L<GPForum::Web::Responder/payload>.

=head2 global_permission_scope

Returns the explicit unscoped permission scope: both C<resource_id> and
C<space_id> undefined. L<GPForum::Service::Admin::PermissionGate> then
accepts global role bindings only.

=head2 participating

Takes the writer's user id and the action they tried. Answers true when
they may take part; for a suspended member it records a
C<suspended_user_block>, answers the request 403 and returns false. A
suspension store that cannot be read answers 503.

=head2 set_success_flash

Sets the C<success> flash to the translation of a flash key; does nothing
without one.

=head2 wants_json

Whether the request asks for JSON (L<GPForum::Web::Access>).

=head2 current_user_id

The signed-in member's id, or undef.

=head2 not_found

Takes an error and renders the not-found answer, JSON or a page as the
request asks (L<GPForum::Web::Guard>).

=head2 system_failure

Renders the internal-error answer, JSON or a page as the request asks.

=head2 await_p

Wraps a promise so async/await resumes inside the originating request's query
and logging context. No context is retained across a yield.

=head2 call_p

Defers rendering and uses a service's native promise API when present. A
persistent synchronous workflow runs in the bounded subprocess executor, with
its transaction, typed result rows and exceptions preserved.

=head2 file_p

Reads file metadata off the reactor and streams bounded chunks with backpressure,
including HEAD, byte ranges and conditional responses.

=head2 async_work

Returns the shared per-worker executor for blocking operations.

=head2 respond_p

Defers rendering until a promise settles, restores request counters and logging
for callbacks, and skips responses after disconnect. Admission failures answer 503.

=head2 work_p

Runs a persistent service method with one input in a bounded subprocess.

=head2 work_args_p

Runs a persistent service method with positional inputs in a bounded subprocess.

=head2 within_request

Scopes synchronous callback work to its original request's counters and logger.
The scope is restored before the callback's returned promise yields.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the C<t> translation helper registered during application startup.

=head1 DEPENDENCIES

L<Mojolicious::Controller>, L<GPForum::Web::Responder>.

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
