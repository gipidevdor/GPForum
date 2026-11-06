# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Navigation;
use Mojo::Base 'GPForum::Controller::Base', -async_await;
use v5.40;
use GPForum::Web::Navigation;
our $VERSION = '0.001';

async sub show ($self) {
    my $actor   = $self->current_user_id;
    my $context = { available => 1, permissions => {} };
    if ( defined $actor && length $actor ) {
        try {
            $context = (
                await $self->call_p(
                    $self->gp_permission_gate, 'navigation_context', $actor
                )
            );
        }
        catch ($error) {
            $self->app->log->warn("navigation permissions unavailable: $error");
            $context = { available => 0, permissions => {} };
        };
    }
    $self->res->headers->cache_control('private, no-store');
    return $self->render(
        template => 'navigation',
        groups   => GPForum::Web::Navigation->new->groups(
            { %{$context}, member => defined $actor && length $actor ? 1 : 0 }
        ),
        navigation_available => $context->{available},
    );
}
1;

__END__

=head1 NAME

GPForum::Controller::Navigation - The visible menu page, linked from every forum header.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # See the description and methods below.

=head1 DESCRIPTION

The visible menu page, linked from every forum header.

=head1 SUBROUTINES/METHODS

=head2 show

Renders grouped links with one bounded permission read for a signed-in menu
visit and none for a guest. Responses are private and cannot be stored in a
shared cache. Lookup failures retain ordinary destinations and show a notice.

=head1 DIAGNOSTICS

Permission failures omit staff destinations; target controllers retain their authorization.

=head1 CONFIGURATION AND ENVIRONMENT

Uses request-owned navigation context. No permission cache crosses requests.

=head1 DEPENDENCIES

L<GPForum::Web::Navigation>, L<GPForum::Service::Admin::PermissionGate>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Contextual actions remain on their resource pages.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
