# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::Forks;
use v5.40;
use Const::Fast;
use Exporter   qw(import);
use List::Util qw(any);
use GPForum::Infrastructure::AsyncWork;

our $VERSION   = '0.001';
our @EXPORT_OK = qw(children_during);

const my $CALLER_DEPTH => 30;
const my $SUBROUTINE   => 3;
const my @PLUMBING => (
    qr/\AGPForum::Test::Forks/msx, qr/\AGPForum::Infrastructure::Async/msx,
    qr/\AMojo/msx,                 qr/\AFuture/msx,
    qr/\A[(]eval[)]/msx,
);

# Runs $code and answers which children AsyncWork started meanwhile:
# { cpu => N, other => [ caller, ... ] }. cpu counts the CPU lane (cpu_p),
# whose child cannot open PostgreSQL; other names the caller of every child
# started any other way, which a request path must never do.
sub children_during ($code) {
    my %seen = ( cpu => 0, other => [] );
    my $run  = GPForum::Infrastructure::AsyncWork->can('run_p');
    {
        no warnings 'redefine';    ## no critic (TestingAndDebugging::ProhibitNoWarnings) -- observe run_p for the duration of $code only
        local *GPForum::Infrastructure::AsyncWork::run_p = sub (@arguments) {
            if ($GPForum::Infrastructure::AsyncWork::CPU_LANE) {
                $seen{cpu}++;
            }
            else {
                push @{ $seen{other} }, _caller();
            }
            return $run->(@arguments);
        };
        $code->();
    }
    return \%seen;
}

sub _caller {
    for my $level ( 1 .. $CALLER_DEPTH ) {
        my $name = ( caller $level )[$SUBROUTINE] // last;
        next if any { $name =~ $_ } @PLUMBING;
        return $name;
    }
    return 'unknown';
}

1;

__END__

=head1 NAME

GPForum::Test::Forks - Observe the children AsyncWork starts while a test runs.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    use GPForum::Test::Forks qw(children_during);
    my $children = children_during( sub { ... } );
    is_deeply( $children->{other}, [], 'no database child' );

=head1 DESCRIPTION

Wraps L<GPForum::Infrastructure::AsyncWork/run_p> while a callback runs and
sorts every child it starts: the CPU lane (C<cpu_p>), whose child cannot
open PostgreSQL, is counted; any other child is named by its caller.

=head1 SUBROUTINES/METHODS

=head2 children_during

Takes a callback, runs it, and answers C<< { cpu => N, other => [...] } >>.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::AsyncWork>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

For tests only. A child started after the callback returns is not seen.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
