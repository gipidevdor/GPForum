# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Example::Passkeys::App;

use Mojo::Base 'Mojolicious', -signatures;
use v5.40;
use Const::Fast;
use Crypt::URandom qw(urandom);
use MIME::Base64   qw(encode_base64url);
use Mojo::Exception;
use Mojo::URL;
use GPForum::Example::Passkeys::Challenges;
use GPForum::Example::Passkeys::Controller;
use GPForum::Example::Passkeys::Registration;

our $VERSION = '0.001';
const my $RANDOM_BYTES      => 32;
const my $MAX_REQUEST_BYTES => 65_536;
const my $SESSION_SECONDS   => 1_800;

has challenges   => sub { return GPForum::Example::Passkeys::Challenges->new; };
has registration => undef;    # initialized once by startup

sub startup ($self) {
    my $origin = $ENV{GPFORUM_PASSKEY_DEMO_ORIGIN} // 'http://localhost:3000';
    my $url    = _origin($origin);
    if ( defined $ENV{GPFORUM_PASSKEY_DEMO_SECRET}
        && length( $ENV{GPFORUM_PASSKEY_DEMO_SECRET} ) < $RANDOM_BYTES )
    {
        Mojo::Exception->throw(
            'The configured demo secret must contain at least 32 characters');
    }
    $self->registration(
        GPForum::Example::Passkeys::Registration->new(
            rp_id  => $url->host,
            origin => $origin
        )
    );
    $self->secrets(
        [
            $ENV{GPFORUM_PASSKEY_DEMO_SECRET}
              // encode_base64url( urandom($RANDOM_BYTES) )
        ]
    );
    $self->sessions->cookie_name('good_phorum_passkey_demo');
    $self->sessions->default_expiration($SESSION_SECONDS);
    $self->sessions->samesite('Strict');
    $self->sessions->secure( $url->scheme eq 'https' ? 1 : 0 );
    $self->max_request_size($MAX_REQUEST_BYTES);
    my $home = $self->home;
    $self->renderer->paths( [ $home->child('templates')->to_string ] );
    $self->static->paths( [ $home->child('public')->to_string ] );
    $self->types->type( mjs => 'application/javascript' );
    $self->hook(
        before_server_start => sub ( $server, $app ) {
            if ( $server->isa('Mojo::Server::Prefork') ) {
                Mojo::Exception->throw(
                    'This demo requires the single-process daemon');
            }
            return;
        }
    );
    my $routes = $self->routes;
    $routes->namespaces( ['GPForum::Example::Passkeys'] );
    $routes->get(q{/})->to(
        cb => sub ($c) {
            $c->session->{demo_account} //= {
                id           => encode_base64url( urandom($RANDOM_BYTES) ),
                name         => 'demo',
                display_name => 'Account dimostrativo effimero',
            };
            $c->res->headers->cache_control('private, no-store');
            return $c->render( template => 'index' );
        }
    );
    $routes->post('/api/passkey/register/challenge')->to(
        controller => 'controller',
        action     => 'challenge'
    );
    $routes->post('/api/passkey/register/verify')->to(
        controller => 'controller',
        action     => 'verify'
    );
    return;
}

sub _origin ($raw) {
    my $url  = Mojo::URL->new($raw);
    my $path = $url->path;
    if (   !$url->host
        || defined $url->userinfo
        || defined $url->fragment
        || length( $url->query->to_string )
        || length( $path->to_string ) )
    {
        Mojo::Exception->throw(
            'Set an exact origin without path, query or credentials');
    }
    if ( $url->scheme ne 'https'
        && !( $url->scheme eq 'http' && $url->host eq 'localhost' ) )
    {
        Mojo::Exception->throw('HTTPS is required, except http://localhost');
    }
    return $url;
}

1;

__END__

=head1 NAME

GPForum::Example::Passkeys::App - Isolated registration example, not GPForum login.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Example::Passkeys::App->new(home => $home)->start;

=head1 DESCRIPTION

Run app.pl with the single-process daemon. The first page creates an ephemeral
demo identity, not an authenticated forum account. No production routes, schema
or authentication policy are changed. See docs/passkeys-registration.md.

=head1 SUBROUTINES/METHODS

=head2 startup

Installs fixed-origin JSON POST routes, bounded input, signed sessions and the
standalone page. Secrets rotate at restart unless explicitly configured.

=head1 DIAGNOSTICS

Invalid origin configuration and prefork startup raise Mojo::Exception.

=head1 CONFIGURATION AND ENVIRONMENT

GPFORUM_PASSKEY_DEMO_ORIGIN fixes the exact origin (default http://localhost:3000). GPFORUM_PASSKEY_DEMO_SECRET optionally supplies a secret of at least 32 characters.

=head1 DEPENDENCIES

See the pinned dependencies in examples/passkeys/cpanfile.snapshot.

=head1 INCOMPATIBILITIES

The single-process daemon is required. This is not a production authentication application.

=head1 BUGS AND LIMITATIONS

No credential persistence or assertion/login ceremony is implemented.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
