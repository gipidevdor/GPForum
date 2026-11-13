# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Command::Setup::Report;

use Const::Fast;
use Mojo::Base 'GPForum::Command::Setup::Database', -signatures;
use v5.40;

use List::Util   qw(any first);
use Mojo::Loader qw(load_class);
use GPForum::Command::Support::ServiceEnvironment;
use GPForum::Command::Support::Verbs;
use GPForum::Command::Usage;
use GPForum::Service::Operations::DatabaseProvisioning;
use GPForum::Service::Operations::Host;
use GPForum::Service::Operations::PeerAuthentication;
use GPForum::Service::Operations::ServiceFiles;

our $VERSION = '0.001';

const my $COMMAND       => 'gpforum-setup';
const my $DATABASE_NAME => 'gpforum';

# The findings, then what to do next, or what was left to fix.
sub report ( $self, $options, $state, $findings, $changed ) {
    my $closing;
    if ( !$findings->exit_status && !%{$changed} ) {
        $closing = $self->said_text('setup.unchanged');
    }

    return $self->print_report( $options, $state, $findings, $changed,
        $closing );
}

sub print_report ( $self, $options, $state, $findings, $changed, $closing ) {
    my $failed = $findings->exit_status;
    if ( $options->{json} ) {
        GPForum::Command::Usage->json(
            $self->output,
            {
                command  => $COMMAND,
                status   => $failed             ? 'fail' : $findings->status,
                changed  => %{$changed}         ? 1      : 0,
                dry_run  => $options->{dry_run} ? 1      : 0,
                file     => $state->{file},
                findings => GPForum::Command::Support::ServiceEnvironment
                  ->findings_as_read(
                    $findings->document
                  ),
            }
        );
        return $failed;
    }

    my @lines = ( split /\n/msx, $findings->human_text( summary => 0 ) );
    if ($failed) {
        push @lines, q{}, $findings->summary;
    }
    elsif ( !$options->{dry_run} ) {
        push @lines, ( defined $closing ? ( q{}, $closing ) : () ), q{},
          $self->_peer_lines($state), $self->_next_steps($state);
    }
    else {
        push @lines, q{}, $closing;
    }
    $self->say_text( join "\n", @lines );

    return $failed;
}

# The PostgreSQL rules a deployed host needs to reach its local server
# over the socket by peer, which lets an account in only as its own role
# unless a map says otherwise (ADR 0137): the service's account as the
# owner and the runtime role, the operator as the owner. Undef for a
# database on another host or a development checkout.
sub peer ( $self, $state, $plan ) {
    return undef if !$state->{deployed};
    my $source =
      GPForum::Service::Operations::DatabaseProvisioning->data_source(
        $plan->{GPFORUM_DATABASE_DSN} );
    return undef if !defined $source;
    return undef if length $source->{host} && $source->{host} !~ m{\A /}msx;

    return GPForum::Service::Operations::PeerAuthentication->new(
        os       => $self->os,
        database => $source->{database} // $DATABASE_NAME,
        account  => $self->account->name,
        owner    => $plan->{GPFORUM_DATABASE_USER} // $DATABASE_NAME,
    );
}

# The lines of pg_hba.conf and pg_ident.conf, each file's under a sentence
# that says where they go, then the reload; and an empty line after them.
sub _peer_lines ( $self, $state ) {
    my $peer = $state->{peer};
    return () if !defined $peer;

    return (
        $self->said_text(
            'setup.peer',
            {
                account => $peer->account,
                owner   => $peer->owner,
                runtime => $peer->runtime,
            }
        ),
        ( map { "  $_" } @{ $peer->hba_lines } ),
        $self->said_text('setup.peer_ident'),
        ( map { "  $_" } @{ $peer->ident_lines } ),
        $self->said_text(
            'setup.peer_reload', { reload => $peer->reload_command }
        ),
        q{},
    );
}

# The steps after setup, as the audit's first minutes have them: the
# forum's owner, the services, then a check of everything.
sub _next_steps ( $self, $state ) {
    my $as_service = $self->runner($state);
    my @steps;
    if ( !$state->{owned} ) {
        push @steps,
          $self->said_text(
            'setup.next_owner',
            {
                command => $as_service
                  . 'gpforum admin create --email EMAIL --username NAME'
            }
          );
    }
    push @steps, $self->_services_step($state);
    push @steps,
      $self->said_text( 'setup.next_doctor',
        { command => $as_service . 'gpforum doctor' } );

    my $first = shift @steps;
    return (
        $self->said_text( 'cli.next', { step => $first } ),
        map { $self->said_text( 'cli.then', { step => $_ } ) } @steps
    );
}

# How the services are installed: gpforum service print, where that verb is
# there to run, which prints this host's files and the steps that install
# them (ADR 0123); the development server otherwise.
sub _services_step ( $self, $state ) {
    return $self->said_text( 'setup.next_start',
        { command => 'gpforum start --foreground' } )
      if !$state->{deployed};

    my $verb = GPForum::Command::Support::Verbs->find('service');
    my $print =
        $verb && !load_class("GPForum::CLI::$verb->{command}")
      ? $self->_service_print($state)
      : undef;
    return $self->said_text( 'setup.next_services', { command => $print } )
      if defined $print;

    return $self->said_text('setup.next_services_by_hand');
}

# gpforum service print --to the directory this host's service manager
# reads, for the file setup wrote; undef where GPForum ships no service
# files.
sub _service_print ( $self, $state ) {
    my $host = GPForum::Service::Operations::Host->new(
        os               => $self->os,
        catalog          => $self->catalog,
        environment      => $state->{environment},
        environment_file => $state->{file},
    );

    return GPForum::Service::Operations::ServiceFiles->new(
        host             => $host,
        environment_file => $state->{file},
    )->install_step;
}

1;

__END__

=head1 NAME

GPForum::Command::Setup::Report - What setup tells the operator at the end.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Part of GPForum::Command::Setup; callers use that class.

=head1 DESCRIPTION

The report of what changed, the peer-authentication note and the next steps, including the service units.

GPForum::Command::Setup inherits it, so the object a caller builds has every method; this
file holds one part of that class so each part can be read by itself.

=head1 SUBROUTINES/METHODS

=head2 report

A step the parts of GPForum::Command::Setup share.

=head2 print_report

A step the parts of GPForum::Command::Setup share.

=head2 peer

A step the parts of GPForum::Command::Setup share.

=head1 DIAGNOSTICS

As GPForum::Command::Setup.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

As GPForum::Command::Setup.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
