# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Operations::NoSharedCache;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# The shared layer of a forum without GlifiStore: it holds nothing, so the
# process's own cache is all there is, and it answers every write as done.
# It exists so that the stack is a TieredCache whatever is configured, and
# a TieredCache carries the invalidation bus: without one, a moderator's
# hide reached no web worker but the one that served it.

sub put ( $, $key, $value, $options = undef ) { return 0; }

sub lookup ( $, $key ) { return undef; }

sub invalidate ( $, $key ) { return 0; }

sub invalidate_tag ( $, $tag ) { return 0; }

sub purge_expired ($self) { return 0; }

sub clear ($self) { return 0; }

sub snapshot ($self) { return { kind => 'none' }; }

1;

__END__

=head1 NAME

GPForum::Service::Operations::NoSharedCache - The empty shared layer of a forum without GlifiStore.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $cache = GPForum::Service::Operations::TieredCache->new(
        l1 => $local,
        l2 => GPForum::Service::Operations::NoSharedCache->new,
    );

=head1 DESCRIPTION

The second layer L<GPForum::Service::Operations::TieredCache> stands on
when no GlifiStore is configured (D2: GlifiStore is optional). It holds
nothing: a lookup misses, a write or a purge is done at once. With it the
cache stack is tiered in every configuration, and so carries
L<GPForum::Service::Operations::CacheInvalidationBus>, which tells every
other process of an invalidation. It answers no C<ping> and no C<ticket>:
TieredCache reads that as the local fallback.

=head1 SUBROUTINES/METHODS

=head2 put

Keeps nothing; returns 0.

=head2 lookup

Returns undef: nothing is shared.

=head2 invalidate

Returns 0, defined: there was nothing to purge, and the purge is done.

=head2 invalidate_tag

As L</invalidate>, for a tag.

=head2 purge_expired

Returns 0: nothing expires in a layer that holds nothing.

=head2 clear

Returns 0.

=head2 snapshot

Returns C<< { kind => 'none' } >>.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>.

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
