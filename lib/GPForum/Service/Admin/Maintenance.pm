# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Admin::Maintenance;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::Service::Search::Indexer;
use GPForum::Service::Search::RebuildRun;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $SCHEMA_VERSION => 1;

# Every public page, and the reader caches the public pages are built from
# (the anonymous category list).
const my @PURGED_TAGS =>
  qw(forum:public-html categories forum-index announcements);

__PACKAGE__->requires(qw(cache));
has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };
has indexer    => sub ($self) {
    return GPForum::Service::Search::Indexer->new( schema => $self->schema );
};
has rebuild_run => sub ($self) {
    return GPForum::Service::Search::RebuildRun->new(
        id_service => $self->id_service,
        indexer    => $self->indexer,
        schema     => $self->schema,
    );
};
has recorder  => \&GPForum::Infrastructure::EventRecorder::for_service;
has schema    => undef;    # optional: the defaults below are built from it
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each operation is written once, as its promise method (ADR 0177); the
# search services it awaits block with it.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(search_status request_search_rebuild purge_public_cache));
GPForum::Infrastructure::SqlFunction->blocking_parts(qw(indexer rebuild_run));

# 6.5: the maintenance the shell could do and the console could not. What an
# operator reads first: is search behind, and how did the last rebuild go.
async sub search_status_p ( $self, $context = undef ) {
    return {
        lag    => await $self->indexer->observe_lag_p($context),
        latest => await $self->rebuild_run->latest_p($context),
    };
}

# Starts a search rebuild through the outbox (Search::RebuildRun) and audits
# who asked: inside the caller's transaction ($scope, the call layer
# transaction_p hands its work) or in one of its own.
async sub request_search_rebuild_p (
    $self, $input,
    $context = undef,
    $scope = undef
  )
{
    my $work = async sub ($transaction) {
        my $correlation_id = $self->id_service->uuid;
        my $run            = await $self->rebuild_run->request_p(
            _rebuild_request( $input, $correlation_id ),
            $context, $transaction );
        await $self->_audit_p( $transaction,
            _rebuild_audit( $input, $correlation_id, $run ), $context );
        return { run_id => $run->{run_id}, status => 'requested' };
    };
    return await(
          $scope
        ? $work->($scope)
        : $self->_functions->transaction_p( $work, $context )
    );
}

sub _rebuild_request ( $input, $correlation_id ) {
    return {
        actor_id       => $input->{actor_user_id},
        correlation_id => $correlation_id,
        entity_type    => 'all',
    };
}

sub _rebuild_audit ( $input, $correlation_id, $run ) {
    return {
        action         => 'admin.search_rebuild_requested',
        actor_user_id  => $input->{actor_user_id},
        correlation_id => $correlation_id,
        metadata       => { run_id => $run->{run_id}, via => 'web' },
        target_id      => $run->{run_id},
        target_type    => 'search_rebuild',
    };
}

# Drops every cached public page, in every web process (the cache's
# invalidation bus carries it), and audits who did, inside the caller's
# transaction ($scope) or on its own. Nothing is lost: each page is
# rendered again on its next request.
#
# A tag the cache could not purge in GlifiStore (its invalidate_tag returns
# nothing: the shared layer is paused after a failure, or failed now) leaves
# the pages there current until their TTL, while every process's own copy is
# gone. The purge said "purged" all the same, and an operator who purged to
# take a page down believed it was down. It is now "purged_locally", in the
# answer and in the audit row, with the tags concerned.
async sub purge_public_cache_p ( $self, $input, $context = undef,
    $scope = undef )
{
    my $functions = $scope // $self->_functions;
    my $purge     = $self->_purge;
    await $self->_audit_p( $functions, $self->_purge_audit( $input, $purge ),
        $context );

    return $purge;
}

# The public cache's tags dropped, with those its shared layer did not take.
sub _purge ($self) {
    my @unreached;
    for my $tag (@PURGED_TAGS) {
        if ( !defined $self->cache->invalidate_tag($tag) ) {
            push @unreached, $tag;
        }
    }
    return {
        status         => @unreached ? 'purged_locally' : 'purged',
        tags           => [@PURGED_TAGS],
        unreached_tags => [@unreached],
    };
}

