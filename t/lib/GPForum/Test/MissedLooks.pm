# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::MissedLooks;

use v5.40;

use Exporter qw(import);
use Mojo::Promise;

use GPForum::Service::Attachment::Store;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';

our @EXPORT_OK = qw(with_missed_looks);

# Runs the code with the attachment store's next looks in the named tables
# finding nothing: what a writer sees when it looks just before a concurrent
# writer commits the same row. Only the look is scripted. The insert that
# follows, the unique violation PostgreSQL raises and the savepoint that
# recovers from it are the database's own.
sub with_missed_looks ( $misses, $code ) {
    my %due  = %{$misses};
    my $look = GPForum::Service::Attachment::Store->can('_single_row_p');

    return with_replaced_subs(
        'GPForum::Service::Attachment::Store',
        {
            _single_row_p => sub ( $store, $source, @arguments ) {
                if ( ( $due{$source} // 0 ) > 0 ) {
                    $due{$source}--;
                    return Mojo::Promise->resolve(undef);
                }
                return $look->( $store, $source, @arguments );
            },
        },
        $code
    );
}

1;

__END__

=head1 NAME

GPForum::Test::MissedLooks - Run code while the attachment store's looks lose a race.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    use GPForum::Test::MissedLooks qw(with_missed_looks);

    my $link = with_missed_looks( { AttachmentLink => 1 },
        sub { return $store->link_attachment($target); } );

=head1 DESCRIPTION

The attachment store looks for a row before it inserts one, and again after
a unique conflict. A test that races it makes the next looks in the named
tables (C<Attachment>, C<AttachmentLink>, C<AttachmentVariant>) find
nothing, and the insert then meets the row PostgreSQL holds.

=head1 SUBROUTINES/METHODS

=head2 with_missed_looks

Given a hash of table names to the number of looks to miss in each and a
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
