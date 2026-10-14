# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use English qw(-no_match_vars);
use Test::Exception;
use Test::More;

use lib 'lib';

use GPForum::Config;
use GPForum::Config::Report;
use GPForum::Service::Operations::Profile;

our $VERSION = '0.001';

# GPFORUM_ENV said two things: where a node runs and how big it is
# (production-small, production-medium). The size had to be chosen by hand,
# and choosing it sized nothing: the profile raised floors the defaults did
# not meet (audit 2.3, D1'). It says where a node runs now -- development,
# staging or production -- and the size comes from the host (t/611, ADR
# 0125). Nothing was released with the old names, so none is read.

const my %PRODUCTION => (
    GPFORUM_MAIL_FROM       => 'forum@forum.gpforum.net',
    GPFORUM_METRICS_TOKEN   => 'metrics-token',
    GPFORUM_PUBLIC_BASE_URL => 'https://forum.gpforum.net',
    GPFORUM_SESSION_SECRET  => '0123456789abcdef' x 3,
);

subtest 'three environments, and the refusal names only them' => sub {
    for my $environment (qw(development staging production)) {
        is(
            GPForum::Config->from_environment(
                { %PRODUCTION, GPFORUM_ENV => $environment }
            )->environment,
            $environment,
            "$environment is one"
        );
    }
    throws_ok {
        GPForum::Config->from_environment( { GPFORUM_ENV => 'large' } )
    }
    'GPForum::X::Config', 'a size is not an environment';
    is(
        GPForum::Config::Report->sentence( $EVAL_ERROR->problems->[0] ),
        'GPFORUM_ENV must be one of development, test, staging, production,'
          . q{ not 'large'.},
        'and the old names are not offered'
    );
    is_deeply(
        GPForum::Service::Operations::Profile->new->names,
        [qw(development production staging)],
        'one profile for each'
    );
};

subtest 'an old size is refused like any other word' => sub {
    for my $old (qw(production-small production-medium)) {
        throws_ok {
            GPForum::Config->from_environment(
                { %PRODUCTION, GPFORUM_ENV => $old } )
        }
        'GPForum::X::Config', "$old is not an environment";
        is( $EVAL_ERROR->problems->[0]{variable},
            'GPFORUM_ENV', 'GPFORUM_ENV is the problem' );
    }
};

done_testing();

1;
