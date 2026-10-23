# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- Mojolicious command name
package GPForum::CLI::gemini;
## use critic

use Mojo::Base 'Mojolicious::Command', -signatures;
use v5.40;
use Const::Fast;
use Carp         qw(croak);
use Getopt::Long qw(GetOptionsFromArray);
use Mojo::IOLoop;
use Mojo::URL;
use GPForum::Service::Discovery::Gemini;
use GPForum::Command::Usage;

our $VERSION = '0.001';

const my $DEFAULT_PORT      => 1965;
const my $IDLE_TIMEOUT      => 10;
const my $MAX_CONNECTIONS   => 100;
const my $MAX_PORT          => 65_535;
const my $MAX_REQUEST_BYTES => 1026;
const my $READ_RATE         => 60;
has description => 'Serve public categories and threads over Gemini with TLS';
has usage =>
"Usage: gpforum gemini --cert FILE --key FILE [--listen ADDRESS] [--port 1965] [--hostname HOST]\n";

sub run ( $self, @arguments ) {
    return GPForum::Command::Usage->help( \*STDOUT, $self->usage )
      if GPForum::Command::Usage->wants_help(@arguments);
    my %options = ( listen => '127.0.0.1', port => $DEFAULT_PORT );
    return GPForum::Command::Usage->front_door(2)
      if !GetOptionsFromArray(
        \@arguments, \%options, 'cert=s', 'key=s',
        'listen=s',  'port=i',  'hostname=s'
      )
      || @arguments
      || !-f ( $options{cert} // q{} )
      || !-f ( $options{key}  // q{} )
      || $options{port} < 1
      || $options{port} > $MAX_PORT;
    my $controller = $self->app->build_controller;
    my $reader     = GPForum::Service::Discovery::Gemini->new(
        hostname => $options{hostname}
          // Mojo::URL->new( $controller->gp_config->public_base_url )->host,
        port                 => $options{port},
        category_reader      => $controller->gp_category_reader,
        thread_reader        => $controller->gp_thread_reader,
        thread_detail_reader => $controller->gp_thread_detail_reader
    );
    _listen( $controller, $reader, \%options );
    if ( !Mojo::IOLoop->is_running ) { Mojo::IOLoop->start; }
    return;
}

sub _listen ( $controller, $reader, $options ) {
    Mojo::IOLoop->singleton->max_connections($MAX_CONNECTIONS);
    Mojo::IOLoop->server(
        {
            address     => $options->{listen},
            port        => $options->{port},
            tls         => 1,
            tls_cert    => $options->{cert},
            tls_key     => $options->{key},
            tls_options =>
              { SSL_version => 'SSLv23:!TLSv1:!TLSv1_1:!SSLv3:!SSLv2' }
        },
        sub ( $loop, $stream, $id ) {
            $stream->timeout($IDLE_TIMEOUT);
            my $buffer = q{};
            my $done   = 0;
            $stream->on(
                read => sub ( $connection, $bytes ) {
                    return if $done;
                    $buffer .= $bytes;
                    return
                      if length($buffer) <= $MAX_REQUEST_BYTES
                      && $buffer !~ /\n/msx;
                    $done = 1;
                    my $rate = $controller->gp_rate_limiter->check(
                        {
                            scope          => 'gemini',
                            action         => 'read',
                            actor_id       => $connection->handle->peerhost,
                            limit          => $READ_RATE,
                            window_seconds => $READ_RATE
                        }
                    );
                    my $response =
                        $rate->{ok}
                      ? $reader->response($buffer)
                      : "44 Slow down\r\n";
                    $connection->write(
                        $response => sub ($finished) { $finished->close; } );
                }
            );
        }
    ) or croak 'cannot start Gemini TLS listener';
    return;
}

1;

__END__

=head1 NAME

GPForum::CLI::gemini - Serve public GPForum content on Gemini.

=head1 SYNOPSIS

    gpforum gemini --cert /etc/gpforum/gemini.crt --key /etc/gpforum/gemini.key

=head1 DESCRIPTION

Runs a separate TLS 1.2 or newer listener, by default on loopback port 1965.
Use --listen 0.0.0.0 to expose it, --hostname for the published Gemini host,
and --port to change the port. A real certificate and matching private key
are required; self-signed certificates are supported. Connections time out
after ten idle seconds, URLs are limited to 1024 bytes and requests are
rate limited. Run under a service supervisor alongside the HTTP service.

=head1 VERSION

Version 0.001.

=head1 SUBROUTINES/METHODS

=head2 run

Parses the command arguments, runs the operation and reports its exit status.

=head1 DIAGNOSTICS

Invalid arguments exit with status 2. Operational failures are reported on standard error.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the same GPForum environment file and application services as the HTTP process.

=head1 DEPENDENCIES

Mojolicious and the GPForum services named in this module.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

See the operation description and docs/ops/community-protocols.md.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
