# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Command::Setup;

use Const::Fast;

use English       qw(-no_match_vars);
use JSON::MaybeXS ();
use List::Util    qw(any first);
use Mojo::Base 'GPForum::Command::Setup::Report', -signatures;
use v5.40;
use Mojo::File  qw(path);
use Mojo::Util  qw(decode encode trim);
use Net::Domain ();

use GPForum::Command::Migrate;
use GPForum::Command::Secret;
use GPForum::Command::Support::Terminal;
use GPForum::Command::Support::Words;
use GPForum::Command::Usage;
use GPForum::Config;
use GPForum::OS;
use GPForum::Schema;
use GPForum::Service::Admin::Bootstrapper;
use GPForum::Service::I18N::CliCatalog;
use GPForum::Service::Operations::DatabaseProvisioning;
use GPForum::Service::Operations::Findings;
use GPForum::Service::Operations::ServiceAccount;
use GPForum::X::Io;

our $VERSION = '0.001';

const my $COMMAND => 'gpforum-setup';

# The environments setup writes, and the deployed ones among them, which run
# as services under the account and refuse mail that only reaches the log.
const my @ENVIRONMENTS => qw(production staging development);

# What "create" means: the forum's database and role, named as the template
# names them, on this host.

# The address a development forum answers at: gpforum start --foreground's.

# The file: readable by the services' group and nobody else, in a directory
# anyone may enter.

# Where stat puts the mode, the owner and the group.

# What each answer sets, in the order the file is written.
const my @SECRETS => qw(GPFORUM_SESSION_SECRET GPFORUM_METRICS_TOKEN);

# The template's example addresses, which a copied file may still hold.

# The settings whose value is never shown, in a conflict or anywhere else.

# The failures of the forum's role that the role and the database setup
# makes would put right, and what each leaves to make: a refused password is
# how PostgreSQL answers for a role it does not have, when it asks for one;
# a database it does not have, it says only once the role has logged in.

# The superuser role a fix names, where the operating system's is not known.

# What the operator answers "yes" with, in either language.

has input  => sub { return \*STDIN; };
has prompt => sub { return \*STDERR; };
has output => sub { return \*STDOUT; };

# Where the questions are asked; a test gives its own.
has terminal => sub ($self) {
    return GPForum::Command::Support::Terminal->new(
        input  => $self->input,
        prompt => $self->prompt,
    );
};

has catalog => sub { return GPForum::Service::I18N::CliCatalog->new; };
has os      => sub { return GPForum::OS->detect; };

# Who runs it: root makes the account, gives the file to its group and may
# reach PostgreSQL as its own account.
has effective_uid => sub { return $EFFECTIVE_USER_ID; };

# The checkout the services run from, which holds the uploads.
has root => sub {
    return path(__FILE__)->to_abs->dirname->dirname->dirname->dirname;
};

# Where setup links gpforum, so it runs from any directory: root's
# /usr/local/bin, on the PATH of Debian, FreeBSD and macOS alike, or the
# operator's own bin where the system has one (Homebrew's, on macOS); none
# otherwise. A test gives its own.
has links_into => sub ($self) {
    return $self->is_root ? '/usr/local/bin' : $self->os->operator_bin;
};

has account => sub ($self) {
    return GPForum::Service::Operations::ServiceAccount->new( os => $self->os );
};

# PostgreSQL's superuser is tried with the login the shell gives too
# (GPFORUM_DATABASE_USER, GPFORUM_DATABASE_PASSWORD): read here, when the run
# starts, before the file it writes is loaded over the shell's settings.
has database => sub ($self) {
    my $class = 'GPForum::Service::Operations::DatabaseProvisioning';
    return $class->new(
        os            => $self->os,
        effective_uid => $self->effective_uid,
        given_logins  => $class->logins_of( \%ENV ),
    );
};

# Makes a secret: gpforum secret rotate's.
has generate => sub { return GPForum::Command::Secret->new->generate; };

