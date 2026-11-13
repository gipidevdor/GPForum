# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Command::Setup::Database;

use Const::Fast;
use Mojo::Base 'GPForum::Command::Setup::Files', -signatures;
use v5.40;

use List::Util qw(any first);
use GPForum::Command::Usage;
use GPForum::Service::Operations::DatabaseFailure;
use GPForum::Service::Operations::DatabaseProvisioning;

our $VERSION = '0.001';

const my %MAKES => (
    'database.unknown_role'     => 'role',
    'database.authentication'   => 'role',
    'database.unknown_database' => 'database',
);
const my $SUPERUSER_ROLE => 'postgres';

# The role and the database: made as the superuser when one answered,
# checked as the forum's role, and said how to make by hand when neither
# worked. Returns whether setup goes on.
sub ensure_database ( $self, $state, $plan, $held, $findings, $changed ) {
    my %target = (
        dsn      => $plan->{GPFORUM_DATABASE_DSN},
        user     => $plan->{GPFORUM_DATABASE_USER},
        password => $plan->{GPFORUM_DATABASE_PASSWORD} // q{},
    );
    my %parameters = (
        database => _database_of($plan),
        server   => $self->_server_of($plan),
        user     => $plan->{GPFORUM_DATABASE_USER},
    );
    my $made = { role_made => 0, database_made => 0 };
    if ( $held->{superuser} ) {
        $made = $self->database->provision(%target);
        if ( $made->{role_made} || $made->{database_made} ) {
            $changed->{database} = 1;
        }
    }

    my $error = $self->as_service( $state,
        sub { return $self->database->connection_error(%target); } );
    if ( !defined $error ) {
        my $what =
            $made->{role_made} && $made->{database_made} ? 'made_both'
          : $made->{role_made}                           ? 'made_role'
          : $made->{database_made}                       ? 'made_database'
          :                                                'present';
        $findings->add(
            name    => 'database',
            status  => 'ok',
            message => $self->_with_superuser(
                [ "setup.database_$what", \%parameters ], $made
            ),
        );
        return 1;
    }

    $self->_database_failed( $state, $held, \%target, \%parameters, $error,
        $findings );

    return 0;
}

