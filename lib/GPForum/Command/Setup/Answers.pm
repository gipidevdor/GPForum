# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Command::Setup::Answers;

use Const::Fast;
use Mojo::Base 'GPForum::Command::Setup::Core', -signatures;
use v5.40;

use List::Util qw(any first);
use Mojo::File qw(path);
use Mojo::Util qw(decode encode trim);
use GPForum::Command::Support::ServiceEnvironment;
use GPForum::Command::Usage;
use GPForum::Config;
use GPForum::Config::EnvironmentFile;
use GPForum::Config::Report;
use GPForum::Service::Operations::DatabaseProvisioning;

our $VERSION = '0.001';

const my $EDIT          => 'GPForum::Command::Support::EnvironmentFileEdit';
const my $DEPLOYED      => qr/\A (?: staging | production )/msx;
const my $DATABASE_NAME => 'gpforum';
const my $SMTP_PORT     => 587;
const my $SENDER        => 'forum';
const my $DEVELOPMENT_ADDRESS => 'http://127.0.0.1:3000';
const my @SECRETS => qw(GPFORUM_SESSION_SECRET GPFORUM_METRICS_TOKEN);
const my @SMTP => qw(
  GPFORUM_SMTP_HOST GPFORUM_SMTP_PORT GPFORUM_SMTP_USERNAME GPFORUM_SMTP_PASSWORD
);
const my %SECRET => map { $_ => 1 }
  ( @SECRETS, qw(GPFORUM_DATABASE_PASSWORD GPFORUM_SMTP_PASSWORD) );
const my $YES =>
  qr/\A (?: [ys] | yes | si | s\N{LATIN SMALL LETTER I WITH GRAVE} ) \z/msxi;

# The file as it is: its lines and values, or the template's when there is
# none yet.
sub read_file ( $self, $options ) {
    my $environment = GPForum::Command::Support::ServiceEnvironment->new;
    my $file =
      path( $options->{env_file} // $environment->default_file )
      ->to_abs->to_string;
    my $template = [ split /^/msx, GPForum::Config::EnvironmentFile->render ];

    my %state = (
        file     => $file,
        exists   => -e $file ? 1 : 0,
        template => $EDIT->values_of($template),
    );
    if ( $state{exists} ) {
        GPForum::Command::Support::ServiceEnvironment->new( file => $file )
          ->read_file($file);
        $state{lines} =
          [ split /^/msx, $self->decode_text( path($file)->slurp ) ];
    }
    else {
        $state{lines} = $template;
    }
    $state{values}   = $EDIT->values_of( $state{lines} );
    $state{deployed} = 0;

    return \%state;
}

# The three answers, asked or taken from the options, and what they set.
# Returns the plan, or the exit status when the operator stopped.
sub answers ( $self, $options, $state ) {
    my $environment = $options->{environment}
      // $self->stated( $state, 'GPFORUM_ENV' ) // 'production';
    $state->{environment} = $environment;
    $state->{deployed}    = $environment =~ $DEPLOYED ? 1 : 0;

    my $asking = !$options->{yes};
    if ($asking) {
        $self->ask_line( $self->said_text('setup.intro') );
    }

    my %plan    = ( GPFORUM_ENV => $environment );
    my $address = $self->_answer(
        $options,
        'public_url',
        $self->said_text('setup.ask_address'),
        $self->_suggested_address($state),
        sub ($answer) { return $self->_address_problem( $state, $answer ); }
    );
    return $address if !ref $address;
    $plan{GPFORUM_PUBLIC_BASE_URL} = $address->{value};
    _typed( $state, $address, 'GPFORUM_PUBLIC_BASE_URL' );

    my $suggested_database = $self->stated( $state, 'GPFORUM_DATABASE_DSN' );
    my $database           = $self->_answer(
        $options,
        'database',
        $self->said_text('setup.ask_database'),
        $suggested_database // $self->said_text(
            'setup.suggest_create', { database => $DATABASE_NAME }
        ),
        sub ($answer) { return $self->_database_problem($answer); },
        defined $suggested_database ? undef : 'create',
    );
    return $database if !ref $database;
    $plan{GPFORUM_DATABASE_DSN} = _dsn( $database->{value} );
    _typed( $state, $database, 'GPFORUM_DATABASE_DSN' );
    $plan{GPFORUM_DATABASE_USER} = $options->{database_user}
      // $self->stated( $state, 'GPFORUM_DATABASE_USER' ) // $DATABASE_NAME;

    my $mail = $self->_answer(
        $options,
        'mail',
        $self->said_text('setup.ask_mail'),
        $self->_suggested_mail($state),
        sub ($answer) { return $self->_mail_problem( $state, $answer ); }
    );
    return $mail if !ref $mail;
    my $smtp = $self->_mail_plan( $options, $state, \%plan, $mail->{value} );
    return $smtp if defined $smtp;
    _typed( $state, $mail, 'GPFORUM_MAIL_TRANSPORT', @SMTP[ 0 .. 2 ] );

    for my $secret (@SECRETS) {
        $plan{$secret} = $self->stated( $state, $secret )
          // $self->generate->();
    }
    $plan{GPFORUM_DATABASE_PASSWORD} =
      $self->stated( $state, 'GPFORUM_DATABASE_PASSWORD' );

    # How uploads are scanned is not asked: a new file takes this
    # environment's default -- clamd once deployed, none in development --
    # where the template's line holds production's.
    $plan{GPFORUM_ANTIVIRUS} = $self->stated( $state, 'GPFORUM_ANTIVIRUS' )
      // _default_in( $environment, 'GPFORUM_ANTIVIRUS' );

    return \%plan;
}

