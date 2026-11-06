# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Operations::CacheFactory;

use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Infrastructure::Text qw(has_text);
use GPForum::Service::Operations::LocalCache;
use GPForum::Service::Operations::NoSharedCache;
use GPForum::Service::Operations::SharedCache;
use GPForum::Service::Operations::TieredCache;

our $VERSION = '0.001';

# Each process's own cache, with GlifiStore behind it when one is
# configured. GlifiStore is optional everywhere (D2): without one the local
# cache is all there is, in production as on a laptop -- and the stack is a
# TieredCache all the same, over an empty shared layer, so the bootstrap gives
# it the invalidation bus that tells every other process. A local cache
# alone had no bus, and a moderator's hide reached no worker but its own.
sub build ( $, $config ) {
    return GPForum::Service::Operations::TieredCache->new(
        l1 => _local_cache($config),
        l2 => _shared_cache($config)
          // GPForum::Service::Operations::NoSharedCache->new,
    );
}

sub _local_cache ($config) {
    return GPForum::Service::Operations::LocalCache->new(
        max_entries => $config->local_cache_max_entries,
        namespace   => 'gpforum',
    );
}

sub _shared_cache ($config) {
    if ( !has_text( $config->glifistore_url ) ) {
        return undef;
    }

    return GPForum::Service::Operations::SharedCache->connect_required(
        {
            namespace   => 'gpforum',
            ttl_seconds => $config->category_cache_ttl_seconds,
            url         => $config->glifistore_url,
        }
    );
}

1;

__END__

=head1 NAME

GPForum::Service::Operations::CacheFactory - Build the process cache stack.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $cache = GPForum::Service::Operations::CacheFactory->build($config);

=head1 DESCRIPTION

Constructs the disposable application cache used by public SSR rendering,
category read models, and worker tag invalidation.

C<LocalCache> is always L1. When C<glifistore_url> is set, L2 is
L<GPForum::Service::Operations::SharedCache>; without it, in every
environment, it is L<GPForum::Service::Operations::NoSharedCache>, and each
process keeps its own cache. Either way the stack is a
L<GPForum::Service::Operations::TieredCache>, which the bootstrap gives the
invalidation bus. PostgreSQL remains the only
source of truth; GlifiStore is never treated as authoritative.

=head1 SUBROUTINES/METHODS

=head2 build

Returns a TieredCache: L1 the process's own, L2 GlifiStore when it is
configured and the empty layer when it is not.

=head1 DIAGNOSTICS

None: a GlifiStore URL that does not answer is found on the first call, not
here (see L</BUGS AND LIMITATIONS>).

=head1 CONFIGURATION AND ENVIRONMENT

Reads C<glifistore_url>, C<local_cache_max_entries>, and
C<category_cache_ttl_seconds> from L<GPForum::Config>.

=head1 DEPENDENCIES

Uses L<Mojo::Base>, L<GPForum::Service::Operations::LocalCache>,
L<GPForum::Service::Operations::NoSharedCache>,
L<GPForum::Service::Operations::SharedCache> and
L<GPForum::Service::Operations::TieredCache>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A reachable GlifiStore is not required at process start: the first call
tries it. After a failed call the shared layer skips GlifiStore for fifteen
seconds (lookups, writes, invalidations and the readiness ping alike), so a
hung server costs each process one timeout rather than every request one.
Meanwhile the cache degrades to L1 and PostgreSQL, and an invalidation
skipped then leaves the L2 entry until its TTL. The ERASE of an absent key is
not a failure, and an overloaded server keeps its connection.

Tag invalidation erases one token per tag; an entry written under an older
token, or before tokens existed, misses. An entry filled from L2 into L1
keeps only the lifetime it had left in L2. The shared client is opened with
C<connect_required>.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
