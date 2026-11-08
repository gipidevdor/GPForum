# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::Syndication;

use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;
use Const::Fast;
use Digest::SHA qw(sha256_hex);
use Mojo::Util  qw(encode);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Service::Forum::PostingNative;
use GPForum::Service::Integration::HttpClient;
use GPForum::Service::Integration::FeedParser;
use GPForum::X::Argument;
use GPForum::X::Unavailable;
use GPForum::X::Conflict;
use GPForum::X::RateLimited;
our $VERSION = '0.001';
const my $POLL_SECONDS      => 300;
const my $ETAG_LENGTH       => 512;
const my $HTTP_NOT_MODIFIED => 304;
const my $MODIFIED_LENGTH   => 128;
has policy_available => 0;
__PACKAGE__->requires(qw(schema config));
has client    => sub { return GPForum::Service::Integration::HttpClient->new; };
has parser    => sub { return GPForum::Service::Integration::FeedParser->new; };
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;
has recorder  => sub ($self) {
    return GPForum::Infrastructure::EventRecorder->new(
        schema => $self->schema );
};

sub request ( $self, $actor, $source ) {
    $self->_source($source);
    return $self->recorder->record_event( _requested( $actor, $source ) );
}

# request on a pooled asynchronous connection: one api function call.
async sub request_p ( $self, $actor, $source, $context = undef ) {
    $self->_source($source);
    return await $self->recorder->record_event_p(
        { _requested( $actor, $source ) }, $context );
}

sub _requested ( $actor, $source ) {
    return (
        event_type     => 'integration.feed.requested',
        aggregate_type => 'integration',
        aggregate_id   => GPForum::Infrastructure::Id->new->uuid,
        actor_id       => $actor,
        schema_version => 1,
        payload        => { source_url => $source }
    );
}

sub _require_policy ($self) {
    if ( !$self->policy_available ) {
        GPForum::X::Unavailable->throw(
            message => 'integration policy unavailable' );
    }
    return;
}

