# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Mojo::DOM;
use Test::More;

use lib 'lib';

use GPForum::Service::Notification::DigestMessage;
use GPForum::Service::Notification::Renderer;

our $VERSION = '0.001';

# ADR 0078: the digest's HTML part styles itself inline, and a style that
# quotes a font name ("Segoe UI") is escaped inside its attribute, so the
# attribute holds the whole declaration and nothing leaks out of it.
my $html = GPForum::Service::Notification::DigestMessage->new(
    i18n => GPForum::Service::Notification::Renderer->new->i18n )->compose(
    {
        locale    => 'en',
        frequency => 'daily',
        items     => [
            {
                thread_id      => '00000000-0000-4000-8000-000000000001',
                title          => 'Release notes',
                category_title => 'News',
                new_posts      => 2,
            }
        ],
        thread_total    => 1,
        base_url        => 'https://forum.example',
        unsubscribe_url => 'https://forum.example/unsubscribe/token',
    }
  )->{html};
my $body = Mojo::DOM->new($html)->at('body');

ok(
    index( $body->attr('style'),
        'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,' ) >=
      0,
    'the quoted font name stays inside the style attribute'
);
like(
    $body->attr('style'),
    qr/background:\#ffffff \z/msx,
    'and the declaration reaches its end'
);
is_deeply( [ grep { $_ ne 'style' } sort keys %{ $body->attr } ],
    [], 'with no stray attributes after it' );
unlike( $html, qr/"Segoe/msx, 'the quote is written as an entity' );

done_testing;

1;
