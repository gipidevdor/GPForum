# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Command::Support::Verbs;

use Const::Fast;
use List::Util qw(first);
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# What an operator types after `gpforum`, by what they are doing: setting a
# forum up, running it, checking it, maintaining it, and the rest -- the
# benchmarks, seeds, drills and evidence a release needs and an operator
# rarely does. Each verb names the command that does the work (a
# GPForum::CLI adapter) and what it needs besides the settings:
# "application" for one that runs the web application, "nothing" for one
# that reads no setting either -- the front door does not read the settings
# file for it, so it runs where that file cannot be read: a CI runner, an
# account that is not the service's. The front door's help is drawn from
# this table.
const my @VERBS => (
    [qw(setup setup setup)],
    [qw(migrate setup migrate)],
    [qw(api-role setup api_role)],
    [qw(postgres-performance check postgres_performance)],
    [qw(admin setup admin)],
    [qw(secret setup secret)],
    [qw(start run start application)],
    [qw(outbox run outbox_dispatch application)],
    [qw(scheduled-jobs run scheduled_jobs application)],
    [qw(service setup service)],
    [qw(doctor check doctor)],
    [qw(status check status)],
    [qw(mail-check check mail_check)],
    [qw(antivirus-check check antivirus_check)],
    [qw(platform-check check platform_check)],
    [qw(os-preflight check os_preflight)],
    [qw(search-rebuild maintain search_rebuild)],
    [qw(dead-letters maintain dead_letter_replay)],
    [qw(partitions maintain partition_maintenance)],
    [qw(budgets maintain query_budget)],
    [qw(backup maintain backup)],
    [qw(restore maintain restore)],
    [qw(upgrade maintain upgrade)],
    [qw(benchmark more benchmark)],
    [qw(hypnotoad-benchmark more hypnotoad_benchmark)],
    [qw(hypnotoad-scaling more hypnotoad_scaling)],
    [qw(performance-seed more performance_seed)],
    [qw(stress-load more stress_load)],
    [qw(query-plan-evidence more query_plan_evidence)],
    [qw(staging-drill more staging_drill)],
    [qw(staging-drill-attachments more staging_drill_attachments nothing)],
    [qw(staging-host-verify more staging_host_verify)],
    [qw(evidence-meta more evidence_meta nothing)],
    [qw(evidence-validate more evidence_validate nothing)],
    [qw(dead-letter-check more dead_letter_check nothing)],
    [qw(mail-lifecycle-check more mail_lifecycle_check nothing)],
);

# The groups, in the order the help shows them. "more" is shown by
# `gpforum help --all` only.
const my @GROUPS => qw(setup run check maintain more);

sub groups ($class) {
    return [@GROUPS];
}

# Every verb, in the help's order, as { verb, group, command, needs }: the
# verb typed, its group, the GPForum::CLI command that does the work, and
# what it needs besides the settings -- "application" for one that runs the
# web application, "nothing" for one that reads no setting.
sub verbs ($class) {
    return [ map { _verb($_) } @VERBS ];
}

sub find ( $class, $verb ) {
    return first { $_->{verb} eq $verb } @{ $class->verbs };
}

sub _verb ($row) {
    my ( $verb, $group, $command, $needs ) = @{$row};

    return {
        command => $command,
        group   => $group,
        needs   => $needs,
        verb    => $verb,
    };
}

1;

__END__

=head1 NAME

GPForum::Command::Support::Verbs - What an operator types after C<gpforum>.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $verb = GPForum::Command::Support::Verbs->find('partitions');
    # { verb => 'partitions', group => 'maintain',
    #   command => 'partition_maintenance', needs => undef }

=head1 DESCRIPTION

The front door's verbs, grouped as its help shows them -- set up, run,
check, maintain, and more -- each with the C<GPForum::CLI> command that does
the work and what it needs besides the settings: C<application> for a verb
that runs the web application, C<nothing> for one that reads no setting, for
which the front door reads no settings file.

=head1 SUBROUTINES/METHODS

=head2 groups

Class method. The group names in the help's order.

=head2 verbs

Class method. Every verb, in the help's order, as a hash reference with
C<verb>, C<group>, C<command> and C<needs>.

=head2 find

Class method. The verb typed, or undef.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Const::Fast>, L<List::Util>, L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A verb whose command is not installed (C<doctor> before it lands) is in the
table all the same; the front door shows only the ones it can load.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
