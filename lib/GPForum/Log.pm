# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Log;

use Mojo::Base -strict, -signatures;
use v5.40;

use GPForum::X::Config;
use Digest::SHA qw(hmac_sha256_hex);
use English     qw(-no_match_vars);
use JSON::MaybeXS;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use Const::Fast;

our $VERSION = '0.001';

const my $MILLISECONDS   => 1_000;
const my $WARNING_LENGTH => 2_048;
const my $STACK_FRAMES   => 20;
my $JSON = JSON::MaybeXS->new( canonical => 1, utf8 => 0 );
my %ACTIVE;

sub configure ( $class, $app, $config ) {
    $app->log->level( $config->log_level );
    $app->log->format( \&_format );
    $class->_apply_destination( $app, $config );
    $app->hook(
        around_dispatch => sub ( $next, $controller ) {
            my $context = {
                gpforum_log_context => 1,
                started_at          => clock_gettime(CLOCK_MONOTONIC),
            };
            $controller->stash( gp_log_context => $context );
            $controller->stash->{'mojo.log'} = $app->log->context($context);
            ## no critic (Variables::ProhibitLocalVars) -- synchronous scope; async callbacks retain the controller's own logger
            local $ACTIVE{request} = $context;
            ## use critic
            if ( $config->is_production ) {
                local $SIG{__WARN__} = sub ($message) {
                    _warning( $controller->log, $message );
                };
                return $next->();
            }
            return $next->();
        }
    );
    $app->hook(
        around_action => sub ( $next, $controller, @arguments ) {
            $class->identify_request( $controller, $config );
            return $next->();
        }
    );
    $app->log->debug('GPForum logging configured');

    return;
}

sub identify_request ( $, $controller, $config ) {
    my $context = $controller->stash('gp_log_context');
    return if !$context;
    $context->{request_id} = $controller->stash('gp_request_id');
    my $user = $controller->session('user_id');
    $context->{user_hash} =
      defined $user
      ? hmac_sha256_hex( "gpforum-log:$user", $config->signing_secrets->[0] )
      : undef;

    return;
}

sub _format ( $timestamp, $level, @lines ) {
    my $context = $ACTIVE{request};
    my ( @messages, %fields );
    for my $line (@lines) {
        if ( ref $line eq 'HASH' && $line->{gpforum_log_context} ) {
            $context = $line;
        }
        elsif ( ref $line eq 'HASH' ) {
            %fields = ( %fields, %{$line} );
        }
        else {
            push @messages, "$line";
        }
    }
    return $JSON->encode(
        {
            %fields,
            timestamp   => $timestamp,
            level       => $level,
            pid         => $PROCESS_ID,
            message     => join( q{ }, @messages ),
            request_id  => $context ? $context->{request_id} : undef,
            user_hash   => $context ? $context->{user_hash}  : undef,
            duration_ms => $context
            ? ( clock_gettime(CLOCK_MONOTONIC) - $context->{started_at} ) *
              $MILLISECONDS
            : undef,
        }
    ) . "\n";
}

# Only locations, never the arguments of a call (tokens, passwords, bodies).
# The warning handler performs no SQL and cannot recursively audit itself.
sub _warning ( $logger, $message ) {
    return if $ACTIVE{warning};
    ## no critic (Variables::ProhibitLocalVars) -- recursion guard for this warning only
    local $ACTIVE{warning} = 1;
    ## use critic
    my @stack;
    for my $depth ( 1 .. $STACK_FRAMES ) {
        my ( $package, $file, $line, $subroutine ) = caller $depth;
        last if !defined $package;
        push @stack,
          { file => $file, line => $line, subroutine => $subroutine };
    }
    try {
        $logger->warn(
            {
                event   => 'perl.warning',
                warning => substr( $message, 0, $WARNING_LENGTH ),
                stack   => \@stack,
            }
        );
    }
    catch ($error) {
        local $SIG{__WARN__} = 'DEFAULT';
        warn $message;    ## no critic (ErrorHandling::RequireCarping) -- preserve the original warning location on logger failure
    };

    return;
}

# Mojolicious logs to STDERR by default, and Mojo::Server::daemonize reopens
# STDERR on /dev/null before Hypnotoad forks its workers. Setting only the level
# therefore meant every line of a daemonized deployment was discarded: no
# request log, no error, nothing to read during an incident.
#
# An explicit path takes the logger off STDERR so the destination survives
# daemonization. Leaving it empty keeps STDERR, which is correct when the
# process stays in the foreground and a supervisor captures it.
sub _apply_destination ( $, $app, $config ) {
    my $path = $config->log_path;
    if ( !defined $path || !length $path ) {
        return;
    }

    # Mojo::Log opens the file on first use and dies with its own words when
    # it cannot: open it now, so a bad path stops the start, not a request.
    $app->log->path($path);
    try {
        $app->log->handle;
    }
    catch ($error) {
        GPForum::X::Config->throw(
            message => "unable to open the configured log path: $path",
            cause   => $error,
        );
    };

    return;
}

1;

__END__

=head1 NAME

GPForum::Log - Logging bootstrap.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Log->configure($app, $config);

=head1 DESCRIPTION

Configures the Mojolicious logger for the current runtime environment.

=head1 SUBROUTINES/METHODS

=head2 configure

Applies the configured log level and destination, and writes one JSON object
per line. Request loggers carry C<request_id>, an HMAC C<user_hash> (or null
for a guest), and elapsed C<duration_ms>. Background entries carry nulls.
The controller logger retains its context for delayed callbacks; the app
logger inherits it only while dispatch runs synchronously.
Production dispatch captures Perl warnings as bounded C<perl.warning> log
events with stack locations, without call arguments or database writes.

=head2 identify_request

Refreshes the request id and pseudonymous actor from the request session.

=head2 _apply_destination

Points the logger at C<log_path> when one is configured. Without it the logger
stays on STDERR, which Hypnotoad reopens on F</dev/null> when it daemonizes.

=head1 DIAGNOSTICS

Throws L<GPForum::X::Config> when the configured C<log_path> cannot be
opened, with the opening error as its C<cause>.

=head1 CONFIGURATION AND ENVIRONMENT

Receives log level, destination, production mode and the signing secrets
used for user pseudonyms through L<GPForum::Config>.

=head1 DEPENDENCIES

Uses L<Mojo::Base>, L<GPForum::X::Config>, L<JSON::MaybeXS>,
L<Digest::SHA>, L<Time::HiRes> and L<Const::Fast>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Warning capture covers synchronous production dispatch. Worker jobs and
delayed callbacks keep their existing warning handlers. Operational warnings
are not moderation reports or tamper-evident database audit records.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
