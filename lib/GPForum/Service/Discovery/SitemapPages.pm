# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Discovery::SitemapPages;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;

use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

const my $PAGE_SIZE => 1000;
__PACKAGE__->requires(qw(schema builder));
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

sub sitemap_index ($self) {
    my $count =
      $self->functions->rows( 'forum_sitemap_count', {} )->[0]{total};
    my $pages   = ceil( $count / $PAGE_SIZE ) || 1;
    my $base    = $self->builder->canonical_url->base_url;
    my @entries = map { { loc => "$base/sitemap-$_.xml" } } 1 .. $pages;
    return $self->builder->render_index( \@entries );
}

sub page ( $self, $page ) {
    my $rows =
      $self->functions->rows( 'forum_sitemap_page', { page => $page } );
    my $canonical = $self->builder->canonical_url;
    my @entries   = $page == 1 ? @{ $self->builder->legal_entries } : ();
    for my $row ( @{$rows} ) {
        my $url =
          $row->{kind} eq 'thread'
          ? $canonical->thread_url(
            { thread_id => $row->{resource_id}, slug => $row->{slug} } )
          : $canonical->category_url($row);
        push @entries, { loc => $url, lastmod => $row->{changed_at} };
    }
    return $self->builder->render_xml( \@entries );
}

1;

__END__

=head1 NAME

GPForum::Service::Discovery::SitemapPages - Public sitemap index and pages.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Discovery::SitemapPages->new(...);

=head1 DESCRIPTION

Public sitemap index and pages. See ADR 0155.

=head1 SUBROUTINES/METHODS

=head2 sitemap_index

Returns the sitemap index, naming every numbered 1000-resource page.

=head2 page

Takes a positive page number and returns its public resource URL set. Page one also carries legal pages.

=head1 DIAGNOSTICS

Exceptions propagate to the command or worker, which reports the failure.

=head1 CONFIGURATION AND ENVIRONMENT

Receives configuration or collaborators through constructor arguments. See
ADR 0155 for the operator settings and commands.

=head1 DEPENDENCIES

Uses the modules listed in the source preamble and the locked cpanfile.

=head1 INCOMPATIBILITIES

Requires Perl 5.40 or newer.

=head1 BUGS AND LIMITATIONS

See ADR 0155 for the scope and operational limits.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