# The settings an answer typed at the prompt sets: typing it is the say-so,
# so replacing what the file has is not asked again (Enter, --yes and
# --force keep the question, or its refusal).
sub _typed ( $state, $answer, @names ) {
    return if !$answer->{typed};
    @{ $state->{typed} }{@names} = (1) x @names;

    return;
}

# The sender, once the address is settled: the file's own, kept, unless
# setup derived it from the address the file had (forum@ its host) and the
# address changed -- then it follows the address, and setup says so. One the
# operator wrote stays, whatever the address.
sub plan_sender ( $self, $state, $plan ) {
    my $address = $plan->{GPFORUM_PUBLIC_BASE_URL};
    my $kept    = $self->stated( $state, 'GPFORUM_MAIL_FROM' );
    my $before  = $self->stated( $state, 'GPFORUM_PUBLIC_BASE_URL' );
    if ( !defined $kept ) {
        $plan->{GPFORUM_MAIL_FROM} = _sender($address);
        return;
    }

    my $derived = defined $before && $kept eq _sender($before);
    my $now     = _sender($address);
    if ( $derived && $kept ne $now ) {
        $plan->{GPFORUM_MAIL_FROM} = $now;
        $state->{sender_followed}  = { from => $kept, sender => $now };
        return;
    }
    $plan->{GPFORUM_MAIL_FROM} = $kept;

    return;
}

