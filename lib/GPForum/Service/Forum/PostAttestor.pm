# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::PostAttestor;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';
__PACKAGE__->requires(qw(schema signer));

sub run ($self) {
    my $functions =
      GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
    my ( $after, $saved, $skipped ) = ( undef, 0, 0 );
    while (1) {
        my $bodies = $functions->rows( 'forum_protocol_unsigned_bodies',
            { after => $after } );
        last if !@{$bodies};
        for my $body ( @{$bodies} ) {
            my $answer = $functions->row(
                'forum_protocol_attest_body',
                {
                    body_id  => $body->{body_id},
                    post_id  => $body->{post_id},
                    source   => $body->{body_source},
                    envelope => $self->signer->sign($body),
                }
            );
            $answer->{saved} ? $saved++ : $skipped++;
            $after = $body->{body_id};
        }
    }
    return { signed => $saved, skipped => $skipped };
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::PostAttestor - Attest previously unsigned post bodies in bounded batches.

=head1 DESCRIPTION

Signs existing revisions as they are at the time of this administrative
operation. It does not claim to prove their pre-attestation history and
never overwrites an existing signature. Each insertion compares the exact
source again, so an edit or erasure racing the operation is skipped.

=head1 SUBROUTINES/METHODS

=head2 run

Attests unsigned revisions in batches and returns signed and skipped counts.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $counts = $attestor->run;

=head1 DIAGNOSTICS

Storage or signing failures propagate; racing edits and deletions are counted as skipped.

=head1 CONFIGURATION AND ENVIRONMENT

Inject the migrated schema and persistent server signer.

=head1 DEPENDENCIES

SqlFunction and PostSigner.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Attests current stored history without proving its pre-attestation provenance.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
