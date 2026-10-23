# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::SitemapFunctions;
use Mojo::Base -base, -signatures;
use v5.40;
our $VERSION = '0.001';

sub rows ( $self, $name, $values ) {
    return [ { total => 1 } ] if $name eq 'forum_sitemap_count';
    return [
        {
            kind        => 'thread',
            resource_id => 'thread-1',
            slug        => 'welcome',
            changed_at  => '2026-05-23T12:00:00Z'
        }
    ];
}
1;