# A setting's default in an environment, as the settings table gives it.
sub _default_in ( $environment, $variable ) {
    my $setting =
      first { $_->{env} eq $variable } @{ GPForum::Config->settings };
    for my $when ( @{ $setting->{default_when} // [] } ) {
        my ( $on, $values, $default ) = @{$when};
        return $default
          if $on eq 'environment' && any { $_ eq $environment } @{$values};
    }

    return $setting->{default};
}

# One answer: the option's, the suggestion's under --yes, or the
# operator's, asked again until it is one setup can use. Returns { value },
# or the exit status.
sub _answer ( $self, $options, $name, $question, $suggestion, $problem,
    $meaning = undef )
{
    my $given = $options->{$name};
    if ( defined $given || $options->{yes} ) {
        my $value = $given // $meaning // $suggestion;
        my $wrong = $problem->($value);
        return { value => $value } if !defined $wrong;

        return $self->refused($wrong);
    }

    while (1) {
        my $typed = $self->terminal->line(
            defined $suggestion
            ? "$question [$suggestion]:"
            : "$question:"
        );
        return $self->_stopped if !defined $typed;

        $typed = trim($typed);
        my $value = length $typed ? $typed : $meaning // $suggestion;
        next if !defined $value;

        my $wrong = $problem->($value);
        return { value => $value, typed => length $typed ? 1 : 0 }
          if !defined $wrong;
        $self->ask_line($wrong);
    }

    return;
}

# An answer setup cannot use, given as an option: what is wrong with it, and
# where the options are explained -- not the whole usage, which buried the
# one sentence that mattered.
sub refused ( $self, $sentence ) {
    $self->complain( join "\n", $sentence, $self->said_text('setup.see_help') );

    return $GPForum::Command::Usage::EXIT_USAGE;
}

sub _stopped ($self) {
    $self->ask_line(q{});
    $self->ask_line( $self->said_text('setup.stopped') );

    return $GPForum::Command::Usage::EXIT_FAILURE;
}

# The sender at the forum's own name; at localhost for an address that is
# a number or this host.
sub _sender ($address) {
    my ($host) = $address =~ m{\A \w+ :// (?: [^@/]* @ )? ([^/:]+)}msx;
    $host //= 'localhost';
    if ( $host =~ /\A (?: [\d.]+ | localhost | \[ .* ) \z/msx ) {
        $host = 'localhost';
    }

    return "$SENDER\@$host";
}

sub _suggested_address ( $self, $state ) {
    return $self->stated( $state, 'GPFORUM_PUBLIC_BASE_URL' ) // (
        $state->{deployed}
        ? 'https://' . lc $self->host_name
        : $DEVELOPMENT_ADDRESS
    );
}

# The address as the service checks it: an http or https URL, https in
# production, not an example's.
sub _address_problem ( $self, $state, $address ) {
    my @problems = grep { $_->{variable} eq 'GPFORUM_PUBLIC_BASE_URL' } @{
        $self->_problems_of(
            {
                %{ $state->{template} },
                GPFORUM_ENV             => $state->{environment},
                GPFORUM_PUBLIC_BASE_URL => $address,
            }
        )
    };

    return @problems
      ? GPForum::Config::Report->sentence( $problems[0],
        $self->catalog->translator )
      : undef;
}

sub _database_problem ( $self, $answer ) {
    return undef if lc $answer eq 'create';

    my $source =
      GPForum::Service::Operations::DatabaseProvisioning->data_source($answer);
    return undef if defined $source && defined $source->{database};

    return $self->said_text( 'setup.invalid_database', { value => $answer } );
}

sub _dsn ($answer) {
    return lc $answer eq 'create'
      ? "dbi:Pg:dbname=$DATABASE_NAME"
      : $answer;
}

sub _suggested_mail ( $self, $state ) {
    my $transport = $self->stated( $state, 'GPFORUM_MAIL_TRANSPORT' );
    return $state->{deployed} ? 'sendmail' : 'log' if !defined $transport;
    return $transport                              if $transport ne 'smtp';

    my $host = $state->{values}{GPFORUM_SMTP_HOST} // q{};
    my $port = $state->{values}{GPFORUM_SMTP_PORT} || $SMTP_PORT;
    my $user = $state->{values}{GPFORUM_SMTP_USERNAME} // q{};

    return join q{ }, 'smtp', "$host:$port", length $user ? $user : ();
}

sub _mail_problem ( $self, $state, $answer ) {
    my $mail = _mail($answer);
    return $self->said_text( 'setup.invalid_mail', { value => $answer } )
      if !defined $mail;
    return $self->said_text( 'setup.log_refused',
        { environment => $state->{environment} } )
      if $mail->{transport} eq 'log' && $state->{deployed};

    return undef;
}

# sendmail, log (or "log only"), or smtp HOST[:PORT] [USER].
sub _mail ($answer) {
    my $text = trim($answer);
    return { transport => 'sendmail' } if lc $text eq 'sendmail';
    return { transport => 'log' } if $text =~ /\A log (?: \s+ only )? \z/msxi;

    my ( $host, $port, $user ) =
      $text =~ /\A smtp \s+ ([^\s:]+) (?: : (\d+) )? (?: \s+ (\S+) )? \z/msxi;
    return undef if !defined $host;

    return {
        transport => 'smtp',
        host      => $host,
        port      => $port // $SMTP_PORT,
        user      => $user // q{},
    };
}

# What the mail answer sets. An SMTP login needs its password: the file's
# when it is the same login at the same server, else asked without echo or
# read from standard input. Returns undef, or the exit status.
sub _mail_plan ( $self, $options, $state, $plan, $answer ) {
    my $mail = _mail($answer);
    $plan->{GPFORUM_MAIL_TRANSPORT} = $mail->{transport};
    return undef if $mail->{transport} ne 'smtp';

    $plan->{GPFORUM_SMTP_HOST}     = $mail->{host};
    $plan->{GPFORUM_SMTP_PORT}     = $mail->{port};
    $plan->{GPFORUM_SMTP_USERNAME} = $mail->{user};
    return undef if !length $mail->{user};

    my $values = $state->{values};
    my $kept   = $self->stated( $state, 'GPFORUM_SMTP_PASSWORD' );
    if (   defined $kept
        && ( $values->{GPFORUM_SMTP_HOST}     // q{} ) eq $mail->{host}
        && ( $values->{GPFORUM_SMTP_USERNAME} // q{} ) eq $mail->{user} )
    {
        $plan->{GPFORUM_SMTP_PASSWORD} = $kept;
        return undef;
    }

    # At a terminal the password is asked without echo, --smtp-password-stdin
    # or not: read as a line there, it showed on the screen as typed.
    my $password;
    if ( !$self->terminal->is_interactive && $options->{smtp_password_stdin} ) {
        my $input = $self->input;
        $password = <$input>;
        if ( defined $password ) {
            chomp $password;
        }
    }
    elsif ( $self->terminal->is_interactive ) {
        $password = $self->terminal->hidden_line(
            $self->said_text(
                'setup.ask_smtp_password',
                { user => $mail->{user}, host => $mail->{host} }
            )
        );
    }
    else {
        return $self->refused( $self->said_text('setup.no_smtp_password') );
    }
    return $self->_stopped if !defined $password;

    $plan->{GPFORUM_SMTP_PASSWORD} = $self->decode_text($password);

    return undef;
}

# The settings the file has that the answers would change: confirmed one
# by one on a terminal, replaced with --force, and otherwise said, with
# nothing written. Returns undef to go on, or the exit status.
sub conflicts ( $self, $options, $state, $plan ) {
    my @conflicts = $self->_conflicting( $state, $plan );
    return undef if !@conflicts || $options->{force};

    if ( $options->{yes} ) {
        $self->complain(
            join "\n",
            (
                map {
                    $self->said_text( 'setup.conflict',
                        $self->_conflict( $state, $plan, $_ ) )
                } @conflicts
            ),
            $self->said_text(
                'setup.conflict_footer',
                { file => $state->{file} }
            )
        );
        return $GPForum::Command::Usage::EXIT_FAILURE;
    }

    for my $name ( grep { !$state->{typed}{$_} } @conflicts ) {
        my $reply = $self->terminal->line(
            $self->said_text(
                'setup.ask_replace', $self->_conflict( $state, $plan, $name )
            )
        );
        return $self->_stopped if !defined $reply;
        next                   if trim($reply) =~ $YES;

        $plan->{$name} = $self->stated( $state, $name );
    }

    return undef;
}

# The names the file sets to something else than the answers would; the
# secrets setup makes only where the file has none.
sub _conflicting ( $self, $state, $plan ) {
    return grep {
        my $given = $self->stated( $state, $_ );
        ( !exists $SECRET{$_} || $_ eq 'GPFORUM_SMTP_PASSWORD' )
          && defined $given
          && defined $plan->{$_}
          && $given ne $plan->{$_}
    } sort keys %{$plan};
}

sub _conflict ( $self, $state, $plan, $name ) {
    return {
        file     => $state->{file},
        variable => $name,
        current  => _shown( $name, $self->stated( $state, $name ) ),
        wanted   => _shown( $name, $plan->{$name} ),
    };
}

# A value as the conflict shows it: a secret not at all, a DSN or a URL
# without the password it carries.
sub _shown ( $name, $value ) {
    return exists $SECRET{$name}
      ? '********'
      : GPForum::Config::Report->without_passwords($value);
}

# What the server holds, asked before anything is written: the role's
# password is made here when setup is to make the role, or to print the
# statements that make it, so the file holds it before the role exists. A
# server that does not answer at all is no reason to make one: an existing
# file without a password kept none.
sub inspect_database ( $self, $state, $plan ) {
    my %target = (
        dsn  => $plan->{GPFORUM_DATABASE_DSN},
        user => $plan->{GPFORUM_DATABASE_USER},
    );
    my $held = $self->database->inspect(%target);
    if ( !$held->{superuser} ) {
        $held->{tried} //= [];
        $held->{error} = $self->database->connection_error( %target,
            password => $plan->{GPFORUM_DATABASE_PASSWORD} );
        $held->{unmade} = $self->unmade( $state, $held->{error} );
    }

    # A role that logged in to say its database is missing has the password
    # it has, or needs none: a new one in the file would lock it out.
    my $needs_password =
      $held->{superuser}
      ? !$held->{role}
      : ( $held->{unmade} // q{} ) eq 'role';
    if ( $needs_password && !defined $plan->{GPFORUM_DATABASE_PASSWORD} ) {
        $plan->{GPFORUM_DATABASE_PASSWORD} = $self->generate->();
    }

    return $held;
}

# The file's lines with the plan written in: the template's when there is
# no file yet, each other line as it was.
sub planned_lines ( $self, $state, $plan ) {
    my @lines = @{ $state->{lines} };
    for my $name (
        qw(GPFORUM_ENV GPFORUM_PUBLIC_BASE_URL),
        $SECRETS[0],
        qw(GPFORUM_DATABASE_DSN GPFORUM_DATABASE_USER GPFORUM_DATABASE_PASSWORD),
        $SECRETS[1],
        qw(GPFORUM_MAIL_TRANSPORT GPFORUM_MAIL_FROM),
        @SMTP,
        'GPFORUM_ANTIVIRUS',
      )
    {
        next if !defined $plan->{$name};
        my $current = $EDIT->values_of( \@lines )->{$name};
        next if defined $current && $current eq $plan->{$name};

        $EDIT->assign( \@lines, $name, $plan->{$name} );
    }

    return \@lines;
}

# The problems the service would find in the file as planned, every one.
sub settings_problems ( $self, $lines ) {
    return $self->_problems_of( $EDIT->values_of($lines) );
}

sub _problems_of ( $self, $values ) {
    my $problems = [];
    try {
        GPForum::Config->from_environment( { %{$values} } );
    }
    catch ($error) {
        die $error if !GPForum::X::Config->caught($error);    ## no critic (ErrorHandling::RequireCarping) -- rethrows the caught error as it was raised
        $problems = $error->problems;
    };

    return $problems;
}

1;

__END__

=head1 NAME

GPForum::Command::Setup::Answers - Reading, asking for and checking the answers.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Part of GPForum::Command::Setup; callers use that class.

=head1 DESCRIPTION

Reading the environment file, working out each answer from the file, the flags or a question, and checking the address, mail and database answers and the conflicts between them.

GPForum::Command::Setup inherits it, so the object a caller builds has every method; this
file holds one part of that class so each part can be read by itself.

=head1 SUBROUTINES/METHODS

=head2 read_file

A step the parts of GPForum::Command::Setup share.

=head2 answers

A step the parts of GPForum::Command::Setup share.

=head2 plan_sender

A step the parts of GPForum::Command::Setup share.

=head2 refused

A step the parts of GPForum::Command::Setup share.

=head2 conflicts

A step the parts of GPForum::Command::Setup share.

=head2 inspect_database

A step the parts of GPForum::Command::Setup share.

=head2 planned_lines

A step the parts of GPForum::Command::Setup share.

=head2 settings_problems

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
