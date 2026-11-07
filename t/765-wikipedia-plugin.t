# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use utf8;
use Test::More;
use Test::Fatal;
use Const::Fast;
use lib 'lib';
use GPForum::Service::Integration::Registry;
use GPForum::Service::Integration::Wikipedia;
use GPForum::Service::Plugin::Contract;

our $VERSION = '0.001';
const my $LABEL_LIMIT         => 256;
const my $HOST_LIMIT          => 1_024;
const my $TITLE_LIMIT         => 255;
const my $EXCESS_CAPABILITIES => 17;

my $registry =
  GPForum::Service::Integration::Registry->new( enabled => ['wikipedia'] );
my $article = $registry->resolve(
    'https://it.m.wikipedia.org/wiki/Alan_Turing?utm_source=test#Biografia');
is_deeply(
    $article,
    {
        api_version => 1,
        provider    => 'wikipedia',
        name        => 'Wikipedia',
        kind        => 'article',
        label       => 'Alan Turing (IT)',
        url         => 'https://it.wikipedia.org/wiki/Alan_Turing#Biografia',
    },
'mobile article becomes a canonical language-specific source with its section'
);
is( $registry->resolve('https://fr.wikipedia.org/wiki/Caf%C3%A9')->{label},
    'Café (FR)', 'UTF-8 page titles are decoded for readers' );
is(
    $registry->resolve('https://ja.wikipedia.org/wiki/%E6%9D%B1%E4%BA%AC')
      ->{label},
    '東京 (JA)',
    'non-Latin titles remain readable'
);
is(
    $registry->resolve('https://en.wikipedia.org/wiki/O%27Brien')->{url},
    'https://en.wikipedia.org/wiki/O%27Brien',
    'apostrophes stay safely encoded'
);
is( $registry->resolve('https://en.wikipedia.org/wiki/AC/DC')->{label},
    'AC/DC (EN)', 'slashes in a title are preserved' );
is(
    $registry->resolve('https://en.wikipedia.org/wiki/Star_Trek:_Voyager')
      ->{label},
    'Star Trek: Voyager (EN)',
    'colons in article names are supported'
);
is(
    $registry->resolve(
'https://en.wikipedia.org/w/index.php?title=Alan+Turing&action=view&utm_source=x'
    )->{url},
    'https://en.wikipedia.org/wiki/Alan_Turing',
    'reading query URLs lose tracking parameters'
);
is(
    $registry->resolve('https://it.wikipedia.org/w/index.php?title=Caff%C3%A8')
      ->{label},
    'Caffè (IT)',
    'query-form UTF-8 titles remain readable'
);
my $revision = $registry->resolve(
    'https://en.wikipedia.org/w/index.php?title=Wrong_title&oldid=12345#History'
);
is(
    $revision->{url},
    'https://en.wikipedia.org/w/index.php?oldid=12345#History',
    'permanent citations preserve the revision and section'
);
is( $revision->{label}, '#12345 (EN)',
    'a revision is never attributed to an unchecked title' );
is(
    $registry->resolve(
        'https://de.wikipedia.org/wiki/Albert_Einstein?oldid=987')->{url},
    'https://de.wikipedia.org/w/index.php?oldid=987',
    'oldid on a pretty URL remains a stable citation'
);
is(
    $registry->resolve('https://simple.wikipedia.org/wiki/Computer')
      ->{provider},
    'wikipedia', 'reviewed multi-letter language codes are accepted'
);
is(
    $registry->resolve('https://be-tarask.wikipedia.org/wiki/Test')->{provider},
    'wikipedia', 'reviewed hyphenated language codes are accepted'
);

for my $bad (
    'https://it.wikipedia.org.evil.test/wiki/Test',
    'https://evil.wikipedia.org/wiki/Test',
    'https://www.wikipedia.org/',
    'https://commons.wikimedia.org/wiki/Test',
    'https://en.wikipedia.org/w/api.php?action=query',
    'https://en.wikipedia.org/w/index.php?action=edit&title=Test',
    'https://en.wikipedia.org/wiki/Test?action=delete',
    'https://en.wikipedia.org/wiki/Test?diff=123',
    'https://en.wikipedia.org/wiki/Test?oldid=latest',
    'https://en.wikipedia.org/wiki/Test?oldid=0',
    'https://en.wikipedia.org/wiki/Test?oldid=1&oldid=2',
    'https://en.wikipedia.org/w/index.php',
    'https://en.wikipedia.org/wiki/',
    'https://en.wikipedia.org/wiki/Bad%FF',
    'https://en.wikipedia.org/wiki/Bad%00',
    'https://en.wikipedia.org/wiki/%3Cscript%3E',
    'https://en.wikipedia.org/wiki/%2E%2E/Test',
    'https://en.wikipedia.org/wiki/%252E%252E/Test',
    'https://en.wikipedia.org/wiki/Test%23Other',
    'https://en.wikipedia.org/w/index.php?title=%3Cscript%3E',
  )
{
    ok( !defined $registry->resolve($bad),
        'unsupported or unsafe target stays an ordinary link' );
}
my $long = $registry->resolve(
    'https://en.wikipedia.org/wiki/' . ( 'A' x $TITLE_LIMIT ) );
ok(
    length( $long->{label} ) <= $LABEL_LIMIT,
    'long titles fit the fixed API label bound'
);
is_deeply( $registry->frame_origins, [],
    'Wikipedia grants no frame or external connection permission' );
ok( !exists $article->{embed},
    'Wikipedia is a local link card without remote content' );
is_deeply(
    GPForum::Service::Integration::Registry->new( enabled => ['none'] )
      ->for_source('https://it.wikipedia.org/wiki/Alan_Turing'),
    [],
    'disabling Wikipedia removes generated cards'
);

my $api      = GPForum::Service::Plugin::Contract->new;
my $manifest = GPForum::Service::Integration::Wikipedia->new->manifest_v1;
ok( $api->manifest_v1($manifest),
    'the complete reviewed language list fits API v1' );
my @too_many = map { "edition$_.wikipedia.org" } 1 .. $HOST_LIMIT + 1;
ok(
    exception { $api->manifest_v1( { %{$manifest}, url_hosts => \@too_many } ) }
    ,
    'origin declarations remain bounded'
);
my @unknown_capabilities = map { "unknown$_" } 1 .. $EXCESS_CAPABILITIES;
ok(
    exception {
        $api->manifest_v1(
            { %{$manifest}, capabilities => \@unknown_capabilities } )
    },
    'the larger origin limit does not expand the capability limit'
);
is(
    $registry->for_source(
        '[Mercury](https://en.wikipedia.org/wiki/Mercury_(planet))')->[0]{url},
    'https://en.wikipedia.org/wiki/Mercury_(planet)',
    'standalone Markdown citations keep parentheses within Wikipedia titles'
);

done_testing();

1;
