# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Home;

use GPForum::Web::HomeAccess;
use GPForum::Web::RequestPreference;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use v5.40;

our $VERSION = '0.001';

sub show ($self) {
    my $access = GPForum::Web::HomeAccess->new;
    my $home;
    try {
        $home = $self->gp_home_page_reader->home_page(
            {
                %{ $access->query( $self->param('after') ) },
                viewer => $self->gp_forum_viewer,
            }
        );
        _attach_tags( $home->{latest_threads}{items},
            $self->gp_tags_for_threads( $home->{latest_threads}{items} ) );
    }
    catch ($error) {
        $self->app->log->error("home page read failed: $error");
        return $access->render_unavailable($self);
    };

    # The line under the forum's name is the operator's, not the page's data.
    $self->stash( site_description => $self->gp_config->site_description );

    # Diagnostics are part of the JSON contract, not the HTML template.
    # Keep them live when requested without probing the OS on every page.
    my $runtime =
      GPForum::Web::RequestPreference->wants_json($self)
      ? $self->gp_runtime->as_hash
      : undef;
    return $access->render_page( $self,
        $access->page_payload( $home, $runtime ) );
}

# The tags of each listed thread on its row (ADR 0135).
sub _attach_tags ( $threads, $tags ) {
    for my $thread ( @{ $threads || [] } ) {
        $thread->{tags} = $tags->{ $thread->{thread_id} // q{} } // [];
    }

    return;
}

1;

__END__

=head1 NAME

GPForum::Controller::Home - Home page controller.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get(q{/})->to('Home#show');

=head1 DESCRIPTION

Renders the Good Phorum public home index.

=head1 SUBROUTINES/METHODS

=head2 show

Renders a navigable SSR home page backed by forum reader services.

=head1 DIAGNOSTICS

Rendering errors are reported by Mojolicious. Reader failures stay logged on
this method and render C<home_unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

Uses Good Phorum runtime and forum home page reader helpers configured during
application startup.

=head1 DEPENDENCIES

Uses L<Mojolicious::Controller> and L<GPForum::Web::HomeAccess>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The home page exposes public categories and latest visible public threads. It
does not expose private or moderated content.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