# This host's fully qualified name, the address suggested in production.
has host_name => sub { return Net::Domain::hostfqdn() // 'localhost'; };

# Brings the schema up to date as gpforum migrate does, under the settings
# the file holds, and returns { status, summary }: its exit status and its
# one-line summary. A test gives its own.
has migrate => sub { return \&_migrate; };

# Whether the forum has an owner: 1, 0, or undef when it cannot tell. A test
# gives its own.
has owner_check => sub { return \&_has_owner; };

sub run ( $self, @arguments ) {
    return GPForum::Command::Usage->help( \*STDOUT, _usage() )
      if GPForum::Command::Usage->wants_help(@arguments);

    my $options = GPForum::Command::Usage->read_arguments( _usage(),
        sub { return $self->_options(@arguments) } );
    return $options if !ref $options;
    if ( !$options->{yes} && !$self->terminal->is_interactive ) {
        return $self->refused( $self->said_text('setup.no_terminal') );
    }

    my $status;
    try {
        $status = $self->_setup($options);
    }
    catch ($error) {
        return GPForum::Command::Usage->failure( $error,
            $options->{json}
            ? ( $self->output, { command => $COMMAND, findings => [] } )
            : () );
    };

    return $status;
}

# Public so the Mojolicious command adapter in GPForum::CLI can show the same
# text --help prints.
sub usage_text ($class) {
    return _usage();
}

sub _usage {
    return <<'USAGE';
Usage: gpforum setup [--yes] [--public-url URL] [--database create|DSN]
                     [--mail sendmail|'smtp HOST[:PORT] [USER]'|log]
                     [--environment production|staging|development]
                     [--database-user ROLE] [--smtp-password-stdin]
                     [--force] [--dry-run] [--json] [--env-file FILE]

Sets this host up to run the forum. It asks three questions -- the public
address, the database, and how mail leaves -- and Enter accepts each
suggestion. On a fresh clone it first installs the dependencies, as make
install-deps-production does. Then it:

  - makes the account gpforum the services run as, with the directory its
    uploads go in, when run as root (useradd, pw, or dscl on macOS);
  - links gpforum into /usr/local/bin when run as root, or into Homebrew's
    bin on macOS, so it runs from any directory;
  - writes the environment file the service reads (/etc/gpforum/gpforum.env,
    /usr/local/etc/gpforum/gpforum.env on FreeBSD, Homebrew's etc/ on
    macOS), mode 0640, root:gpforum when run as root, with a new session
    secret and metrics token;
  - makes the database role and the database, as PostgreSQL's superuser,
    when it can reach one, and otherwise prints the two psql commands;
  - brings the schema up to date, as gpforum migrate does;
  - and says what to do next.

Run again, it changes nothing that is already right and says so. It never
replaces a setting the file has unless you say so -- an answer typed at the
prompt, yes when it asks, or --force -- and never prints a secret. A sender
it derived from the address follows a new address; one you wrote stays.

  --yes                 take every suggestion and ask nothing, for scripts
  --public-url URL      the address members reach the forum at
  --database create     make the database gpforum on this host (default)
  --database DSN        use this DBI data source, such as
                        dbi:Pg:dbname=gpforum;host=db.internal;port=5432
  --database-user ROLE  the role the forum connects as (default gpforum)
  --mail sendmail       hand mail to this host's mail server (default)
  --mail 'smtp HOST[:PORT] [USER]'
                        send through an SMTP server; port 587 by default; a
                        password for USER is asked, or read with
                        --smtp-password-stdin
  --mail log            write mail to the log: development only
  --environment NAME    production (default), staging or development
  --force               replace settings the file already has
  --dry-run             say what it would do, changing nothing
  --json                one JSON object on stdout instead of sentences
  --env-file FILE       write FILE instead of this host's environment file
  --help                show this help

Exit status: 0 the host is set up; 1 a step failed, or the file has
settings it would replace without --force; 2 usage error; 78 settings the
service could not use.
USAGE
}

sub _options ( $self, @arguments ) {
    my %options = ( yes => 0, force => 0, dry_run => 0, json => 0 );
    my $usage   = _usage();
    my $value   = sub ($name) {
        return sub ( $options, $given ) {
            GPForum::Command::Usage->option_value( $given, qr/\S/msx, $usage,
                "--$name" =~ tr/_/-/r );
            $options->{$name} =
              $name eq 'env_file' ? $given : $self->decode_text($given);
        };
    };

    GPForum::Command::Usage->parse_options(
        \@arguments,
        \%options,
        {
            switches => {
                '--yes'                 => { yes                 => 1 },
                '--force'               => { force               => 1 },
                '--dry-run'             => { dry_run             => 1 },
                '--json'                => { json                => 1 },
                '--smtp-password-stdin' => { smtp_password_stdin => 1 },
            },
            values => {
                '--public-url'    => $value->('public_url'),
                '--database'      => $value->('database'),
                '--database-user' => $value->('database_user'),
                '--mail'          => $value->('mail'),
                '--env-file'      => $value->('env_file'),
                '--environment'   => sub ( $options, $given ) {
                    $options->{environment} =
                      GPForum::Command::Usage->option_choice( $given,
                        [@ENVIRONMENTS], $usage, '--environment' );
                },
            },
            usage => $usage,
        }
    );

    return \%options;
}

# The whole run: the answers, the plan, then each step, said as it is done.
sub _setup ( $self, $options ) {
    $self->database;
    my $state = $self->read_file($options);
    my $plan  = $self->answers( $options, $state );
    return $plan if !ref $plan;

    my $refused = $self->conflicts( $options, $state, $plan );
    return $refused if defined $refused;
    $self->plan_sender( $state, $plan );
    $state->{peer} = $self->peer( $state, $plan );

    my $database = $self->inspect_database( $state, $plan );
    my $lines    = $self->planned_lines( $state, $plan );
    my $problems = $self->settings_problems($lines);
    if ( @{$problems} ) {
        print {*STDERR} encode(
            'UTF-8',
            GPForum::Command::Support::Words->new->config_report(
                $problems, $state->{file}
            )
          )
          or GPForum::X::Io->throw(
            message => 'failed to write the settings report' );
        return $GPForum::Command::Usage::EXIT_CONFIG;
    }

    my $findings =
      GPForum::Service::Operations::Findings->new( catalog => $self->catalog );
    return $self->dry_run( $options, $state, $plan, $database, $lines,
        $findings )
      if $options->{dry_run};

    my %changed;
    my $continue =
         $self->ensure_account( $state, $lines, $findings, \%changed )
      && $self->write_file( $state, $lines, $findings, \%changed )
      && $self->ensure_link( $findings, \%changed );
    if ($continue) {
        local %ENV = %ENV;
        $self->load_environment($state);
        $continue =
          $self->ensure_database( $state, $plan, $database, $findings,
            \%changed )
          && $self->ensure_schema( $state, $findings, \%changed );
        $state->{owned} =
          $continue
          ? $self->as_service( $state,
            sub { return $self->owner_check->($self); } )
          : 1;
    }

    return $self->report( $options, $state, $findings, \%changed );
}

# gpforum migrate, run here with the file's settings. Its document is read
# from --json, and its one line said as setup's own; a failure's sentence
# reaches the operator on standard error, as gpforum migrate writes it.
sub _migrate ($self) {
    my $output  = q{};
    my $migrate = GPForum::Command::Migrate->new( default_mode => 'apply' );
    my $status;
    {
        open my $capture, '>', \$output
          or GPForum::X::Io->throw( message => "capture: $OS_ERROR" );
        local *STDOUT = $capture;
        $status = $migrate->run('--json');
        close $capture
          or GPForum::X::Io->throw( message => "capture: $OS_ERROR" );
    }
    my $document = {};
    try {
        $document = JSON::MaybeXS->new( utf8 => 1 )->decode($output);
    }
    catch ($error) {
        $status ||= $GPForum::Command::Usage::EXIT_FAILURE;
    };
    return { status => $status } if $status;

    my $applied = $document->{applied}                         // [];
    my $budgets = $document->{budgets}                         // {};
    my $created = ( $document->{partitions} // {} )->{created} // [];
    my $changes =
      @{$applied} +
      @{$created} +
      ( $budgets->{written}  // 0 ) +
      @{ $budgets->{removed} // [] };

    return {
        status  => 0,
        summary => $migrate->summary( $applied, $document ),
        changed => $changes ? 1 : 0,
    };
}

sub _has_owner ($self) {
    my $owned;
    try {
        my $schema = GPForum::Schema->connect_from_config(
            GPForum::Config->from_environment );
        $owned =
          GPForum::Service::Admin::Bootstrapper->new( schema => $schema )
          ->has_owner;
        $schema->storage->disconnect;
    }
    catch ($error) {
        $owned = undef;
    };

    return $owned;
}

1;

__END__

=head1 NAME

GPForum::Command::Setup - Sets a host up to run the forum, in three
questions.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # sudo gpforum setup
    # gpforum setup --yes --public-url https://forum.example.org \
    #   --database create --mail sendmail
    exit GPForum::Command::Setup->new->run(@ARGV);

=head1 DESCRIPTION

C<gpforum setup> asks for the public address, the database and how mail
leaves, Enter taking each suggestion, and then does what a fresh install
needs, saying each step as a line of C<gpforum doctor>'s kind: it makes the
account the services run as (as root) and links C<gpforum> into
F</usr/local/bin> (or Homebrew's F<bin>), writes the
environment file the service reads with new secrets, makes the database role
and database as PostgreSQL's superuser when it can reach one, applies the
migrations, and names the next steps. Re-run on a host it set up, it changes
nothing and says so. It never replaces a setting the file has unless the
operator says so -- an answer typed at the prompt, yes when it asks, or
C<--force> -- and never prints a secret; a sender it derived from the
address follows a new one. ADR 0122 says why it does
each of these and leaves the service files to C<gpforum service print>.

=head1 SUBROUTINES/METHODS

=head2 run

Runs the command line. Returns 0 when the host is set up, 1 when a step
failed or the file has settings it would replace, 2 on misuse, 78 when the
settings would stop the service.

=head2 usage_text

The text C<--help> prints.

=head2 links_into

Where setup links C<gpforum>: F</usr/local/bin> for root, Homebrew's
F<bin> for anyone else on macOS, or undef.

=head1 DIAGNOSTICS

Every sentence is in the operator's language, from the command-line
catalogs (C<setup.*>).

=head1 CONFIGURATION AND ENVIRONMENT

Writes the host's environment file, or the one given with C<--env-file>. In
development run through sudo, the file is the developer's, from
C<SUDO_UID> and C<SUDO_GID>.

=head1 DEPENDENCIES

L<GPForum::Service::Operations::ServiceAccount>,
L<GPForum::Service::Operations::DatabaseProvisioning>,
L<GPForum::Command::Support::EnvironmentFileEdit>, L<GPForum::Command::Migrate>,
L<GPForum::Command::Secret> for its secrets.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The account is made where the system has a command for it: C<useradd>,
C<pw>, or C<dscl> on macOS under the highest id below 500 no user and no
group has; with none free, setup says to make it by hand. The service files
are written by C<gpforum service print>, which the operator runs.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
