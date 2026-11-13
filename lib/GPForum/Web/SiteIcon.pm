# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::SiteIcon;

use Mojo::Base -strict, -signatures;
use v5.40;

use GPForum::Web::IconSet;

our $VERSION = '0.001';

# The approved orbit is also the browser icon. Its accessible title remains
# the installation's own name, without a second symbol family.
sub svg ( $, $name ) {
    return GPForum::Web::IconSet->document( 'orbit', $name // 'Forum' );
}

1;

__END__

=head1 NAME

GPForum::Web::SiteIcon - the approved orbit, labelled by the forum's name

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $svg = GPForum::Web::SiteIcon->svg('Circolo Fotografico');

=head1 DESCRIPTION

The icon a browser shows for the forum's pages: the approved orbit symbol,
with the installation's configured name as its accessible title.

=head1 SUBROUTINES/METHODS

=head2 svg

Takes a name. Returns a self-contained SVG document from the shared symbol
source, with that name escaped for XML in its title.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

C<GPFORUM_SITE_NAME> names the forum (L<GPForum::Config>).

=head1 DEPENDENCIES

L<Mojo::Base>, L<GPForum::Web::IconSet>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

BSD-3-Clause.

=cut