sub _purge_audit ( $self, $input, $purge ) {
    my $correlation_id = $self->id_service->uuid;
    return {
        action         => 'admin.cache_purged',
        actor_user_id  => $input->{actor_user_id},
        correlation_id => $correlation_id,
        metadata       => {
            status         => $purge->{status},
            tags           => [ @{ $purge->{tags} } ],
            unreached_tags => [ @{ $purge->{unreached_tags} } ],
            via            => 'web',
        },
        target_id   => $correlation_id,
        target_type => 'cache',
    };
}

sub _audit_p ( $self, $functions, $input, $context ) {
    return $functions->row_p( 'ops_record_audit',
        $self->recorder->audit_call( %{ $self->_audit_row($input) } ),
        $context );
}

sub _audit_row ( $self, $input ) {
    return {
        action         => $input->{action},
        actor_id       => $input->{actor_user_id},
        correlation_id => $input->{correlation_id},
        created_at     => $self->clock->now_iso8601,
        metadata       => $input->{metadata},
        previous_hash  => undef,
        record_hash    => q{},
        schema_version => $SCHEMA_VERSION,
        target_id      => $input->{target_id},
        target_type    => $input->{target_type},
    };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'maintenance needs the PostgreSQL function layer' );
}

1;

__END__

=head1 NAME

GPForum::Service::Admin::Maintenance - Search rebuilds, search lag and cache purges for the console.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $maintenance = GPForum::Service::Admin::Maintenance->new(
        cache  => $cache,
        schema => $schema,
    );
    my $status = $maintenance->search_status;
    $maintenance->request_search_rebuild( { actor_user_id => $admin_id } );
    $maintenance->purge_public_cache( { actor_user_id => $admin_id } );

=head1 DESCRIPTION

The console side of operations that had only a shell command (quality
program 6.5): the search index's lag and last rebuild, a rebuild run through
the outbox, and a purge of the public page cache. Each write is audited.

=head1 SUBROUTINES/METHODS

Each operation is written once, as its promise method, and takes an
optional query context; the blocking methods are those bodies settled on
the blocking layer, with the indexer and the rebuild run blocking too
(ADR 0177).

=head2 search_status_p

Resolves with the search lag and the latest rebuild run. C<search_status>
is its blocking twin.

=head2 request_search_rebuild_p

Takes a hash reference with C<actor_user_id>, an optional query context,
and the call layer of the caller's transaction, when the request joins it;
without one it runs in a transaction of its own. Starts a rebuild and
audits it; resolves with its run id. C<request_search_rebuild> is its
blocking twin.

=head2 purge_public_cache_p

Takes a hash reference with C<actor_user_id>, an optional query context and
the caller's call layer, as L</request_search_rebuild_p> does. Invalidates
every cached public page (the tags C<forum:public-html>, C<categories>,
C<forum-index> and C<announcements>, the last being the active list every
page shows) in this process, in the others through the cache's bus, and
in the shared cache, and records an C<admin.cache_purged> audit row.
Resolves with C<< { status, tags, unreached_tags } >>: C<status> is
C<purged>, or C<purged_locally> when the shared cache was not reached for
one of the tags (its C<invalidate_tag> returned C<undef>), which
C<unreached_tags> lists; the pages under those tags stay in the shared
cache until their TTL. The audit row's metadata holds the same C<status>,
C<tags> and C<unreached_tags>, and C<via> (C<web>).
C<purge_public_cache> is its blocking twin.

=head1 DIAGNOSTICS

Dies when the database does; the workflow's transaction rolls back. Throws
L<GPForum::X::Unavailable> without the function layer.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Search::RebuildRun>,
L<GPForum::Infrastructure::EventRecorder>.

Extends L<GPForum::Base>: built without C<cache> it throws
L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A purge that did not reach the shared cache is not retried: the pages it
left there expire within their TTL, and purging again once GlifiStore
answers clears them sooner.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