# Why the forum's role cannot connect: the role or the database missing,
# with no superuser here to make them, is said with the two psql commands
# that do; anything else as gpforum doctor says it.
sub _database_failed ( $self, $state, $held, $target, $parameters, $error,
    $findings )
{
    my $reader = $self->_failure_reader($state);
    my $unmade = $held->{superuser} ? undef : $self->unmade( $state, $error );
    if ( defined $unmade ) {
        my $command = $self->sudo_command . 'gpforum setup';
        my $role    = ( $self->os->postgresql_superuser // {} )->{role}
          // $SUPERUSER_ROLE;
        $findings->add(
            name    => 'database',
            status  => 'fail',
            message => [
                "setup.database_unmade_$unmade",
                { %{$parameters}, tried => $self->_tried($held) }
            ],
            fixes => [
                $self->said_text(
                    'setup.fix_pguser',
                    {
                        command => $self->sudo_command
                          . "PGUSER=$role gpforum setup"
                    }
                ),
                $self->said_text(
                    "setup.fix_by_hand_$unmade", { command => $command }
                ),
                @{
                    $self->database->commands( %{$target},
                        role_exists => $unmade eq 'database' )
                },
            ],
        );
        return;
    }

    my $parts = $reader->parts($error);
    $findings->add(
        name    => 'database',
        status  => 'fail',
        message => $parts
        ? $self->_labelled( $parts->{problem} )
        : GPForum::Command::Usage->trimmed($error),
        fixes => $parts ? [ $parts->{fix} ] : [],
    );

    return;
}

# A database failure's sentence under the label gpforum doctor's line has
# ("database: cannot reach PostgreSQL at ..."), its first word lowercased
# as doctor lowers it, unless that word is a name with capitals of its own.
sub _labelled ( $self, $problem ) {
    return $self->said_text(
        'doctor.database_problem',
        {
            problem => $problem =~
              s/\A (\p{Lu}) (?= [^\s\p{Lu}]* (?: \s | \z ) )/\l$1/rmsx
        }
    );
}

# The doctor's reader of a database failure, for this file.
sub _failure_reader ( $self, $state ) {
    return GPForum::Service::Operations::DatabaseFailure->new(
        os               => $self->os,
        environment      => $state->{environment},
        environment_file => $state->{file},
    );
}

# What the forum's role, failing to connect, says is missing -- role (with
# its database) or database -- when the superuser's statements put it
# right; undef for any other failure.
sub unmade ( $self, $state, $error ) {
    return undef if !defined $error;
    my $class = $self->_failure_reader($state)->classify($error);

    return $class && exists $MAKES{ $class->{key} }
      ? $MAKES{ $class->{key} }
      : undef;
}

# What each superuser login setup tried was told, as one phrase: "you: role
# "you" does not exist; postgres (GPFORUM_DATABASE_USER): password
# authentication failed for user "postgres"".
sub _tried ( $self, $held ) {
    my @tried = @{ $held->{tried} // [] };
    return $self->said_text('setup.tried_none') if !@tried;

    return join q{; }, map {
        $self->said_text(
            defined $_->{from} ? 'setup.tried_from' : 'setup.tried',
            {
                as     => $_->{as},
                from   => $_->{from} // q{},
                reason => $_->{reason}
            }
        )
    } @tried;
}

# A line of what the superuser made, with which way in setup used: libpq's
# own login, the one the shell or the data source gave, or the server's
# account. A result that does not name the role says nothing more.
sub _with_superuser ( $self, $message, $held ) {
    my ( $key, $parameters ) = @{$message};
    return $message if !defined $held->{as} || !defined $held->{superuser};

    my $way =
        $held->{superuser} eq 'you' ? [ 'setup.by_you', {} ]
      : $held->{superuser} eq 'given'
      ? [ 'setup.by_given', { from => $held->{from} } ]
      : [ 'setup.by_account', { account => $held->{superuser} } ];

    return $self->said_text( $key, $parameters ) . ', '
      . $self->said_text( $way->[0], { %{ $way->[1] }, as => $held->{as} } );
}

# What setup would find or make, for --dry-run: { status, message, fixes }.
# A server that does not answer is said as the run itself would say it, not
# as two statements to print.
sub would_database ( $self, $state, $plan, $held ) {
    my %parameters = (
        database => _database_of($plan),
        server   => $self->_server_of($plan),
        user     => $plan->{GPFORUM_DATABASE_USER},
    );
    if ( !$held->{superuser} ) {
        return {
            status  => 'ok',
            message => [ 'setup.database_present', \%parameters ]
          }
          if !defined $held->{error};
        return {
            status  => 'degraded',
            message => [
                'setup.would_database_unmade',
                { %parameters, tried => $self->_tried($held) }
            ]
          }
          if $held->{unmade};

        my $parts = $self->_failure_reader($state)->parts( $held->{error} );
        return {
            status  => 'degraded',
            message => $parts
            ? $self->_labelled( $parts->{problem} )
            : GPForum::Command::Usage->trimmed( $held->{error} ),
            fixes => $parts ? [ $parts->{fix} ] : [],
        };
    }
    my $what =
        !$held->{role} && !$held->{database} ? 'would_database_made_both'
      : !$held->{role}                       ? 'would_database_made_role'
      : !$held->{database}                   ? 'would_database_made_database'
      :                                        'database_present';

    return {
        status  => 'ok',
        message => $what eq 'database_present'
        ? [ "setup.$what", \%parameters ]
        : $self->_with_superuser( [ "setup.$what", \%parameters ], $held ),
    };
}

sub _database_of ($plan) {
    return GPForum::Service::Operations::DatabaseProvisioning->data_source(
        $plan->{GPFORUM_DATABASE_DSN} )->{database};
}

sub _server_of ( $self, $plan ) {
    my $class = q{GPForum::Service::Operations::DatabaseProvisioning};

    return $class->server_name(
        $class->data_source( $plan->{GPFORUM_DATABASE_DSN} ),
        $self->os );
}

# The schema, as gpforum migrate brings it up to date. Returns whether setup
# goes on.
sub as_service ( $self, $state, $work ) {
    return $work->() if !$state->{deployed} || !$self->is_root;
    return $self->account->with_identity($work);
}

sub ensure_schema ( $self, $state, $findings, $changed ) {
    my $migrated =
      $self->as_service( $state, sub { return $self->migrate->($self); } );
    if ( $migrated->{status} ) {
        $findings->add(
            name    => 'schema',
            status  => 'fail',
            message => ['setup.migrate_failed'],
            fixes   => [ $self->runner($state) . 'gpforum migrate' ],
        );
        return 0;
    }
    if ( $migrated->{changed} ) {
        $changed->{schema} = 1;
    }
    $findings->add(
        name    => 'schema',
        status  => 'ok',
        message => $migrated->{summary},
    );

    return 1;
}

1;

__END__

=head1 NAME

GPForum::Command::Setup::Database - The database and its schema.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Part of GPForum::Command::Setup; callers use that class.

=head1 DESCRIPTION

Creating the database and the role, reading why that failed, and applying the schema as the service account.

GPForum::Command::Setup inherits it, so the object a caller builds has every method; this
file holds one part of that class so each part can be read by itself.

=head1 SUBROUTINES/METHODS

=head2 ensure_database

A step the parts of GPForum::Command::Setup share.

=head2 unmade

A step the parts of GPForum::Command::Setup share.

=head2 would_database

A step the parts of GPForum::Command::Setup share.

=head2 as_service

A step the parts of GPForum::Command::Setup share.

=head2 ensure_schema

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
