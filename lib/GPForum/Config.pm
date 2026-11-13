# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Config;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;
use DateTime::TimeZone;
use Email::Address::XS;
use English    qw(-no_match_vars);
use List::Util qw(any first max min pairmap);
use Mojo::File qw(path);

use GPForum::Config::Report;
use GPForum::Config::Settings;
use GPForum::OS;
use GPForum::OS::Memory;
use GPForum::X::Config;

our $VERSION = '0.001';
const my $INTEGRATION_HOST_LIMIT   => 1_024;
const my $INTEGRATION_SOURCE_LIMIT => 32;
const my $INTEGRATION_HOST_CHAR    => qr{[[:lower:][:digit:]]}amsx;
const my $INTEGRATION_HOST_LABEL =>
qr{$INTEGRATION_HOST_CHAR(?:[[:lower:][:digit:]-]{0,61}$INTEGRATION_HOST_CHAR)?}amsx;
const my $INTEGRATION_HOST =>
  qr{(?:${INTEGRATION_HOST_LABEL}[.])+[[:lower:]]{2,63}}amsx;
const my $DISCORD_WEBHOOK_ID       => qr{[[:digit:]]{15,24}}amsx;
const my $DISCORD_WEBHOOK_TOKEN    => qr{[[:alnum:]_-]{40,100}}amsx;
const my $MINIMUM_MEDIA_MIB        => 100;
const my $MAXIMUM_MEDIA_MIB        => 250;
const my $MINIMUM_ARGON_MEMORY_MIB => 19;
const my $MAXIMUM_ARGON_MEMORY_MIB => 256;
const my $MAXIMUM_ARGON_ITERATIONS => 10;

const my $DEVELOPMENT_SESSION_SECRET =>
  GPForum::Config::Settings->development_session_secret;
const my $DEVELOPMENT_SECOND_FACTOR_KEY =>
  'gpforum-development-second-factor-key-change-me';
const my $MAXIMUM_PROCESS_COUNT => 512;

# Production signs sessions with a secret at least this long: 32 characters
# of `openssl rand -hex 32` is 128 bits of it.
const my $MINIMUM_PRODUCTION_SECRET =>
  GPForum::Config::Settings->minimum_production_secret;

# GPFORUM_WEB_PROCESSES=auto runs as many web processes as the CPUs carry,
# but never more than this: each holds PostgreSQL connections -- its queries
# and its live-update LISTEN -- and PostgreSQL's default max_connections is
# 100. A larger host is one whose operator chooses the number.
const my $MAXIMUM_AUTOMATIC_WEB_PROCESSES => 16;
const my $AUTOMATIC => GPForum::Config::Settings->automatic_word;

# GPFORUM_LOCAL_CACHE_MAX_ENTRIES=auto gives each web process an equal part
# of an eighth of the host's memory, at about 16 KiB an entry -- a rendered
# fragment, a category list -- rounded down to a power of two between 1024
# and 16384: 4096, the old fixed default, on a 1 GB host with two web
# processes. A host whose memory cannot be measured keeps 4096.
const my $CACHE_MEMORY_SHARE      => 8;
const my $CACHE_ENTRY_BYTES       => 16 * 1_024;
const my $MINIMUM_AUTOMATIC_CACHE => 1_024;
const my $MAXIMUM_AUTOMATIC_CACHE => 16_384;
const my $UNMEASURED_CACHE        => 4_096;

