# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::OS::Process;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my $DEFAULT_NICE_DELTA => 0;
const my %PROCESS_CLASSES => (
    web_worker         => 0,
    projection_worker  => 5,
    mail_worker        => 8,
    search_worker      => 5,
    maintenance_worker => 10,
);

sub snapshot ($self) {
    my %classes;
    for my $class ( sort keys %PROCESS_CLASSES ) {
        $classes{$class} = $self->priority_plan($class);
    }

    return {
        classes => \%classes,
        policy  => 'declared-for-the-supervisor',
    };
}

# A plan, never applied here: nothing in GPForum calls setpriority. The
# supervisor sets the nice value (the shipped scheduled-jobs units set 10).
# GPFORUM_OS_WORKER_PRIORITY, which only relabelled this plan in the report,
# is gone.
sub priority_plan ( $self, $class ) {
    my $known = exists $PROCESS_CLASSES{$class} ? 1 : 0;

    return {
        class      => $class,
        known      => $known,
        nice_delta => $known ? $PROCESS_CLASSES{$class} : $DEFAULT_NICE_DELTA,
    };
}

1;