sub _source ( $self, $source ) {
    $self->_require_policy;
    my %allowed = map { $_ => 1 } @{ $self->config->syndication_sources };

    if ( !$allowed{ $source // q{} } ) {
        GPForum::X::Argument->throw(
            message => 'syndication source is not authorized' );
    }
    $self->client->https_url($source);
    return;
}

sub poll ( $self, $source ) {
    $self->_source($source);
    my $hash   = sha256_hex( encode( 'UTF-8', $source ) );
    my $cursor = $self->functions->row( 'integration_feed_begin',
        { source_hash => $hash, source_url => $source } );

    if ( !$cursor ) {
        GPForum::X::RateLimited->throw(
            message     => 'syndication source polling interval',
            retry_after => $POLL_SECONDS
        );
    }
    my $headers =
      { Accept =>
          'application/atom+xml, application/rss+xml, application/xml, text/xml'
      };
    my $saved = $cursor->{result};
    if ( length $saved->{etag} ) {
        $headers->{'If-None-Match'} = $saved->{etag};
    }
    if ( length $saved->{modified} ) {
        $headers->{'If-Modified-Since'} = $saved->{modified};
    }

    my $response =
      $self->client->request( 'GET', $source, { headers => $headers } );
    return { status => 'unchanged' } if $response->code == $HTTP_NOT_MODIFIED;

    if ( !$response->is_success ) {
        GPForum::X::Unavailable->throw(
            message => 'syndication source did not return a feed' );
    }
    my $items = $self->parser->parse( $response->text );
    return $self->schema->txn_do(
        sub {
            my $created = 0;
            for my $item ( @{$items} ) {
                my $row = $self->functions->row(
                    'integration_feed_stage',
                    {
                        %{$item},
                        source_hash => $hash,
                        item        => GPForum::Infrastructure::Id->new->uuid
                    }
                );
                $created += $row->{result}{created} ? 1 : 0;
            }
            my $etag = substr $response->headers->etag // q{}, 0, $ETAG_LENGTH;
            my $modified = substr $response->headers->last_modified // q{}, 0,
              $MODIFIED_LENGTH;
            $self->functions->row( 'integration_feed_finish',
                { source_hash => $hash, etag => $etag, modified => $modified }
            );
            return { status => 'staged', created => $created };
        }
    );
}

sub decide_with_posting ( $self, $input, $posting, $viewer ) {
    return $self->decide(
        $input,
        sub ($command) {
            return $posting->create_thread(
                { %{$command}, viewer => $viewer } );
        }
    );
}

sub decide ( $self, $input, $publish ) {
    $self->_require_policy;
    return $self->schema->txn_do(
        sub {
            my $found =
              $self->_pending( $self->functions->row( _find_call($input) ) );
            return $found->{answer} if $found->{answer};
            my $thread;
            if ( $input->{decision} eq 'published' ) {
                my $result = $publish->(
                    _publish_command(
                        $input, $found->{item}, $found->{source}
                    )
                );
                return $result if !$result->{ok};
                $thread = column_of( $result->{stored}{thread}, 'thread_id' );
                return { status => 'failed' } if !$thread;
            }
            my $answer =
              $self->functions->row( _decide_call( $input, $thread ) )
              ->{result};
            _confirm_authority( $thread, $answer );
            if ( $answer->{status} eq 'ok' ) {
                $self->recorder->record_audit(
                    _decided_audit( $input, $thread ) );
            }
            return $answer;
        }
    );
}

# decide_with_posting on pooled asynchronous connections. The item stays
# locked in this transaction while the posting workflow publishes the
# thread under the item's id as its command id, on this transaction's call
# layer: a second decision waits, a retried one replays the same thread, and
# a decision refused after the thread was written rolls the thread back
# with it, as the blocking path's one transaction does.
async sub decide_with_posting_p ( $self, $input, $posting, $viewer,
    $context = undef )
{
    $self->_require_policy;
    return await $self->functions->transaction_p(
        async sub ($scope) {
            my $found = $self->_pending(
                await $scope->row_p( _find_call($input), $context ) );
            return $found->{answer} if $found->{answer};
            my $thread;
            if ( $input->{decision} eq 'published' ) {
                my $command = {
                    %{
                        _publish_command( $input, $found->{item},
                            $found->{source} )
                    },
                    viewer => $viewer
                };
                my $result =
                  await _published_p( $posting, $command, $context, $scope );
                return $result if !$result->{ok};
                $thread = column_of( $result->{stored}{thread}, 'thread_id' );
                return { status => 'failed' } if !$thread;
            }
            my $answer =
              ( await $scope->row_p( _decide_call( $input, $thread ), $context )
              )->{result};
            _confirm_authority( $thread, $answer );
            if ( $answer->{status} eq 'ok' ) {
                await $scope->row_p(
                    'ops_record_audit',
                    $self->recorder->audit_call(
                        _decided_audit( $input, $thread )
                    ),
                    $context
                );
            }
            return $answer;
        },
        $context
    );
}

# The thread created as the posting workflow creates it, its reads and its
# write on $scope (Forum::PostingNative); a double without the native path
# answers in the worker.
async sub _published_p ( $posting, $command, $context, $scope ) {
    return $posting->create_thread($command)
      if !$posting->can('async_call_p');

    return await GPForum::Service::Forum::PostingNative->new(
        workflow => $posting,
        scope    => $scope
    )->call_p( 'create_thread', [$command], $context, undef );
}

sub _find_call ($input) {
    return ( 'integration_feed_find',
        { item => $input->{item_id}, actor => $input->{actor_user_id} } );
}

# The found item, still pending, and its configured source; or the answer
# when it is gone, decided, or its source no longer configured.
sub _pending ( $self, $row ) {
    return { answer => { status => 'not_found' } } if !$row;
    my $item = $row->{result};
    return { answer => { status => 'unchanged' } }
      if $item->{status} ne 'pending';
    my ($source) =
      grep { sha256_hex( encode( 'UTF-8', $_ ) ) eq $item->{source_hash} }
      @{ $self->config->syndication_sources };
    return { answer => { status => 'refused' } } if !defined $source;
    return { item   => $item, source => $source };
}

sub _publish_command ( $input, $item, $source ) {
    return {
        command_id     => $item->{item_id},
        title          => $item->{title},
        body_source    => $item->{url} . "\n\n" . $source,
        author_user_id => $input->{actor_user_id},
        category_id    => $input->{category_id},
        visibility     => 'public'
    };
}

sub _decide_call ( $input, $thread ) {
    return (
        'integration_feed_decide',
        {
            actor  => $input->{actor_user_id},
            item   => $input->{item_id},
            status => $input->{decision},
            thread => $thread
        }
    );
}

sub _confirm_authority ( $thread, $answer ) {
    if ( $thread && $answer->{status} ne 'ok' ) {
        GPForum::X::Conflict->throw(
            message => 'feed publication lost its review authority' );
    }
    return;
}

sub _decided_audit ( $input, $thread ) {
    return (
        action      => 'integration.feed.' . $input->{decision},
        actor_id    => $input->{actor_user_id},
        target_type => 'integration',
        target_id   => $input->{item_id},
        metadata    => { thread_id => $thread }
    );
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::Syndication - Import authorized syndication into a deduplicated staff review queue.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Integration::Syndication->new;

=head1 DESCRIPTION

Import authorized syndication into a deduplicated staff review queue. Core owns configuration, authorization and presentation.

=head1 SUBROUTINES/METHODS

=head2 request

Queues a poll only for an exact configured HTTPS source.

=head2 request_p

Queues a poll as L</request> does, recording its event on a pooled
asynchronous connection.

=head2 poll

Rechecks source authorization, uses conditional fetches and stages deduplicated title/link candidates.

=head2 decide

Publishes a separately approved candidate through the normal forum workflow or records rejection in the same transaction.

=head2 decide_with_posting

Runs a feed decision and its synchronous posting callback as one service operation. The caller isolates this complete workflow; a transaction never receives an unresolved promise.

=head2 decide_with_posting_p

Decides as L</decide_with_posting> does, on pooled asynchronous
connections, in one transaction: the item stays locked while the posting
workflow publishes the thread under the item's id on that transaction's
call layer, then the decision and its audit row commit with the thread. A
decision refused after the thread was written rolls the thread back.

=head1 DIAGNOSTICS

Invalid configuration and transport failures raise typed exceptions.

=head1 CONFIGURATION AND ENVIRONMENT

The composition layer supplies validated settings and dependencies.

=head1 DEPENDENCIES

The Good Phorum runtime and the modules named above.

=head1 INCOMPATIBILITIES

Network capabilities are independent of the frozen local Plugin API v1.

=head1 BUGS AND LIMITATIONS

External operations depend on the configured provider and its availability.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
