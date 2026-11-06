# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::ReadyHealth;

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
        status      => 'ok',
        check       => 'ready',
        runtime     => { web_processes => 2 },
        checks      => [ { name => 'database', status => 'ok' } ],
        environment => 'test',
        timestamp   => '2026-05-23T12:00:00Z',
    };
}

1;