const my $GLIFISTORE_TCP_URL =>
  qr{\A (?:tcp://)? [[:alnum:]._-]+ : [[:digit:]]+ \z}msx;
const my $GLIFISTORE_UNIX_URL => qr{\A unix:// \S+ \z}msx;

# A public address: a scheme, a host (a name, an IPv4 address or a bracketed
# IPv6 one), an optional port and an optional path.
const my $PUBLIC_HOST =>
  qr{ [[:alnum:]] [[:alnum:].-]* | \[ [[:xdigit:]:.]+ \] }msx;
const my $URL_REST   => qr{ (?: : [[:digit:]]+ )? (?: [/?#] \S* )? }msx;
const my $PUBLIC_URL => qr{\A (https?) :// ($PUBLIC_HOST) $URL_REST \z}msxi;

# RFC 9116 section 2.5.3: a security.txt Contact is a mailto:, https: or tel:
# URI (RFC 6068, RFC 9110, RFC 3966), with no space or control character.
const my $MAILTO_URI  => qr{mailto: [^\s@]+ @ [^\s@]+}msxi;
const my $HTTPS_URI   => qr{https :// $PUBLIC_HOST $URL_REST}msxi;
const my $TEL_URI     => qr{tel: [+]? [\d().-]+}msxi;
const my $CONTACT_URI => qr{\A (?: $MAILTO_URI | $HTTPS_URI | $TEL_URI ) \z}msx;

# The names RFC 2606 keeps for examples, which no DNS will ever point at a
# forum and no mail server delivers from: the template's
# https://forum.example.com and forum@forum.example.com, left as copied.
const my $RESERVED_NAME =>
  qr{ example [.] (?: com | net | org ) | example | invalid }msxi;
const my $EXAMPLE_HOST => qr{ (?: \A | [.] ) (?: $RESERVED_NAME ) [.]? \z }msxi;

# Both kinds of TLS to an SMTP server run through this module, which
# Net::SMTP needs only once it is asked for TLS: at the first message.
const my $TLS_MODULE => 'IO::Socket::SSL';

# Where Hypnotoad listens: a URL with a scheme, as Mojo::Server::Daemon reads
# it -- http://127.0.0.1:8080, https://*:443?cert=..., http+unix://... -- not a
# bare port.
const my $LISTEN_LOCATION => qr{\A (?: https? | http[+]unix ) :// \S+ \z}msxi;

# A sender mail servers refuse to take from another host.
const my $LOCAL_SENDER =>
  qr{\@ (?: localhost | 127[.]0[.]0[.]1 | \[::1\] ) \z}msxi;

# A language tag as GPForum::Service::I18N::Locale accepts one, lowercased and
# with - between its parts: a language, then optional subtags (it, it-it,
# zh-hant-tw).
const my $LANGUAGE_TAG =>
  qr{\A [[:lower:]]{2,8} (?: - [[:lower:][:digit:]]{1,8} )* \z}msx;

# The deployed environments. They need a rotated session secret, a metrics
# token and Secure cookies, they refuse the log mail transport, and they
# default to the system's clamd and sendmail. Production, on top, needs an
# https address, a sender mail servers accept and a long session secret.
const my @DEPLOYED      => GPForum::Config::Settings->deployed_environments;
const my %IS_DEPLOYED   => map { $_ => 1 } @DEPLOYED;
const my %IS_PRODUCTION => ( production => 1 );

# How a boolean may be written. Each word reads as 1 or 0.
const my %BOOLEAN => (
    ( map { $_ => 1 } qw(1 yes true on) ),
    ( map { $_ => 0 } qw(0 no false off) ),
);

# The languages the forum ships: the catalogs in locale/ at the root of the
# checkout, two directories above the one holding lib/GPForum/Config.pm.
# Resolved while the module loads, so a later chdir cannot move it.
const my $CHECKOUT_DEPTH   => 2;
const my $LOCALE_DIRECTORY => _locale_directory_of(__FILE__);

# A suggestion for a mistyped value is offered only when it is this close:
# it shares a prefix this long, or it is one edit away for every this many
# characters typed (always at least one).
const my $MINIMUM_PREFIX       => 3;
const my $SUGGESTION_PER_CHARS => 3;

# A unique violation an api.* function raises is a conflict by its SQLSTATE,
# whatever language the server writes it in (Infrastructure::SqlFunction).
# UniqueConflict, on the DBIx::Class paths the test doubles keep, matches
# "duplicate key" and "unique constraint" in the error text, English words:
# under any other lc_messages a unique violation there reads as an unknown
# error and its savepoint recovery rethrows it. PostgreSQL lets only a
# superuser, or a role granted SET on it, set lc_messages, and production
# connects as an ordinary role: a plain SET refused every connection,
# migrations included. So it is set where the role may and otherwise left at
# the server's setting. Asking first is a
# function call; the PL/pgSQL block with an exception handler it replaces
# cost a millisecond of every connection's three (ADR 0137).
const my $SET_MESSAGE_LOCALE =>
  q{CASE WHEN pg_catalog.has_parameter_privilege('lc_messages', 'SET')}
  . q{ THEN pg_catalog.set_config('lc_messages', 'C', false) END};

# What a connection puts in its startup packet unless the DSN says
# otherwise: the name pg_stat_activity and the server's log show for it, and
# how long libpq waits for the server. A local socket answers in
# milliseconds, so five seconds is a server that is not answering (ADR 0137).
const my $APPLICATION     => 'gpforum';
const my $CONNECT_TIMEOUT => 5;

# The fuzzy-title threshold for search. Searcher matches titles with the pg_trgm
# % operator, which reads this setting, because % can use the trigram index and
# a similarity(...) >= ? cannot. pg_trgm's own default of 0.3 would quietly
# drop every match between 0.18 and 0.3. Setting a pg_trgm parameter before
# the extension is loaded is allowed: PostgreSQL keeps it as a placeholder
# until then.
const my $SEARCH_SIMILARITY => 0.18;

const my @SETTINGS      => @{ GPForum::Config::Settings->rows };
const my %SETTING_NAMED => map { $_->{name}          => $_ } @SETTINGS;
const my %POSITION      => map { $SETTINGS[$_]{name} => $_ } 0 .. $#SETTINGS;

# What validate refuses, by the name a setting's check gives. Each rule
# returns a problem (see _problem_of), or undef when the value is fine.
# Const::Fast cannot copy code references, so the table is a plain hash.
my %RULE = (
    integration_hosts     => \&_rule_integration_hosts,
    integration_sources   => \&_rule_integration_sources,
    discord_webhook       => \&_rule_discord_webhook,
    oidc_issuer           => \&_rule_oidc_issuer,
    media_size            => \&_rule_media_size,
    optional_mail_reply   => \&_rule_optional_mail_reply,
    optional_mailbox      => \&_rule_optional_mailbox,
    optional_contact_uri  => \&_rule_optional_contact_uri,
    optional_websub_hub   => \&_rule_optional_websub_hub,
    password_cost         => \&_rule_password_cost,
    required              => \&_rule_required,
    positive              => \&_rule_positive,
    non_negative          => \&_rule_non_negative,
    boolean               => \&_rule_boolean,
    process_count         => \&_rule_process_count,
    timezone              => \&_rule_timezone,
    locale                => \&_rule_locale,
    public_url            => \&_rule_public_url,
    session_secret        => \&_rule_session_secret,
    previous_secrets      => \&_rule_previous_secrets,
    metrics_token         => \&_rule_metrics_token,
    second_factor_key     => \&_rule_second_factor_key,
    listen                => \&_rule_listen,
    trusted_when_proxied  => \&_rule_trusted_when_proxied,
    required_by_minion    => \&_rule_required_by_minion,
    glifistore            => \&_rule_glifistore,
    mail_transport        => \&_rule_mail_transport,
    mail_from             => \&_rule_mail_from,
    smtp_host             => \&_rule_smtp_host,
    command_for_antivirus => \&_rule_command_for_antivirus,
);

# A list's default is a fresh empty array for each configuration; an
# automatic setting's is worked out when first read.
for my $setting (@SETTINGS) {
    my $name = $setting->{name};
    if ( $setting->{automatic} ) {
        my $builder = "automatic_$name";
        has $name => sub ($self) { return $self->$builder; };
        next;
    }

    my $is_list = $setting->{type} eq 'list' || $setting->{type} eq 'words';
    has $name => $is_list ? sub { return [] } : $setting->{default};
}

sub from_environment ( $class, $environment = undef ) {
    $environment //= \%ENV;

    my ( %read, @problems );
    for my $setting (@SETTINGS) {
        my ( $value, $problem ) = _read( $environment, $setting, \%read );
        push @problems, $problem // ();
        next if !defined $value;

        $read{ $setting->{name} } = $value;
    }
    push @problems, _test_transport_problem( $environment, \%read ) // ();

    my $self    = $class->new(%read);
    my %refused = map { $_->{variable} => 1 } @problems;
    push @problems, grep { !$refused{ $_->{variable} } } @{ $self->problems };
    _refuse(
        [
            sort { $POSITION{ $a->{setting} } <=> $POSITION{ $b->{setting} } }
              @problems
        ]
    );

    return $self;
}

sub validate ($self) {
    _refuse( $self->problems );

    return $self;
}

# Every problem, not just the first: an operator fixes them all in one edit
# instead of learning of one per start.
sub problems ($self) {
    return [ grep { defined } map { _problem( $self, $_ ) } @SETTINGS ];
}

sub settings ($class) {
    return [ map { +{ %{$_} } } @SETTINGS ];
}

sub requires_secure_transport ($self) {
    return _is_deployed( $self->environment );
}

sub is_production ($self) {
    return _is_production( $self->environment );
}

sub signing_secrets ($self) {
    return _unique_head( $self->session_secret,
        $self->previous_session_secrets );
}

sub accepted_metrics_tokens ($self) {
    return _unique_head( $self->metrics_token, $self->previous_metrics_tokens );
}

# ADR 0142: the keys that open two-step sign-in secrets, the one that seals
# first; in development, a fixed key when none is set, and where the forum
# is deployed, none.
sub second_factor_keys ($self) {
    my $key = $self->second_factor_key // q{};
    if ( !length $key ) {
        return [] if _is_deployed( $self->environment );
        $key = $DEVELOPMENT_SECOND_FACTOR_KEY;
    }

    return _unique_head( $key, $self->previous_second_factor_keys );
}

# Mail sent by smtp with TLS on, from a Perl that cannot load the TLS module,
# fails at the first message -- a sign-up's confirmation, a password reset --
# long after the start. It is not one of problems(): what this Perl has
# installed is a fact about the host, not the settings, and the test suite
# builds configurations on hosts without it. Every place that checks the
# settings the way the service's start does asks it here, so doctor,
# mail-check and the front door answer as the start-up does
# (Bootstrap::Config). undef when mail does not leave by smtp, TLS is off, or
# the module loads ($can_tls, by default smtp_can_tls's answer).
sub smtp_tls_problem ( $self, $can_tls = undef ) {
    return undef
      if $self->mail_transport ne 'smtp' || $self->smtp_tls eq 'off';
    return undef if $can_tls // $self->smtp_can_tls;

    return {
        key        => 'config.smtp_tls_module',
        setting    => 'smtp_tls',
        variable   => $SETTING_NAMED{smtp_tls}{env},
        value      => $self->smtp_tls,
        parameters => { module => $TLS_MODULE },
        generate   => undef,
        example    => undef,
    };
}

# The configuration, or GPForum::X::Config for its smtp_tls_problem, in
# English like every other refusal of from_environment.
sub assert_smtp_tls ( $self, $can_tls = undef ) {
    my $problem = $self->smtp_tls_problem($can_tls);
    _refuse( $problem ? [$problem] : [] );

    return $self;
}

# Whether Net::SMTP, under Email::Sender, can speak TLS, asked of Net::SMTP
# itself: it loads the TLS module, at the version it needs, when it is
# loaded. Asked once per process; the answer does not change while it runs.
sub smtp_can_tls ($invocant) {
    state $can = do {
        require Net::SMTP;
        Net::SMTP->can_ssl ? 1 : 0;
    };

    return $can;
}

# As many web processes as cap-to-cpu lets the CPUs carry, at least one and
# at most $MAXIMUM_AUTOMATIC_WEB_PROCESSES. The CPUs are the ones the host's
# profile counts for a worker (OS::Base::worker_cpu_count: all of them, or
# fewer where some cores are worth less), counted once per process: a host
# does not gain any while GPForum runs, and counting them can mean running
# sysctl.
sub automatic_web_processes ($self) {
    return min(
        $MAXIMUM_AUTOMATIC_WEB_PROCESSES,
        max(
            1,
            ( $self->host_worker_cpus || 1 ) * $self->runtime_max_web_per_cpu
        )
    );
}

# Each web process's own cache, sized from the host's memory: an equal part,
# for each web process, of an eighth of it, at about 16 KiB an entry, rounded
# down to a power of two between 1024 and 16384; 4096 when the memory cannot
# be measured.
sub automatic_local_cache_max_entries ($self) {
    my $bytes = $self->host_memory_bytes;
    return $UNMEASURED_CACHE if !$bytes;

    my $entries =
      $bytes / $CACHE_MEMORY_SHARE /
      max( 1, $self->web_processes ) /
      $CACHE_ENTRY_BYTES;
    my $power = $MINIMUM_AUTOMATIC_CACHE;
    while ( $power * 2 <= $entries && $power < $MAXIMUM_AUTOMATIC_CACHE ) {
        $power *= 2;
    }

    return $power;
}

# What the host gives GPForum, each asked once per process: a host does not
# gain CPUs or memory while GPForum runs, and asking can mean running sysctl.
# The CPUs a worker counts (OS::Base::worker_cpu_count: all of them, or fewer
# where some cores are worth less), every logical CPU, and the memory in
# bytes (undef when it cannot be measured).
sub host_worker_cpus ($self) {
    state $cpus = GPForum::OS->detect->worker_cpu_count;

    return $cpus;
}

sub host_cpus ($self) {
    state $cpus = GPForum::OS->detect->cpu_count;

    return $cpus;
}

sub host_memory_bytes ($self) {
    state $bytes =
      GPForum::OS::Memory->new->detect( GPForum::OS->detect->name )->{bytes};

    return $bytes;
}

# How this node is sized, for gpforum doctor: the host's CPUs and memory,
# and each size worked out from them that the node runs with -- a size the
# operator set to something else is theirs, not the host's (audit D1').
sub sizing ($self) {
    my %sizes;
    for my $setting ( grep { $_->{automatic} } @SETTINGS ) {
        my $name    = $setting->{name};
        my $builder = "automatic_$name";
        my $value   = $self->$name;
        if ( $value == $self->$builder ) {
            $sizes{$name} = $value;
        }
    }

    return {
        cpus         => $self->host_cpus,
        memory_bytes => $self->host_memory_bytes,
        sizes        => \%sizes,
    };
}

sub os_feature_settings ($self) {
    return { reuseport => $self->os_reuseport, };
}

sub os_preflight_settings ($self) {
    return {
        min_recommended_workers   => $self->os_min_recommended_workers,
        max_open_file_descriptors => $self->os_max_open_file_descriptors,
    };
}

# The addresses whose X-Forwarded-For is believed. Only the loopback by
# default: the shipped proxies run on the same host. Believing any sender, as
# before, let a client that reached the application directly name its own
# address, and with it its rate-limit bucket.
sub runtime_trusted_proxy_list ($self) {
    return [ _csv_items( $self->runtime_trusted_proxies ) ];
}

sub runtime_listen_locations ($self) {
    return [ _csv_items( $self->runtime_listen ) ];
}

# The statement every connection runs once it is made, alone in its list:
# the timeouts, the search similarity and the message locale, set in one
# round trip. The query statistics know it by this text, so a worker's
# first request, which makes its connection, is not charged a statement it
# did not ask for. The values are integers the settings checked, and the
# threshold a constant.
sub database_session_settings ($self) {
    my @setting = (
        statement_timeout => $self->database_statement_timeout_ms,
        idle_in_transaction_session_timeout =>
          $self->database_idle_in_transaction_timeout_ms,
        lock_timeout                   => $self->database_lock_timeout_ms,
        'pg_trgm.similarity_threshold' => $SEARCH_SIMILARITY,
    );
    my @calls = pairmap { "pg_catalog.set_config('$a', '$b', false)" } @setting;

    return [ 'SELECT ' . join q{, }, @calls, $SET_MESSAGE_LOCALE ];
}

# The name this process's connections carry: gpforum-web for what Hypnotoad
# loaded, gpforum-VERB for a verb run through the front door, gpforum
# otherwise. The front door names the process "gpforum VERB" while the verb
# runs; Hypnotoad sets HYPNOTOAD_APP in the manager its workers fork from.
sub database_application_name ($self) {
    return "$APPLICATION-web" if defined $ENV{HYPNOTOAD_APP};

    my ($verb) = $PROGRAM_NAME =~ /\A $APPLICATION \s+ ([[:alnum:]_-]+)/msx;
    return defined $verb ? "$APPLICATION-$verb" : $APPLICATION;
}

# The DSN with the startup options a connection gets unless the operator
# set them: in the startup packet they cost no statement.
sub database_connection_dsn ($self) {
    my $dsn = $self->database_dsn;
    my %given =
      map { /\A \s* ([^=\s]+) \s* =/msx ? ( lc $1 => 1 ) : () }
      split /;/msx, $dsn =~ s/\A dbi:Pg://rmsxi;
    my @added = (
        $given{application_name}
        ? ()
        : 'application_name=' . $self->database_application_name,
        $given{connect_timeout} ? () : "connect_timeout=$CONNECT_TIMEOUT",
    );

    return join q{;}, $dsn, @added;
}

sub database_connect_info ($self) {
    return (
        $self->database_connection_dsn,
        $self->database_user,
        $self->database_password,
        {
            AutoCommit     => 1,
            RaiseError     => 1,
            PrintError     => 0,
            on_connect_do  => $self->database_session_settings,
            pg_enable_utf8 => 1,
        },
    );
}

# Throws one X::Config carrying every problem, its message the whole report
# in English. Bootstrap::Config renders the same problems in the operator's
# language.
sub _refuse ($problems) {
    return if !@{$problems};

    GPForum::X::Config->throw(
        message  => GPForum::Config::Report->render($problems),
        problems => $problems,
    );
}

# One setting's value from the environment, and the problem reading it when
# there is one. An unset or empty variable takes the default; a value that
# does not parse is a problem, and the setting keeps its default so the rest
# can still be checked. An automatic setting left at auto reads as undef, for
# its builder. A variable that is not there is asked about with exists, never
# read: a read-only hash, such as a Const::Fast one, refuses a read of a key it
# does not hold.
sub _read ( $environment, $setting, $read ) {
    my $raw =
      _is_set( $environment, $setting )
      ? $environment->{ $setting->{env} }
      : undef;
    my $value = $raw // _default( $setting, $read );
    my $type  = $setting->{type};

    if ( $type eq 'list' ) {
        return [ _csv_items($value) ];
    }
    if ( $type eq 'words' ) {
        return [ grep { length } split /\s+/msx, $value ];
    }
    if ( $type eq 'boolean' ) {
        return _read_boolean( $setting, $value );
    }
    if ( $type eq 'integer' ) {
        return _read_integer( $setting, $value, $read );
    }

    return $value;
}

sub _read_boolean ( $setting, $value ) {
    my $word = lc trim($value);
    if ( exists $BOOLEAN{$word} ) {
        return $BOOLEAN{$word};
    }

    return ( $setting->{default},
        _problem_of( $setting, 'config.not_boolean', $value ) );
}

sub _read_integer ( $setting, $value, $read ) {
    if ( $setting->{automatic} && lc($value) eq $AUTOMATIC ) {
        return undef;
    }
    if ( $value !~ /\A [[:digit:]]+ \z/msx ) {
        my $key =
          $setting->{automatic}
          ? 'config.not_integer_or_auto'
          : 'config.not_integer';
        my $default = $setting->{default};
        return (
            $default eq $AUTOMATIC ? undef : $default,
            _problem_of( $setting, $key, $value )
        );
    }

    my $number = int $value;
    my $limit  = $setting->{within} && $read->{ $setting->{within} };

    return $limit && $number > $limit ? $limit : $number;
}

sub _is_set ( $environment, $setting ) {
    my $variable = $setting->{env};

    return
         exists $environment->{$variable}
      && defined $environment->{$variable}
      && length $environment->{$variable} ? 1 : 0;
}

# The default from_environment reads a setting with: the first default_when
# whose setting holds one of its values, else the plain default.
sub _default ( $setting, $read ) {
    for my $case ( @{ $setting->{default_when} // [] } ) {
        my ( $other, $values, $default ) = @{$case};
        if ( any { $_ eq $read->{$other} } @{$values} ) {
            return $default;
        }
    }

    return $setting->{default} // q{};
}

# The first thing wrong with one setting's value, or undef.
sub _problem ( $self, $setting ) {
    my $name = $setting->{name};

    # An automatic setting not given a number is worked out from the host when
    # first read, and is in bounds by construction. Reading it here would count
    # the CPUs -- run sysctl or nproc -- for every configuration checked, in
    # every command, whether it needs the number or not.
    return undef if $setting->{automatic} && !exists $self->{$name};

    my $value = $self->$name;

    my $rule    = $setting->{check};
    my $problem = $rule ? $RULE{$rule}->( $self, $setting, $value ) : undef;
    if ( defined $problem ) {
        return $problem;
    }

    my $choices = $setting->{one_of};
    if ($choices) {
        my $choice = _value_choice_problem( $setting, $value, $choices );
        return $choice if defined $choice;
        return undef   if $setting->{type} eq 'list';
    }

    # Held only to a positive limit: zero is no limit, and a negative one is
    # its own setting's problem.
    my $limit = $setting->{within};
    if ( $limit && $self->$limit > 0 && $value > $self->$limit ) {
        return _problem_of(
            $setting,
            'config.not_above',
            $value,
            limit_variable => $SETTING_NAMED{$limit}{env},
            limit          => $self->$limit,
        );
    }

    return undef;
}

sub _value_choice_problem ( $setting, $value, $choices ) {
    my @values = $setting->{type} eq 'list' ? @{$value} : ( $value // q{} );
    for my $item (@values) {
        return _choice_problem( $setting, $item, $choices )
          if !any { $_ eq $item } @{$choices};
    }
    return undef;
}

# A problem: the catalog key of its sentence, the variable it names, the
# value it refused and the sentence's other placeholders, with an example or
# the command that makes a secret.
sub _problem_of ( $setting, $key, $value, %parameters ) {
    my $example = $setting->{example} // _example_default($setting);

    return {
        key        => $key,
        setting    => $setting->{name},
        variable   => $setting->{env},
        value      => ref $value ? join( q{,}, @{$value} ) : $value // q{},
        parameters => \%parameters,
        generate   => $setting->{generate},
        example    => $example,
    };
}

# The default, as an operator writes it, when a setting has no example of its
# own: on or off for a boolean, nothing for a list.
sub _example_default ($setting) {
    my $type = $setting->{type};
    return undef if $type eq 'list' || $type eq 'words';
    return $setting->{default} ? 'on' : 'off' if $type eq 'boolean';

    return $setting->{default};
}

sub _choice_problem ( $setting, $value, $choices ) {
    my $problem = _problem_of(
        $setting, 'config.one_of', $value,
        choices => join q{, },
        @{$choices}
    );
    my $nearest = _nearest( $value, $choices );
    if ( defined $nearest ) {
        $problem->{suggestion} = "$setting->{env}=$nearest";
        $problem->{example}    = undef;
    }

    return $problem;
}

sub _rule_required ( $self, $setting, $value ) {
    return defined $value && length $value
      ? undef
      : _problem_of( $setting, 'config.required', $value );
}

sub _rule_required_in ( $self, $setting, $value ) {
    return defined $value && length $value
      ? undef
      : _problem_of( $setting, 'config.required_in', $value,
        environment => $self->environment );
}

sub _rule_password_cost ( $self, $setting, $value ) {
    my ( $minimum, $maximum ) =
      $setting->{name} eq 'password_memory_mib'
      ? ( $MINIMUM_ARGON_MEMORY_MIB, $MAXIMUM_ARGON_MEMORY_MIB )
      : ( 2, $MAXIMUM_ARGON_ITERATIONS );
    return _at_least( $setting, $value, $minimum ) if $value < $minimum;
    return $value > $maximum
      ? _problem_of( $setting, 'config.at_most', $value, maximum => $maximum )
      : undef;
}

sub _rule_positive ( $self, $setting, $value ) {
    return _at_least( $setting, $value, 1 );
}

sub _rule_media_size ( $self, $setting, $value ) {
    return _at_least( $setting, $value, $MINIMUM_MEDIA_MIB )
      if $value < $MINIMUM_MEDIA_MIB;
    return _problem_of( $setting, 'config.at_most', $value,
        maximum => $MAXIMUM_MEDIA_MIB )
      if $value > $MAXIMUM_MEDIA_MIB;
    return undef;
}

sub _rule_non_negative ( $self, $setting, $value ) {
    return _at_least( $setting, $value, 0 );
}

sub _at_least ( $setting, $value, $minimum ) {
    return $value < $minimum
      ? _problem_of( $setting, 'config.at_least', $value, minimum => $minimum )
      : undef;
}

sub _rule_boolean ( $self, $setting, $value ) {
    return defined $value && "$value" =~ /\A [01] \z/msx
      ? undef
      : _problem_of( $setting, 'config.not_boolean', $value );
}

sub _rule_process_count ( $self, $setting, $value ) {
    if ( $value < 1 ) {
        return _at_least( $setting, $value, 1 );
    }

    return $value > $MAXIMUM_PROCESS_COUNT
      ? _problem_of( $setting, 'config.at_most', $value,
        maximum => $MAXIMUM_PROCESS_COUNT )
      : undef;
}

sub _rule_timezone ( $self, $setting, $value ) {
    return DateTime::TimeZone->is_valid_name($value)
      ? undef
      : _problem_of( $setting, 'config.timezone', $value );
}

# A language tag the forum reads as one of its locales, as
# GPForum::Service::I18N::Locale reads it: any case, - or _ between the parts,
# so it, IT, it-IT and it_IT are all Italian. it_IT.UTF-8, a POSIX locale
# rather than a tag, the forum would quietly show in English: it is refused,
# with the locale it names as the suggestion.
sub _rule_locale ( $self, $setting, $value ) {
    my $required = _rule_required( $self, $setting, $value );
    return $required if $required;

    my $locales = _shipped_locales();
    return undef if !@{$locales};

    my $tag        = ( lc trim($value) ) =~ tr/_/-/r;
    my ($language) = $tag =~ /\A ([[:lower:]]{2,8}) /msx;
    my $shipped    = defined $language && any { $_ eq $language } @{$locales};
    return undef if $shipped && $tag =~ $LANGUAGE_TAG;

    my $problem = _choice_problem( $setting, $value, $locales );
    if ($shipped) {
        $problem->{suggestion} = "$setting->{env}=$language";
        $problem->{example}    = undef;
    }

    return $problem;
}

sub _rule_optional_mail_reply ( $self, $setting, $value ) {
    return undef if !length $value;
    my @addresses = Email::Address::XS->parse($value);
    return _problem_of( $setting, 'config.mailbox', $value )
      if $value =~ /[\r\n]/msx
      || @addresses != 1
      || !$addresses[0]->is_valid
      || $addresses[0]->address ne $value;
    return undef;
}

# One plain address, as an operator writes it for people to read.
sub _rule_optional_mailbox ( $self, $setting, $value ) {
    return _rule_optional_mail_reply( $self, $setting, $value );
}

# RFC 9116 section 2.5.3: a Contact is a URI, mailto:, https: or tel:.
sub _rule_optional_contact_uri ( $self, $setting, $value ) {
    return undef if !length $value;
    return undef if $value =~ $CONTACT_URI;
    return _problem_of( $setting, 'config.contact_uri', $value );
}

sub _rule_integration_hosts ( $self, $setting, $value ) {
    return _problem_of( $setting, 'config.url', q{} )
      if @{$value} > $INTEGRATION_HOST_LIMIT;
    for my $host ( @{$value} ) {
        return _problem_of( $setting, 'config.url', q{} )
          if $host !~ /\A $INTEGRATION_HOST \z/amsx;
    }
    return undef;
}

sub _rule_integration_sources ( $self, $setting, $value ) {
    return _problem_of( $setting, 'config.url', q{} )
      if @{$value} > $INTEGRATION_SOURCE_LIMIT;
    for my $url ( @{$value} ) {
        return _problem_of( $setting, 'config.url', q{} )
          if _rule_optional_websub_hub( $self, $setting, $url );
    }
    return undef;
}

sub _rule_discord_webhook ( $self, $setting, $value ) {
    return undef if !length $value;
    return undef
      if $value =~
m{\A https://discord[.]com/api/(?:v10/)?webhooks/$DISCORD_WEBHOOK_ID/$DISCORD_WEBHOOK_TOKEN \z}amsx;
    return _problem_of( $setting, 'config.url', q{} );
}

sub _rule_oidc_issuer ( $self, $setting, $value ) {
    return undef if !length $value;
    return _problem_of( $setting, 'config.url', q{} )
      if _rule_optional_websub_hub( $self, $setting, $value );
    for my $field (
        qw(oidc_authorization_endpoint oidc_token_endpoint oidc_jwks_uri oidc_client_id oidc_client_secret)
      )
    {
        return _problem_of( $setting, 'config.required', q{} )
          if !length $self->$field;
    }
    return undef;
}

sub _rule_optional_websub_hub ( $self, $setting, $value ) {
    return undef if !length $value;
    return _problem_of( $setting, 'config.url', $value )
      if $value !~ $PUBLIC_URL
      || $value !~ /\A https:\/\//msx
      || $value =~ /[\x00-\x20\x7f#]/msx;
    return undef;
}

sub _rule_public_url ( $self, $setting, $value ) {
    my $required = _rule_required( $self, $setting, $value );
    return $required if $required;

    my ( $scheme, $host ) = $value =~ $PUBLIC_URL;
    if ( !$scheme ) {
        return _problem_of( $setting, 'config.url', $value );
    }

    my $environment = $self->environment;
    if ( _is_production($environment) && lc $scheme ne 'https' ) {
        return _problem_of( $setting, 'config.https', $value,
            environment => $environment );
    }

    return _is_deployed($environment)
      ? _placeholder( $setting, 'config.placeholder_url', $value, $host,
        $environment )
      : undef;
}

# An address under a name kept for examples, which a deployed forum would
# put in every link and every sender it mails. No example is offered: the
# template's is the one that was refused.
sub _placeholder ( $setting, $key, $value, $host, $environment ) {
    return undef if $host !~ $EXAMPLE_HOST;

    return {
        %{
            _problem_of( $setting, $key, $value, environment => $environment )
        },
        example => undef,
    };
}

# Staging and production sign with their own secret; production's is long.
sub _rule_session_secret ( $self, $setting, $value ) {
    my $environment = $self->environment;
    if ( _is_deployed($environment) && $value eq $DEVELOPMENT_SESSION_SECRET ) {
        return _rule_required_in( $self, $setting, q{} );
    }
    my $required = _rule_required( $self, $setting, $value );
    return $required if $required;

    return _is_production($environment)
      && length $value < $MINIMUM_PRODUCTION_SECRET
      ? _problem_of(
        $setting, 'config.short_secret',
        $value,
        environment => $environment,
        length      => length $value,
        minimum     => $MINIMUM_PRODUCTION_SECRET,
      )
      : undef;
}

sub _rule_previous_secrets ( $self, $setting, $value ) {
    return undef if !_is_deployed( $self->environment );

    my $development =
      any { defined && $_ eq $DEVELOPMENT_SESSION_SECRET } @{ $value || [] };

    return $development
      ? _problem_of( $setting, 'config.development_secret', q{} )
      : undef;
}

# A key set where the forum is deployed is not the development one, and in
# production it is as long as a session secret.
sub _rule_second_factor_key ( $self, $setting, $value ) {
    my $environment = $self->environment;
    return undef if !length( $value // q{} );
    return _problem_of( $setting, 'config.development_secret', q{} )
      if _is_deployed($environment)
      && $value eq $DEVELOPMENT_SECOND_FACTOR_KEY;

    return _is_production($environment)
      && length $value < $MINIMUM_PRODUCTION_SECRET
      ? _problem_of(
        $setting, 'config.short_secret',
        $value,
        environment => $environment,
        length      => length $value,
        minimum     => $MINIMUM_PRODUCTION_SECRET,
      )
      : undef;
}

# /metrics never answers unauthenticated where it is deployed.
sub _rule_metrics_token ( $self, $setting, $value ) {
    return _is_deployed( $self->environment )
      ? _rule_required_in( $self, $setting, $value )
      : undef;
}

sub _rule_listen ( $self, $setting, $value ) {
    my $required = _rule_required( $self, $setting, $value );
    return $required if $required;

    my @locations  = _csv_items($value);
    my $unreadable = !@locations || any { $_ !~ $LISTEN_LOCATION } @locations;

    return $unreadable
      ? _problem_of( $setting, 'config.listen', $value )
      : undef;
}

sub _rule_trusted_when_proxied ( $self, $setting, $value ) {
    return $self->runtime_proxy && !@{ $self->runtime_trusted_proxy_list }
      ? _problem_of( $setting, 'config.trusted_proxies', $value,
        proxy_variable => $SETTING_NAMED{runtime_proxy}{env} )
      : undef;
}

sub _rule_required_by_minion ( $self, $setting, $value ) {
    return ( $self->minion_enabled // 0 ) eq '1'
      && !( defined $value && length $value )
      ? _problem_of( $setting, 'config.minion_url', $value,
        minion_variable => $SETTING_NAMED{minion_enabled}{env} )
      : undef;
}

sub _rule_glifistore ( $self, $setting, $value ) {
    return
         defined $value
      && length $value
      && $value !~ $GLIFISTORE_TCP_URL && $value !~ $GLIFISTORE_UNIX_URL
      ? _problem_of( $setting, 'config.glifistore_url', $value )
      : undef;
}

# log only writes mail where an operator reads it: never where members wait
# for it.
sub _rule_mail_transport ( $self, $setting, $value ) {
    my $required = _rule_required( $self, $setting, $value );
    return $required if $required;

    return _is_deployed( $self->environment ) && $value eq 'log'
      ? _problem_of(
        $setting, 'config.log_transport',
        $value,   environment => $self->environment
      )
      : undef;
}

# test keeps mail in memory and sends nothing. It is the plain default, which
# a configuration built with new keeps for the test suite; read from the
# environment, production defaults to sendmail, so test there is one an
# operator wrote, and members would wait for mail that never leaves.
sub _test_transport_problem ( $environment, $read ) {
    my $setting = $SETTING_NAMED{mail_transport};
    return undef
      if !_is_production( $read->{environment} )
      || !_is_set( $environment, $setting )
      || $read->{mail_transport} ne 'test';

    return _problem_of(
        $setting, 'config.test_transport',
        'test',   environment => $read->{environment}
    );
}

# The address a sender names: the part between < and > of one with a
# display name, Forum <forum@forum.example.com>, which the checks below read
# the domain of; the value itself otherwise. Its closing > had kept the
# template's domain from being recognized.
sub _sender_address ($value) {
    my ($address) = $value =~ /< \s* ([^<>]+?) \s* > \s* \z/msx;

    return $address // $value;
}

sub _rule_mail_from ( $self, $setting, $value ) {
    my $required = _rule_required( $self, $setting, $value );
    return $required if $required;

    my $environment = $self->environment;
    my $address     = _sender_address($value);
    if ( _is_production($environment) && $address =~ $LOCAL_SENDER ) {
        return _problem_of(
            $setting, 'config.mail_from_local',
            $value,   environment => $environment
        );
    }

    my ($domain) = $address =~ /\@ ([^@]+) \z/msx;
    return _is_deployed($environment)
      && defined $domain
      ? _placeholder( $setting, 'config.placeholder_mail_from',
        $value, $domain, $environment )
      : undef;
}

sub _rule_smtp_host ( $self, $setting, $value ) {
    return ( $self->mail_transport // q{} ) eq 'smtp'
      && !( defined $value && length $value )
      ? _problem_of( $setting, 'config.smtp_host', $value,
        transport_variable => $SETTING_NAMED{mail_transport}{env} )
      : undef;
}

sub _rule_command_for_antivirus ( $self, $setting, $value ) {
    return $self->antivirus eq 'command' && !@{$value}
      ? _problem_of( $setting, 'config.antivirus_command', $value,
        antivirus_variable => $SETTING_NAMED{antivirus}{env} )
      : undef;
}

# The choice an operator most likely meant: one the value begins (prod for
# production), one that begins the value (warning for warn), or one a couple
# of keystrokes away (producton). Undef when none is close.
sub _nearest ( $value, $choices ) {
    my $typed = lc( $value // q{} );
    return undef if !length $typed;

    my ($longer) = sort { length $a <=> length $b }
      grep { length $typed >= $MINIMUM_PREFIX && index( $_, $typed ) == 0 }
      @{$choices};
    return $longer if defined $longer;

    my $shorter =
      first { length $_ >= $MINIMUM_PREFIX && index( $typed, $_ ) == 0 }
      @{$choices};
    return $shorter if defined $shorter;

    my $allowed = max( 1, int( length($typed) / $SUGGESTION_PER_CHARS ) );
    my ($closest) =
      sort { $a->[1] <=> $b->[1] }
      grep { $_->[1] <= $allowed }
      map  { [ $_, _distance( $typed, $_ ) ] } @{$choices};

    return $closest ? $closest->[0] : undef;
}

# Levenshtein distance: the fewest single-character edits from one to the
# other.
sub _distance ( $from, $to ) {
    my @previous = ( 0 .. length $to );
    for my $i ( 1 .. length $from ) {
        my @current = ($i);
        for my $j ( 1 .. length $to ) {
            my $cost =
              substr( $from, $i - 1, 1 ) eq substr( $to, $j - 1, 1 ) ? 0 : 1;
            push @current,
              min(
                $previous[$j] + 1,
                $current[ $j - 1 ] + 1,
                $previous[ $j - 1 ] + $cost
              );
        }
        @previous = @current;
    }

    return $previous[-1];
}

# The locales whose catalogs ship in locale/. None found -- a tree without
# its catalogs -- leaves the setting unchecked rather than refusing them all.
sub _shipped_locales {
    state $locales = [ sort map { $_->basename('.po') }
          path($LOCALE_DIRECTORY)->list->grep(qr/[.]po\z/msx)->each ];

    return $locales;
}

sub _locale_directory_of ($file) {
    my $directory = path($file)->to_abs->dirname;
    for ( 1 .. $CHECKOUT_DEPTH ) {
        $directory = $directory->dirname;
    }

    return $directory->child('locale')->to_string;
}

sub _is_deployed ($environment) {
    return $environment && exists $IS_DEPLOYED{$environment} ? 1 : 0;
}

sub _is_production ($environment) {
    return $environment && exists $IS_PRODUCTION{$environment} ? 1 : 0;
}

sub _csv_items ($raw) {
    return grep { length } map { trim($_) } split /,/msx, $raw;
}

# The first value, then each later one not seen before; empty ones are
# dropped.
sub _unique_head ( $first, $rest ) {
    my %seen = ( $first => 1 );

    return [ $first,
        grep { defined && length && !$seen{$_}++ } @{ $rest || [] } ];
}

1;

__END__

=head1 NAME

GPForum::Config - Environment-backed configuration object.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $config = GPForum::Config->from_environment;

=head1 DESCRIPTION

Loads and validates the configuration, including the multi-process runtime
profile. Every setting is one row of a table: its attribute, its
C<GPFORUM_*> variable, its default, the rule L</validate> applies, the
section it belongs to and a one-line summary. The same table drives the
reading, the checks, the problems an operator is shown and
C<deploy/gpforum.env.example>.

=head1 SUBROUTINES/METHODS

=head2 from_environment

Builds configuration from an environment hash (C<%ENV> by default). Every
problem -- a value that does not parse and a value L</validate> refuses -- is
reported at once, in one L<GPForum::X::Config>.

=head2 validate

Throws L<GPForum::X::Config> when L</problems> finds any; returns the
configuration otherwise.

=head2 problems

Every problem with the configuration, in table order, as an array reference
of hash references: C<key> (the catalog key of its sentence), C<setting>,
C<variable>, C<value>, C<parameters>, and what helps fix it -- C<example>,
C<generate> or C<suggestion>. L<GPForum::Config::Report> renders them.

=head2 settings

Class method. A copy of the settings table, one hash reference per setting
with C<name>, C<env>, C<default>, C<type>, C<section>, C<summary>,
C<operator>, C<operator_when>, C<example> and C<generate>, in table order.

=head2 requires_secure_transport

True for staging and production profiles. Those environments require a
rotated session secret, Secure cookies, and HSTS.

=head2 is_production

True for production: the environment that also requires an https address, a sender mail servers
accept and a long session secret, and that never send the benchmark query
headers.

=head2 signing_secrets

Returns the Mojolicious secret list. The current session secret is first
and signs new cookies. Previous secrets from
C<GPFORUM_SESSION_SECRETS> still validate existing cookies.

=head2 accepted_metrics_tokens

Returns the current metrics token followed by previous tokens from
C<GPFORUM_METRICS_TOKENS>. Scrapers may present either during rotation.
Staging and production refuse to start without C<GPFORUM_METRICS_TOKEN>, so
the list is never empty there and C</metrics> cannot fail open. Development
and test may leave it unset and keep C</metrics> unauthenticated.

=head2 second_factor_keys

Returns the keys two-step sign-in secrets are sealed and opened with (ADR
0142): C<GPFORUM_SECOND_FACTOR_KEY> first, which seals, then those of
C<GPFORUM_SECOND_FACTOR_KEYS>, which still open. Without a key, development
and test use a fixed development key, and a deployed forum gets an empty
list: two-step sign-in is not offered there until a key is set.

=head2 smtp_tls_problem

Takes, optionally, whether this Perl can speak TLS to an SMTP server (by
default L</smtp_can_tls>'s answer) and returns the problem the service's
start stops with -- C<config.smtp_tls_module>, under C<GPFORUM_SMTP_TLS> --
when mail leaves by C<smtp> with C<smtp_tls> on and it cannot, or undef. It
is not one of L</problems>: it is a fact about the host, which doctor,
mail-check, the front door and L<GPForum::Bootstrap::Config> ask for.

=head2 assert_smtp_tls

Takes the same optional argument and returns the configuration, or throws
L<GPForum::X::Config> with L</smtp_tls_problem>'s problem, in English, as
L</from_environment> throws its own.

=head2 smtp_can_tls

Class or instance method: 1 when L<Net::SMTP> can speak TLS (it can only
with IO::Socket::SSL installed), else 0. Asked once per process.

=head2 automatic_web_processes

The web process count C<GPFORUM_WEB_PROCESSES=auto> stands for: the CPUs
(L</host_worker_cpus>) times C<GPFORUM_RUNTIME_MAX_WEB_PER_CPU>, at least 1
and at most 16. It is the default, and C<web_processes> reads it unless a
number is set.

=head2 automatic_local_cache_max_entries

The cache size C<GPFORUM_LOCAL_CACHE_MAX_ENTRIES=auto> stands for: each web
process's equal part of an eighth of L</host_memory_bytes>, at 16 KiB an
entry, rounded down to a power of two from 1024 to 16384, or 4096 when the
memory cannot be measured. It is the default, and C<local_cache_max_entries>
reads it unless a number is set.

=head2 host_worker_cpus

The CPUs a web worker counts on this host (L<GPForum::OS::Base/worker_cpu_count>),
asked once per process.

=head2 host_cpus

Every logical CPU of this host, asked once per process.

=head2 host_memory_bytes

This host's memory in bytes, or a container's limit when it is less
(L<GPForum::OS::Memory>); undef when it cannot be measured. Asked once per
process.

=head2 sizing

How the node is sized, for C<gpforum doctor>: C<cpus>, C<memory_bytes>, and
C<sizes>, each automatic setting (C<web_processes>,
C<local_cache_max_entries>) the node runs at the host's size, by name. One the
operator set to another number is left out.

=head2 os_feature_settings

The OS feature switch, C<GPFORUM_OS_REUSEPORT>, keyed without the prefix.

=head2 os_preflight_settings

The operating-system preflight thresholds, keyed without the prefix.

=head2 runtime_trusted_proxy_list

The addresses and networks (C<GPFORUM_RUNTIME_TRUSTED_PROXIES>, comma
separated; C<127.0.0.1,::1> by default) whose C<X-Forwarded-For> Hypnotoad
believes when C<runtime_proxy> is on.

=head2 runtime_listen_locations

The comma-separated C<runtime_listen> locations as a list.

=head2 database_session_settings

The statement every connection runs once it is made, alone in an array
reference: one C<SELECT> of C<set_config> calls for the timeouts, the
search similarity threshold and, where the role may set it, the message
locale (ADR 0137). C<database_connect_info> passes it as C<on_connect_do>;
the query statistics know it by this text.

=head2 database_application_name

The C<application_name> this process's connections carry: C<gpforum-web>
for what Hypnotoad loaded, C<gpforum-VERB> for a verb run through the front
door, C<gpforum> otherwise.

=head2 database_connection_dsn

C<database_dsn> with C<application_name> and C<connect_timeout=5> added to
its startup options, each unless the DSN already sets it.

=head2 database_connect_info

Returns DBI connection arguments for the Mojo::Pg transport: C<database_connection_dsn>,
the role and its password, and the attributes. Session
C<statement_timeout>, C<idle_in_transaction_session_timeout> and
C<lock_timeout> are applied on connect. Zero
milliseconds disables that PostgreSQL timeout. C<gpforum migrate>
clears C<statement_timeout> after connect so DDL is not capped at the web
budget.

=head1 DIAGNOSTICS

Throws L<GPForum::X::Config> with every problem found. Its C<problems> are
the records L</problems> describes; its message is the English report
L<GPForum::Config::Report> renders from them: a header, each problem naming
its variable with an example, a suggestion for a mistyped choice or the
command that generates a secret, and a footer, ending in a newline.

=head1 CONFIGURATION AND ENVIRONMENT

Reads C<GPFORUM_*> environment variables, including PostgreSQL connection
settings (C<GPFORUM_DATABASE_STATEMENT_TIMEOUT_MS>,
C<GPFORUM_DATABASE_IDLE_IN_TRANSACTION_TIMEOUT_MS>,
C<GPFORUM_DATABASE_LOCK_TIMEOUT_MS>), search's bounds (below), session
rotation (C<GPFORUM_SESSION_SECRET>, comma-separated
C<GPFORUM_SESSION_SECRETS>), metrics scrape tokens
(C<GPFORUM_METRICS_TOKEN>, comma-separated C<GPFORUM_METRICS_TOKENS>),
and mail delivery (C<GPFORUM_MAIL_TRANSPORT>, C<GPFORUM_MAIL_FROM>,
and optional SMTP host, port, credentials, and TLS). Development defaults to
the C<log> transport, which writes each message to the log; test to C<test>;
staging and production to C<sendmail>, and they refuse C<log>. Upload
scanning (C<GPFORUM_ANTIVIRUS>: C<clamd>, C<command> or C<none>, with
C<GPFORUM_ANTIVIRUS_SOCKET>, C<GPFORUM_ANTIVIRUS_COMMAND> and
C<GPFORUM_ANTIVIRUS_TIMEOUT_SECONDS>) defaults to C<clamd> in staging and
production and C<none> elsewhere. Staging and production reject the
development session secret in both the current secret and
C<GPFORUM_SESSION_SECRETS>, and require a non-empty C<GPFORUM_METRICS_TOKEN>
so the C</metrics> scrape endpoint is never left unauthenticated.

C<GPFORUM_ENV> is one of development, staging and production (and test, the
suite's own), and a mistyped one is answered with the nearest (C<prod>:
production). The size of a node is not an environment: web processes and
the cache are sized from the host. C<GPFORUM_EVENT_RETENTION_DAYS> (365) is
how long the event log is kept. Production also requires an C<https://>
C<GPFORUM_PUBLIC_BASE_URL>, a C<GPFORUM_MAIL_FROM> that is not at
localhost and a session secret of at least 32 characters. Booleans read
C<on>/C<off>, C<yes>/C<no>, C<true>/C<false> or C<1>/C<0>.
C<GPFORUM_GLIFISTORE_URL> is optional everywhere and empty by default.

Staging and production refuse a C<GPFORUM_PUBLIC_BASE_URL> or a
C<GPFORUM_MAIL_FROM> under a name RFC 2606 keeps for examples
(C<example.com>, C<.net>, C<.org>, C<.example>, C<.invalid>): the template's
placeholders, left as copied. L</from_environment> also refuses
C<GPFORUM_MAIL_TRANSPORT=test> in production, where it would send nothing;
a configuration built with C<new> keeps C<test>, its plain default, for the
test suite.

C<GPFORUM_SMTP_TLS> is C<starttls>, C<implicit> or C<off>, and defaults to
C<implicit> when C<GPFORUM_SMTP_PORT> is 465 and to C<starttls> otherwise.
C<GPFORUM_FORUM_READ_RATE_LIMIT> is the forum pages one visitor may
read per minute, 60 by default.

Search and autocomplete run under their own C<statement_timeout>,
C<GPFORUM_SEARCH_STATEMENT_TIMEOUT_MS> (C<search_statement_timeout_ms>, 2000
by default), set for the transaction each one runs in; a search it cancels
renders degraded. Zero leaves them under
C<GPFORUM_DATABASE_STATEMENT_TIMEOUT_MS>, and a value above that one (when
it is not zero) is lowered to it: search is never given longer than every
other query. Search ranks only the newest
C<GPFORUM_SEARCH_CANDIDATE_LIMIT> matches (C<search_candidate_limit>, 1000 by
default) and the page says when it did. L</validate> refuses a negative timeout,
a search timeout above a non-zero C<database_statement_timeout_ms>, and a limit
below 1.

=head1 DEPENDENCIES

Uses L<Const::Fast>, L<DateTime::TimeZone>, L<List::Util>, L<Mojo::Base>,
L<Mojo::File>, L<GPForum::Config::Report>, L<GPForum::OS>,
L<GPForum::OS::Memory> and L<GPForum::X::Config>; L<Net::SMTP>, loaded by L</smtp_can_tls>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The configuration checks the shape of the database connection but does not
connect unless a caller asks the schema layer to do so.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
