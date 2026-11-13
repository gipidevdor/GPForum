# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::FailReadiness;

use Mojo::Base -base;
use v5.40;

our $VERSION = '0.001';

# As Service::Operations::Readiness: the report, here always a fresh one.
sub recent_check {
    my ($self) = @_;

    return $self->check;
}

sub check {
    return {
        status      => 'fail',
        checks      => [ { name => 'database', status => 'fail' } ],
        environment => 'test',
        runtime     => {},
        timestamp   => '2026-05-23T12:00:00Z',
    };
}

1;
