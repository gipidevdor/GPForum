# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::Syndication;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;
use Digest::SHA qw(sha256_hex);
use Mojo::Util  qw(encode);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Row;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
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
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};
has recorder => sub ($self) {
    return GPForum::Infrastructure::EventRecorder->new(
        schema => $self->schema );
};

sub request ( $self, $actor, $source ) {
    $self->_source($source);
    return $self->recorder->record_event(
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
            my $row = $self->functions->row( 'integration_feed_find',
                { item => $input->{item_id}, actor => $input->{actor_user_id} }
            );
            return { status => 'not_found' } if !$row;
            my $item = $row->{result};
            return { status => 'unchanged' } if $item->{status} ne 'pending';
            my ($source) = grep {
                sha256_hex( encode( 'UTF-8', $_ ) ) eq $item->{source_hash}
            } @{ $self->config->syndication_sources };
            return { status => 'refused' } if !defined $source;
            my $thread;
            if ( $input->{decision} eq 'published' ) {
                my $result = $publish->(
                    {
                        command_id     => $item->{item_id},
                        title          => $item->{title},
                        body_source    => $item->{url} . "\n\n" . $source,
                        author_user_id => $input->{actor_user_id},
                        category_id    => $input->{category_id},
                        visibility     => 'public'
                    }
                );
                return $result if !$result->{ok};
                $thread = GPForum::Infrastructure::Row->column(
                    $result->{stored}{thread}, 'thread_id' );
                return { status => 'failed' } if !$thread;
            }
            my $answer = $self->functions->row(
                'integration_feed_decide',
                {
                    actor  => $input->{actor_user_id},
                    item   => $input->{item_id},
                    status => $input->{decision},
                    thread => $thread
                }
            )->{result};
            if ( $thread && $answer->{status} ne 'ok' ) {
                GPForum::X::Conflict->throw(
                    message => 'feed publication lost its review authority' );
            }
            if ( $answer->{status} eq 'ok' ) {
                $self->recorder->record_audit(
                    action      => 'integration.feed.' . $input->{decision},
                    actor_id    => $input->{actor_user_id},
                    target_type => 'integration',
                    target_id   => $input->{item_id},
                    metadata    => { thread_id => $thread }
                );
            }
            return $answer;
        }
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

=head2 poll

Rechecks source authorization, uses conditional fetches and stages deduplicated title/link candidates.

=head2 decide

Publishes a separately approved candidate through the normal forum workflow or records rejection in the same transaction.

=head2 decide_with_posting

Runs a feed decision and its synchronous posting callback as one service operation. The caller isolates this complete workflow; a transaction never receives an unresolved promise.

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
