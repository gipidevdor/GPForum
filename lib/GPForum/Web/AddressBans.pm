# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::AddressBans;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Web::Guard;
use GPForum::Web::SecurityEvent;

our $VERSION = '0.001';

const my $HTTP_FORBIDDEN => 403;

# ADR 0146: what each scope refuses. A registration ban refuses creating an
# account; a sign-in ban that and every way into one; a writes ban every
# request that is not a read.
const my %SAFE_METHOD  => map { $_ => 1 } qw(GET HEAD OPTIONS);
const my %REGISTRATION => ( register_submit => 1 );
const my %SIGN_IN => map { $_ => 1 } qw(
  register_submit
  login_submit
  login_second_factor_submit
  password_reset_request_submit
  password_reset_complete
);

# What no ban refuses: signing out, the language and the theme of the page
# that says so, a mail's one-click unsubscribe (RFC 8058), a member's
# privacy rights (ADR 0074), and the console's own ban forms, so that staff
# a ban covers can still lift it.
const my %ALWAYS_OPEN => map { $_ => 1 } qw(
  logout
  locale_update
  theme_update
  unsubscribe_confirm
  privacy_export_request
  privacy_deletion_request
  admin_address_ban_create
  admin_address_ban_update
  admin_address_ban_lift
);

# True when the request may go on; false once the refusal is rendered. A
# read never asks; a write asks which live ban covers its client, the
# address Web::ClientAddress found for it. When the
# lookup fails the request goes on, logged: a database that cannot answer it
# cannot take the write either.
sub admits ( $self, $controller, $client ) {
    return 1 if exists $SAFE_METHOD{ $controller->req->method };
    my $route = $controller->current_route // q{};
    return 1 if exists $ALWAYS_OPEN{$route};

    my $ban;
    try {
        $ban = $controller->gp_address_bans->covering($client);
    }
    catch ($error) {
        $controller->app->log->warn("address ban lookup failed: $error");
        return 1;
    };
    return 1 if !$ban || !$self->refuses( $ban->{scope}, $route );

    GPForum::Web::SecurityEvent->new->record_event( $controller,
        'address_ban_refusal',
        { scope => $ban->{scope}, status => $HTTP_FORBIDDEN } );
    GPForum::Web::Guard->new->address_banned($controller);

    return 0;
}

# Whether a ban of this scope refuses the write request on this route.
sub refuses ( $self, $scope, $route ) {
    my $name = $route // q{};
    return 0 if !defined $scope || exists $ALWAYS_OPEN{$name};
    return 1 if $scope eq 'writes';
    return 1 if $scope eq 'sign_in' && exists $SIGN_IN{$name};

    return exists $REGISTRATION{$name} ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Web::AddressBans - The one place a banned address is refused.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Web::ClientAddress->register wraps every action:
    return $next->()
      if GPForum::Web::AddressBans->new->admits( $controller, $client );

=head1 DESCRIPTION

ADR 0146. Every write request -- any method but GET, HEAD and OPTIONS --
asks L<GPForum::Service::Admin::AddressBans/covering> which live ban covers
the client L<GPForum::Web::ClientAddress> found for it, and is refused with
a plain 403 when that ban's scope covers the route: a registration ban the
registration, a sign-in ban the registration and the sign-in, password reset
and second step, a writes ban every write. Signing out, the language and
theme, the one-click unsubscribe, the privacy requests and the console's ban
forms are never refused. A refusal is counted as the security event
C<address_ban_refusal>.

=head1 SUBROUTINES/METHODS

=head2 admits

Takes the controller and its client address. True when the request may go on; false once the
refusal has been rendered.

=head2 refuses

Takes a scope and a route name. True when a ban of that scope refuses a
write on that route.

=head1 DIAGNOSTICS

A failed lookup is logged as a warning and the request goes on.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Web::Guard>, L<GPForum::Web::SecurityEvent>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Each write costs one indexed lookup; reads cost nothing.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
