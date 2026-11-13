# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::SitemapFunctions;
use Mojo::Base 'GPForum::Test::SettledCalls', -signatures;
use v5.40;
our $VERSION = '0.001';

# Two threads, one titled with an accented letter: its slug keeps it.
sub rows ( $self, $name, $values ) {
    return [ { total => 1 } ] if $name eq 'forum_sitemap_count';
    return [
        {
            kind        => 'thread',
            resource_id => 'thread-1',
            slug        => 'welcome',
            changed_at  => '2026-05-23T12:00:00Z'
        },
        {
            kind        => 'thread',
            resource_id => 'thread-2',
            slug        => "citt\N{LATIN SMALL LETTER A WITH GRAVE}",
            changed_at  => '2026-05-23T12:00:00Z'
        },
    ];
}
1;
