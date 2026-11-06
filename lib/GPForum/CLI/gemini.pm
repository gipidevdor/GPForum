# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- Mojolicious command name
package GPForum::CLI::gemini;
## use critic

use Mojo::Base 'Mojolicious::Command', -signatures;
use v5.40;
use Const::Fast;
use Carp       qw(croak);
use Mojo::File qw(path);
use Mojo::IOLoop;
use Mojo::URL;
use GPForum::CLI::FrontDoor::Launcher;
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
    my $options = $self->_options(@arguments);
    return GPForum::Command::Usage->front_door($options) if !ref $options;

    my $controller = $self->app->build_controller;
    my $reader     = GPForum::Service::Discovery::Gemini->new(
        hostname => $options->{hostname}
          // Mojo::URL->new( $controller->gp_config->public_base_url )->host,
        port                 => $options->{port},
        category_reader      => $controller->gp_category_reader,
        thread_reader        => $controller->gp_thread_reader,
        thread_detail_reader => $controller->gp_thread_detail_reader
    );
    _listen( $controller, $reader, $options );
    if ( !Mojo::IOLoop->is_running ) { Mojo::IOLoop->start; }
    return;
}

# The options, read as every gpforum verb reads them, misuse said with the
# usage: --cert and --key are required and name files, read from where the
# command was typed when relative (the front door moves the run verbs to
# the code directory); --port is one a socket can take.
sub _options ( $self, @arguments ) {
    my $usage       = $self->usage;
    my $usage_class = 'GPForum::Command::Usage';
    my $typed_in    = GPForum::CLI::FrontDoor::Launcher->typed_in;
    my $file        = sub ( $option, $value ) {
        my $given = $usage_class->option_given( $value, $usage, $option );
        my $named =
          path($given)->is_abs || !defined $typed_in
          ? $given
          : path( $typed_in, $given )->to_string;
        if ( !-f $named ) {
            $usage_class->misuse( 'cli.misuse.no_file',
                { option => $option, value => $given }, $usage );
        }

        return $named;
    };

    return $usage_class->read_arguments(
        $usage,
        sub {
            my $options = $usage_class->parse_options(
                \@arguments,
                { listen => '127.0.0.1', port => $DEFAULT_PORT },
                {
                    numbers => { '--port' => [ 'port', 'positive_integer' ] },
                    values  => {
                        '--cert' => sub ( $options, $value ) {
                            $options->{cert} = $file->( '--cert', $value );
                        },
                        '--key' => sub ( $options, $value ) {
                            $options->{key} = $file->( '--key', $value );
                        },
                        '--listen' => sub ( $options, $value ) {
                            $options->{listen} =
                              $usage_class->option_given( $value, $usage,
                                '--listen' );
                        },
                        '--hostname' => sub ( $options, $value ) {
                            $options->{hostname} =
                              $usage_class->option_given( $value, $usage,
                                '--hostname' );
                        },
                    },
                    usage => $usage,
                }
            );
            for my $required (qw(--cert --key)) {
                next if defined $options->{ substr $required, 2 };
                $usage_class->misuse( 'cli.misuse.required',
                    { option => $required }, $usage );
            }
            if ( $options->{port} > $MAX_PORT ) {
                $usage_class->misuse( 'cli.misuse.value',
                    { option => '--port', value => $options->{port} }, $usage );
            }

            return $options;
        }
    );
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

Uses the same Good Phorum environment file and application services as the HTTP process.

=head1 DEPENDENCIES

Mojolicious and the Good Phorum services named in this module.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

See the operation description and docs/ops/community-protocols.md.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause license.

=cut
