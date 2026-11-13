# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::MissedPrivacyLooks;

use v5.40;

use Exporter qw(import);
use Mojo::Promise;

use GPForum::Service::Privacy::Deletion::Core;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';

our @EXPORT_OK = qw(with_missed_privacy_looks);

# Runs the code with the deletion steps' next looks in the named sources
# finding nothing: what a writer sees when it looks just before a concurrent
# writer commits the same row. Only the look is scripted. The insert that
# follows, the unique violation PostgreSQL raises and the savepoint that
# recovers from it are the database's own.
sub with_missed_privacy_looks ( $misses, $code ) {
    my %due  = %{$misses};
    my $look = GPForum::Service::Privacy::Deletion::Core->can('latest_row_p');

    return with_replaced_subs(
        'GPForum::Service::Privacy::Deletion::Core',
        {
            latest_row_p => sub ( $steps, $db, $context, $source, @query ) {
                if ( ( $due{$source} // 0 ) > 0 ) {
                    $due{$source}--;
                    return Mojo::Promise->resolve(undef);
                }
                return $look->( $steps, $db, $context, $source, @query );
            },
        },
        $code
    );
}

1;

__END__

=head1 NAME

GPForum::Test::MissedPrivacyLooks - Run code while the deletion steps' looks lose a race.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    use GPForum::Test::MissedPrivacyLooks qw(with_missed_privacy_looks);

    my $approved = with_missed_privacy_looks( { ErasureJob => 1 },
        sub { return $deletion->approve_request( $id, $staff, 'verified' ) } );

=head1 DESCRIPTION

The deletion steps of L<GPForum::Service::Privacy::DeletionWorkflow> look
for a row (C<latest_row_p>) before they insert one, and again after a
unique conflict. A test that races them makes the next looks in the named
sources (C<ErasureJob>, C<DeletionRequest>, C<DeletionAction>) find
nothing, and the insert then meets the row PostgreSQL holds. The steps
look through their functions, not through resultsets (ADR 0177).

=head1 SUBROUTINES/METHODS

=head2 with_missed_privacy_looks

Given a hash of source names to the number of looks to miss in each and a
code reference, runs the code with those looks missed and returns what it
returns. An exception the code raises passes through.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Test::ReplacedSubs>, L<Mojo::Promise>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
