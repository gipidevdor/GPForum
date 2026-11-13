# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Config::Settings;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# Where a node runs. test is the suite's own. The size of a node is not one
# of them: it comes from the host (automatic_web_processes,
# automatic_local_cache_max_entries).
const my @ENVIRONMENTS => qw(development test staging production);
const my @LOG_LEVELS   => qw(trace debug info warn error fatal);

# The deployed environments. They need a rotated session secret, a metrics
# token and Secure cookies, they refuse the log mail transport, and they
# default to the system's clamd and sendmail. Production, on top, needs an
# https address, a sender mail servers accept and a long session secret.
const my @DEPLOYED => qw(production staging);

const my $DEVELOPMENT_SESSION_SECRET => 'gpforum-development-secret-change-me';

# Production signs sessions with a secret at least this long: 32 characters
# of `openssl rand -hex 32` is 128 bits of it.
const my $MINIMUM_PRODUCTION_SECRET => 32;
const my $SECRET_GENERATOR          => 'openssl rand -hex 32';

# GPFORUM_WEB_PROCESSES=auto runs as many web processes as the CPUs carry.
const my $AUTOMATIC => 'auto';

# A resident clamd answers in well under a second. clamscan, run per file,
# loads its whole signature database first, which alone can take most of 30
# seconds on a small server.
const my $CLAMD_TIMEOUT   => 30;
const my $COMMAND_TIMEOUT => 120;

# The SMTP port that speaks TLS from its first byte (SMTPS); every other
# port starts in the clear and upgrades with STARTTLS.
const my $IMPLICIT_TLS_PORT => 465;

# Every setting, in the order from_environment reads them and validate checks
# them. One table drives the reading, the checks, the problems an operator is
# shown and deploy/gpforum.env.example. Each row is an attribute with its
# default, read from its variable:
#
#   section  where it belongs, as the settings page groups them
#   summary  one line an operator reads in the environment file template
#   operator 1 for the few settings every installation decides; the file
#            gpforum setup writes holds them, and the template lists them
#            first, uncommented
#   operator_when  [ setting, value ]: a decision only when that setting
#            holds that value, as the SMTP server when mail leaves by smtp;
#            the file setup writes offers it commented out
#   example  a value shown when the setting is wrong, and in the template
#   generate the command that makes a value, for a secret
#   type     text (the default), integer (digits only), boolean (on/off,
#            yes/no, true/false or 1/0, read as 1 or 0), list (comma
#            separated) or words (whitespace separated); a list's default is
#            empty
#   automatic  an integer that may be auto, which the attribute's builder
#            (automatic_NAME) works out from the host
#   check    a rule in %RULE that validate applies
#   one_of   the values validate accepts
#   within   validate refuses a value above that setting's, unless it is zero,
#            and from_environment lowers it to it
#   default_when  [ [ setting, values, default ], ... ]: the default
#            from_environment uses when a setting read before this one holds
#            one of the values; a configuration built with new keeps the plain
#            default
const my @SETTINGS => map {
    +{
        type          => 'text',
        default       => undef,
        check         => undef,
        one_of        => undef,
        within        => undef,
        default_when  => undef,
        operator      => 0,
        operator_when => undef,
        automatic     => 0,
        example       => undef,
        generate      => undef,
        %{$_},
    }
} (
    {
        name     => 'environment',
        env      => 'GPFORUM_ENV',
        default  => 'development',
        check    => 'required',
        one_of   => \@ENVIRONMENTS,
        section  => 'application',
        summary  => 'Where this node runs: development, staging or production.',
        operator => 1,
        example  => 'production',
    },
    {
        name    => 'log_level',
        env     => 'GPFORUM_LOG_LEVEL',
        default => 'info',
        check   => 'required',
        one_of  => \@LOG_LEVELS,
        section => 'application',
        summary =>
          'How much the log says: trace, debug, info, warn, error or fatal.',
    },
    {
        name    => 'log_path',
        env     => 'GPFORUM_LOG_PATH',
        default => q{},
        section => 'application',
        summary => 'A file to log to; empty logs to standard error, which'
          . q{ systemd's journal keeps.},
        example => '/var/log/gpforum/gpforum.log',
    },
    {
        name    => 'attachment_root',
        env     => 'GPFORUM_ATTACHMENT_ROOT',
        default => 'var/attachments',
        section => 'application',
        summary => 'Where uploaded files are kept; a relative path starts at'
          . ' the code directory.',
    },
    {
        name    => 'attachment_storage',
        env     => 'GPFORUM_ATTACHMENT_STORAGE',
        default => 'postgres',
        one_of  => [qw(postgres filesystem)],
        section => 'application',
        summary => 'Where new attachment bytes are stored.',
    },
    {
        name    => 'media_max_mib',
        env     => 'GPFORUM_MEDIA_MAX_MIB',
        default => 250,
        type    => 'integer',
        check   => 'media_size',
        section => 'application',
        summary => 'Maximum audio or video size in MiB (100 to 250).',
    },
    {
        name    => 'attachment_owner_max_mib',
        env     => 'GPFORUM_ATTACHMENT_OWNER_MAX_MIB',
        default => 1_024,
        type    => 'integer',
        check   => 'positive',
        section => 'application',
        summary => 'Maximum retained source upload size per member in MiB;'
          . ' deleting an attachment does not release this allowance.',
    },
    {
        name    => 'attachment_owner_max_pending',
        env     => 'GPFORUM_ATTACHMENT_OWNER_MAX_PENDING',
        default => 20,
        type    => 'integer',
        check   => 'positive',
        section => 'application',
        summary =>
          'Maximum uploads awaiting a scan or content approval per member.',
    },
    {
        name    => 'media_source_hosts',
        env     => 'GPFORUM_MEDIA_SOURCE_HOSTS',
        type    => 'words',
        section => 'application',
        summary =>
          'Exact HTTPS source hostnames approved for contributed media.',
    },
    {
        name    => 'attachment_accel_redirect',
        env     => 'GPFORUM_ATTACHMENT_ACCEL_REDIRECT',
        default => q{},
        section => 'application',
        summary => 'The internal path the proxy serves attachments from'
          . ' (X-Accel-Redirect); empty serves them from GPForum.',
        example => '/protected-attachments',
    },

    # ADR 0144: profile pictures are cropped by the image tool the system
    # installed (vipsthumbnail, or sips on macOS). The test environment
    # assumes none, so a run never depends on what the host has.
    {
        name         => 'image_tool',
        env          => 'GPFORUM_IMAGE_TOOL',
        default      => 'system',
        one_of       => [qw(system none)],
        default_when => [ [ environment => ['test'], 'none' ] ],
        section      => 'application',
        summary      => q{How profile pictures are cropped: system, the}
          . q{ system's vipsthumbnail (sips on macOS), or none, which turns}
          . q{ them off.},
    },
    {
        name    => 'default_locale',
        env     => 'GPFORUM_DEFAULT_LOCALE',
        default => 'en',
        check   => 'locale',
        section => 'application',
        summary => 'The language visitors see before they choose one,'
          . ' such as en or it.',
    },

    # The forum's own name and line, which every page, mail and notification
    # says: an installation is not called after the software it runs.
    {
        name    => 'site_name',
        env     => 'GPFORUM_SITE_NAME',
        default => 'Forum',
        check   => 'required',
        section => 'application',
        summary => 'The name of the forum, as its pages and mail say it.',
        example => 'Circolo Fotografico',
    },
    {
        name    => 'site_description',
        env     => 'GPFORUM_SITE_DESCRIPTION',
        default => q{},
        section => 'application',
        summary => 'One line under the name on the home page; empty shows'
          . ' none.',
        example => 'Photography, gear and walks around Rome.',
    },
    {
        name    => 'default_theme',
        env     => 'GPFORUM_DEFAULT_THEME',
        default => 'auto',
        one_of  => [qw(auto default dark high_contrast)],
        section => 'application',
        summary => 'The theme visitors see before they choose one: auto,'
          . ' default, dark or high_contrast.',
    },
    {
        name    => 'integration_plugins',
        env     => 'GPFORUM_INTEGRATION_PLUGINS',
        type    => 'list',
        default =>
'youtube,github,facebook,instagram,spotify,apple_music,wikipedia,mathematics,vimeo,gitlab,codeberg',
        one_of => [
            qw(none youtube github facebook instagram spotify apple_music wikipedia mathematics vimeo gitlab codeberg mastodon peertube)
        ],
        section => 'application',
        summary =>
          'Integration plugins, separated by commas; none disables all.',
        example =>
'youtube,github,facebook,instagram,spotify,apple_music,wikipedia,mathematics,vimeo,gitlab,codeberg',
    },

    {
        check   => 'integration_hosts',
        name    => 'mastodon_hosts',
        env     => 'GPFORUM_MASTODON_HOSTS',
        default => q{},
        section => 'application',
        summary =>
          'Exact Mastodon instance hostnames authorized for link cards.',
        type => 'words',
    },
    {
        check   => 'integration_hosts',
        name    => 'peertube_hosts',
        env     => 'GPFORUM_PEERTUBE_HOSTS',
        default => q{},
        section => 'application',
        summary => 'Exact PeerTube instance hostnames authorized for players.',
        type    => 'words',
    },
    {
        check   => 'discord_webhook',
        name    => 'discord_webhook',
        env     => 'GPFORUM_DISCORD_WEBHOOK',
        default => q{},
        section => 'application',
        summary =>
          'Discord incoming webhook URL; empty disables announcements.',
    },
    {
        check   => 'integration_sources',
        name    => 'syndication_sources',
        env     => 'GPFORUM_SYNDICATION_SOURCES',
        default => q{},
        section => 'application',
        summary =>
          'Exact HTTPS RSS or Atom URLs authorized for moderated imports.',
        type => 'words',
    },
    {
        check   => 'oidc_issuer',
        name    => 'oidc_issuer',
        env     => 'GPFORUM_OIDC_ISSUER',
        default => q{},
        section => 'application',
        summary =>
'Exact optional OpenID Connect issuer; empty disables external login.',
    },
    {
        check   => 'optional_websub_hub',
        name    => 'oidc_authorization_endpoint',
        env     => 'GPFORUM_OIDC_AUTHORIZATION_ENDPOINT',
        default => q{},
        section => 'application',
        summary => 'Pinned HTTPS OpenID authorization endpoint.',
    },
    {
        check   => 'optional_websub_hub',
        name    => 'oidc_token_endpoint',
        env     => 'GPFORUM_OIDC_TOKEN_ENDPOINT',
        default => q{},
        section => 'application',
        summary => 'Pinned HTTPS OpenID token endpoint.',
    },
    {
        check   => 'optional_websub_hub',
        name    => 'oidc_jwks_uri',
        env     => 'GPFORUM_OIDC_JWKS_URI',
        default => q{},
        section => 'application',
        summary => 'Pinned HTTPS OpenID signing-key endpoint.',
    },
    {
        name    => 'oidc_client_id',
        env     => 'GPFORUM_OIDC_CLIENT_ID',
        default => q{},
        section => 'application',
        summary => 'OpenID client id registered for this forum.',
    },
    {
        name    => 'oidc_client_secret',
        env     => 'GPFORUM_OIDC_CLIENT_SECRET',
        default => q{},
        section => 'application',
        summary => 'OpenID confidential client secret; never shown.',
    },
    {
        name    => 'oidc_signing_algorithm',
        env     => 'GPFORUM_OIDC_SIGNING_ALGORITHM',
        default => 'RS256',
        section => 'application',
        summary => 'Pinned OpenID signing algorithm (RS256 or ES256).',
        one_of  => [qw(RS256 ES256)],
    },

    # The IANA zone dates are shown in for visitors and for members who have
    # not chosen their own (9.3).
    {
        name    => 'default_timezone',
        env     => 'GPFORUM_DEFAULT_TIMEZONE',
        default => 'UTC',
        check   => 'timezone',
        section => 'application',
        summary => 'The IANA time zone dates are shown in until a member'
          . ' chooses one.',
        example => 'Europe/Rome',
    },
    {
        name    => 'public_base_url',
        env     => 'GPFORUM_PUBLIC_BASE_URL',
        default => 'http://127.0.0.1:3000',
        check   => 'public_url',
        section => 'application',
        summary => 'The address members reach the forum at, used in every'
          . ' link GPForum mails; https in production.',
        operator => 1,
        example  => 'https://forum.example.com',
    },

    # Who runs the forum and how to reach them, as the legal pages and
    # /.well-known/security.txt say it. Each is optional: a page names what
    # is set and says what is not. The person or body responsible for the
    # forum (GDPR art. 13(1)(a), the data controller; D.Lgs. 70/2003 art. 7
    # and Directive 2000/31/EC art. 5, the service provider).
    {
        name    => 'operator_name',
        env     => 'GPFORUM_OPERATOR_NAME',
        default => q{},
        section => 'legal',
        summary => 'The person or organisation that runs the forum, as the'
          . ' legal pages name it.',
        example => 'Associazione Circolo Fotografico Roma',
    },
    {
        name    => 'operator_address',
        env     => 'GPFORUM_OPERATOR_ADDRESS',
        default => q{},
        section => 'legal',
        summary => q{The operator's postal address.},
        example => 'Via dei Fori 1, 00184 Roma, Italia',
    },

    # The single point of contact for members and for authorities (Regulation
    # (EU) 2022/2065, arts. 11 and 12) and the controller's contact.
    {
        name    => 'operator_email',
        env     => 'GPFORUM_OPERATOR_EMAIL',
        default => q{},
        check   => 'optional_mailbox',
        section => 'legal',
        summary => 'Where members and authorities write to the operator.',
        example => 'info@forum.example.com',
    },
    {
        name    => 'operator_vat_number',
        env     => 'GPFORUM_OPERATOR_VAT_NUMBER',
        default => q{},
        section => 'legal',
        summary => 'VAT number, when the forum is run as an economic'
          . ' activity; empty shows none.',
        example => 'IT01234567890',
    },
    {
        name    => 'operator_register',
        env     => 'GPFORUM_OPERATOR_REGISTER',
        default => q{},
        section => 'legal',
        summary => 'Trade register and number, when the operator is'
          . ' entered in one; empty shows none.',
        example => 'REA RM-1234567',
    },
    {
        name    => 'privacy_officer_email',
        env     => 'GPFORUM_PRIVACY_OFFICER_EMAIL',
        default => q{},
        check   => 'optional_mailbox',
        section => 'legal',
        summary => q{The data protection officer's address, when one is}
          . ' designated (GDPR art. 37).',
        example => 'dpo@forum.example.com',
    },

    # RFC 9116's Contact: a mailto:, https: or tel: URI. Empty takes the
    # operator's address; with neither, no security.txt is served.
    {
        name    => 'security_contact',
        env     => 'GPFORUM_SECURITY_CONTACT',
        default => q{},
        check   => 'optional_contact_uri',
        section => 'legal',
        summary => 'Where to report a vulnerability, as a mailto:, https:'
          . ' or tel: URI; empty uses the operator email.',
        example => 'mailto:security@forum.example.com',
    },
    {
        name    => 'post_signing_key',
        env     => 'GPFORUM_POST_SIGNING_KEY',
        default => 'var/keys/post-signing.pem',
        section => 'security',
        summary =>
'Private Ed25519 PEM path, shared by workers and preserved across upgrades.',
    },
    {
        name    => 'mail_reply_address',
        env     => 'GPFORUM_MAIL_REPLY_ADDRESS',
        default => q{},
        check   => 'optional_mail_reply',
        section => 'mail',
        summary =>
'Local MTA address delivered to gpforum mail-in; empty disables replies by email.',
    },
    {
        name    => 'push_enabled',
        env     => 'GPFORUM_PUSH_ENABLED',
        default => 0,
        type    => 'boolean',
        section => 'application',
        summary =>
          'Enable opt-in encrypted Web Push and its independent worker.',
    },
    {
        name    => 'push_concurrency',
        env     => 'GPFORUM_PUSH_CONCURRENCY',
        default => 8,
        type    => 'integer',
        check   => 'positive',
        section => 'application',
        summary => 'Maximum simultaneous Push sends per worker, capped at 64.',
    },
    {
        name    => 'push_per_provider',
        env     => 'GPFORUM_PUSH_PER_PROVIDER',
        default => 2,
        type    => 'integer',
        check   => 'positive',
        section => 'application',
        summary =>
'Maximum simultaneous sends to one provider hostname per worker, capped at 16.',
    },
    {
        name    => 'push_key_directory',
        env     => 'GPFORUM_PUSH_KEY_DIRECTORY',
        default => 'var/keys/web-push',
        section => 'security',
        summary =>
'Public and private Web Push key-ring directory; private files require mode 0600.',
    },
    {
        name    => 'push_contact',
        env     => 'GPFORUM_PUSH_CONTACT',
        default => q{},
        section => 'application',
        summary =>
'VAPID operator contact URI (mailto: or https:), required when Push is enabled.',
    },
    {
        name    => 'push_providers',
        env     => 'GPFORUM_PUSH_PROVIDERS',
        default =>
'fcm.googleapis.com updates.push.services.mozilla.com *.push.apple.com *.notify.windows.com',
        type    => 'words',
        section => 'security',
        summary =>
'Approved Push provider hostnames; *. matches subdomains at a DNS label boundary.',
    },
    {
        name    => 'websub_hub_url',
        env     => 'GPFORUM_WEBSUB_HUB_URL',
        default => q{},
        check   => 'optional_websub_hub',
        section => 'application',
        summary =>
'Trusted HTTPS WebSub hub managing callback verification, leases and delivery.',
    },
    {
        name    => 'session_secret',
        env     => 'GPFORUM_SESSION_SECRET',
        default => $DEVELOPMENT_SESSION_SECRET,
        check   => 'session_secret',
        section => 'security',
        summary => 'Signs session cookies: a long random string, at least'
          . " $MINIMUM_PRODUCTION_SECRET characters in production.",
        operator => 1,
        generate => $SECRET_GENERATOR,
    },
    {
        name    => 'previous_session_secrets',
        env     => 'GPFORUM_SESSION_SECRETS',
        type    => 'list',
        check   => 'previous_secrets',
        section => 'security',
        summary => 'Earlier session secrets, comma separated, still accepted'
          . ' while a new one rolls out.',
    },
    {
        name    => 'database_dsn',
        env     => 'GPFORUM_DATABASE_DSN',
        default => 'dbi:Pg:dbname=gpforum',
        check   => 'required',
        section => 'database',
        summary => 'The PostgreSQL database, as a DBI data source; without'
          . ' host it uses the local Unix socket.',
        operator => 1,
    },
    {
        name     => 'database_user',
        env      => 'GPFORUM_DATABASE_USER',
        default  => 'gpforum',
        check    => 'required',
        section  => 'database',
        summary  => 'The PostgreSQL role GPForum connects as.',
        operator => 1,
    },
    {
        name    => 'database_password',
        env     => 'GPFORUM_DATABASE_PASSWORD',
        default => q{},
        section => 'database',
        summary => q{That role's password; empty when PostgreSQL trusts the}
          . ' connection or ~/.pgpass holds it.',
        operator => 1,
    },
    {
        name    => 'admin_database_dsn',
        env     => 'GPFORUM_ADMIN_DATABASE_DSN',
        default => undef,
        section => 'database',
        summary =>
'Administrative PostgreSQL connection for API-role provisioning; keep it outside the web service environment.',
    },
    {
        name    => 'admin_database_user',
        env     => 'GPFORUM_ADMIN_DATABASE_USER',
        default => undef,
        section => 'database',
        summary =>
'Administrative PostgreSQL role; set it only in the separate operator environment.',
    },
    {
        name    => 'admin_database_password',
        env     => 'GPFORUM_ADMIN_DATABASE_PASSWORD',
        default => undef,
        section => 'database',
        summary =>
'Administrative role password; keep it in the administrator environment or pgpass.',
    },
    {
        name    => 'database_statement_timeout_ms',
        env     => 'GPFORUM_DATABASE_STATEMENT_TIMEOUT_MS',
        default => 15_000,
        type    => 'integer',
        check   => 'non_negative',
        section => 'database',
        summary => 'Milliseconds a query may run before PostgreSQL cancels it;'
          . ' 0 means no limit.',
    },
    {
        name    => 'postgres_profile',
        env     => 'GPFORUM_POSTGRES_PROFILE',
        default => 'shared',
        one_of  => [qw(shared dedicated)],
        section => 'database',
        summary =>
          'PostgreSQL memory profile: shared host or dedicated server.',
    },
    {
        name    => 'postgres_strict',
        env     => 'GPFORUM_POSTGRES_STRICT',
        default => 0,
        type    => 'boolean',
        section => 'database',
        summary =>
'Refuse nonconforming PostgreSQL connections when explicitly enabled.',
    },
    {
        name    => 'postgres_topology',
        env     => 'GPFORUM_POSTGRES_TOPOLOGY',
        default => 'auto',
        one_of  => [qw(auto local remote managed)],
        section => 'database',
        summary => 'Database location; declare managed services explicitly.',
    },
    {
        name    => 'postgres_memory_mb',
        env     => 'GPFORUM_POSTGRES_MEMORY_MB',
        default => 0,
        type    => 'integer',
        check   => 'non_negative',
        section => 'database',
        summary =>
'Database host or container RAM in MiB; 0 detects only for declared local servers.',
    },
    {
        name    => 'postgres_reserve_mb',
        env     => 'GPFORUM_POSTGRES_RESERVE_MB',
        default => 0,
        type    => 'integer',
        check   => 'non_negative',
        section => 'database',
        summary =>
'RAM reserved for OS, GPForum and other services; 0 reserves half on shared hosts.',
    },
    {
        name    => 'postgres_cpu_count',
        env     => 'GPFORUM_POSTGRES_CPU_COUNT',
        default => 0,
        type    => 'integer',
        check   => 'non_negative',
        section => 'database',
        summary =>
          'Database CPU cores; 0 detects only for declared local servers.',
    },
    {
        name    => 'postgres_storage',
        env     => 'GPFORUM_POSTGRES_STORAGE',
        default => 'unknown',
        one_of  => [qw(unknown hdd ssd nvme)],
        section => 'database',
        summary =>
          'Database storage class; unknown uses conservative planner costs.',
    },
    {
        name    => 'database_idle_in_transaction_timeout_ms',
        env     => 'GPFORUM_DATABASE_IDLE_IN_TRANSACTION_TIMEOUT_MS',
        default => 10_000,
        type    => 'integer',
        check   => 'non_negative',
        section => 'database',
        summary => 'Milliseconds a transaction may sit idle before PostgreSQL'
          . ' ends it; 0 means no limit.',
    },
    {
        name    => 'database_lock_timeout_ms',
        env     => 'GPFORUM_DATABASE_LOCK_TIMEOUT_MS',
        default => 3_000,
        type    => 'integer',
        check   => 'non_negative',
        section => 'database',
        summary => 'Milliseconds a statement waits for a lock; 0 means no'
          . ' limit.',
    },

    # Search's own budget (8.10). A search holds a web worker for as long as
    # the database takes, and there are few workers, so it is cut off well
    # before the statement_timeout every other query gets; the page then says
    # search is degraded. An operator who lowered
    # GPFORUM_DATABASE_STATEMENT_TIMEOUT_MS below it -- to shed load, say --
    # would have given search more time than anything else, so it is held to
    # the connection's. Zero there is no timeout at all, and zero for search
    # already means the connection's: both are left as they are. Search ranks
    # only the newest search_candidate_limit matches, so a word most documents
    # hold costs the same on any forum size.
    {
        name    => 'search_statement_timeout_ms',
        env     => 'GPFORUM_SEARCH_STATEMENT_TIMEOUT_MS',
        default => 2_000,
        type    => 'integer',
        check   => 'non_negative',
        within  => 'database_statement_timeout_ms',
        section => 'search',
        summary => q{Milliseconds a search may run, at most the database's}
          . ' limit; 0 uses that limit.',
    },
    {
        name    => 'search_candidate_limit',
        env     => 'GPFORUM_SEARCH_CANDIDATE_LIMIT',
        default => 1_000,
        type    => 'integer',
        check   => 'positive',
        section => 'search',
        summary => 'How many of the newest matches a search ranks.',
    },

    {
        name    => 'search_embedding_model_path',
        env     => 'GPFORUM_SEARCH_EMBEDDING_MODEL_PATH',
        default => q{},
        type    => 'string',
        section => 'search',
        summary =>
'Local Sentence Transformers model directory; empty disables semantic search.',
    },
    {
        name    => 'search_embedding_model_key',
        env     => 'GPFORUM_SEARCH_EMBEDDING_MODEL_KEY',
        default => 'multilingual-minilm-l12-v2',
        type    => 'string',
        section => 'search',
        summary =>
'Embedding model and preprocessing identity; change when weights change.',
    },
    {
        name    => 'search_embedding_python',
        env     => 'GPFORUM_SEARCH_EMBEDDING_PYTHON',
        default => 'python3',
        type    => 'string',
        section => 'search',
        summary => 'Python executable with Sentence Transformers installed.',
    },
    {
        name    => 'search_embedding_timeout_seconds',
        env     => 'GPFORUM_SEARCH_EMBEDDING_TIMEOUT_SECONDS',
        default => 5,
        type    => 'integer',
        check   => 'positive',
        section => 'search',
        summary =>
'Maximum seconds for local embedding inference, including model startup.',
    },

    # auto, the default, is worked out from the host by
    # automatic_web_processes; a number is taken as it is.
    {
        name      => 'web_processes',
        env       => 'GPFORUM_WEB_PROCESSES',
        default   => $AUTOMATIC,
        type      => 'integer',
        automatic => 1,
        check     => 'process_count',
        section   => 'processes',
        summary   => 'Web processes; auto runs as many as the CPUs carry.',
    },
    {
        name    => 'runtime_listen',
        env     => 'GPFORUM_RUNTIME_LISTEN',
        default => 'http+unix://var%2Frun%2Fgpforum.sock',
        check   => 'listen',
        section => 'processes',
        summary => 'Where Hypnotoad listens, comma separated; the default'
          . ' Unix socket is var/run/gpforum.sock under the code directory.',
    },
    {
        name    => 'runtime_pid_file',
        env     => 'GPFORUM_RUNTIME_PID_FILE',
        default => 'hypnotoad.pid',
        check   => 'required',
        section => 'processes',
        summary => q{Hypnotoad's pid file; a relative path starts at the}
          . ' runtime directory systemd makes, or the code directory.',
    },
    {
        name    => 'runtime_worker_policy',
        env     => 'GPFORUM_RUNTIME_WORKER_POLICY',
        default => 'cap-to-cpu',
        one_of  => [qw(configured cap-to-cpu)],
        section => 'processes',
        summary => 'configured runs the web processes as set; cap-to-cpu'
          . ' holds them to what the CPUs carry.',
    },
    {
        name    => 'runtime_max_web_per_cpu',
        env     => 'GPFORUM_RUNTIME_MAX_WEB_PER_CPU',
        default => 2,
        type    => 'integer',
        check   => 'positive',
        section => 'processes',
        summary => 'Web processes per CPU that auto and cap-to-cpu allow.',
    },
    {
        name    => 'runtime_backlog',
        env     => 'GPFORUM_RUNTIME_BACKLOG',
        default => 256,
        type    => 'integer',
        check   => 'positive',
        section => 'processes',
        summary => 'Connections the kernel queues before the web server'
          . ' accepts them.',
    },
    {
        name    => 'runtime_clients',
        env     => 'GPFORUM_RUNTIME_CLIENTS',
        default => 250,
        type    => 'integer',
        check   => 'positive',
        section => 'processes',
        summary => 'Connections each web process serves at once.',
    },
    {
        name    => 'runtime_requests',
        env     => 'GPFORUM_RUNTIME_REQUESTS',
        default => 1_000,
        type    => 'integer',
        check   => 'positive',
        section => 'processes',
        summary => 'Requests one keep-alive connection serves before it is'
          . ' closed.',
    },
    {
        name    => 'runtime_keep_alive',
        env     => 'GPFORUM_RUNTIME_KEEP_ALIVE_TIMEOUT',
        default => 5,
        type    => 'integer',
        check   => 'positive',
        section => 'processes',
        summary => 'Seconds an idle keep-alive connection stays open.',
    },
    {
        name    => 'runtime_inactivity',
        env     => 'GPFORUM_RUNTIME_INACTIVITY_TIMEOUT',
        default => 30,
        type    => 'integer',
        check   => 'positive',
        section => 'processes',
        summary => 'Seconds a connection may stay silent before it is closed.',
    },
    {
        name    => 'runtime_graceful_timeout',
        env     => 'GPFORUM_RUNTIME_GRACEFUL_TIMEOUT',
        default => 20,
        type    => 'integer',
        check   => 'positive',
        section => 'processes',
        summary => 'Seconds a stopping web process has to finish its requests.',
    },
    {
        name    => 'runtime_heartbeat_interval',
        env     => 'GPFORUM_RUNTIME_HEARTBEAT_INTERVAL',
        default => 5,
        type    => 'integer',
        check   => 'positive',
        section => 'processes',
        summary => q{Seconds between a web process's heartbeats.},
    },
    {
        name    => 'runtime_heartbeat_timeout',
        env     => 'GPFORUM_RUNTIME_HEARTBEAT_TIMEOUT',
        default => 5,
        type    => 'integer',
        check   => 'positive',
        section => 'processes',
        summary => 'Seconds without a heartbeat before a web process is'
          . ' replaced.',
    },
    {
        name    => 'runtime_upgrade_timeout',
        env     => 'GPFORUM_RUNTIME_UPGRADE_TIMEOUT',
        default => 60,
        type    => 'integer',
        check   => 'positive',
        section => 'processes',
        summary => 'Seconds a zero-downtime upgrade waits for the new'
          . ' processes.',
    },
    {
        name    => 'runtime_spare_processes',
        env     => 'GPFORUM_RUNTIME_SPARE_PROCESSES',
        default => 1,
        type    => 'integer',
        check   => 'positive',
        section => 'processes',
        summary => 'Extra web processes started ahead of need during a'
          . ' graceful restart.',
    },
    {
        name    => 'runtime_proxy',
        env     => 'GPFORUM_RUNTIME_PROXY',
        default => 1,
        type    => 'boolean',
        check   => 'boolean',
        section => 'processes',
        summary => 'A reverse proxy is in front (on or off); on believes its'
          . ' X-Forwarded-For.',
    },
    {
        name    => 'runtime_trusted_proxies',
        env     => 'GPFORUM_RUNTIME_TRUSTED_PROXIES',
        default => '127.0.0.1,::1',
        check   => 'trusted_when_proxied',
        section => 'processes',
        summary => 'The proxies whose X-Forwarded-For is believed, comma'
          . ' separated; the shipped proxies run on this host.',
        example => '10.0.0.5',
    },
    {
        name    => 'os_reuseport',
        env     => 'GPFORUM_OS_REUSEPORT',
        default => 'auto',
        one_of  => [qw(auto on off)],
        section => 'operating_system',
        summary => 'SO_REUSEPORT on the listen socket: auto, on or off.',
    },
    {
        name    => 'os_min_recommended_workers',
        env     => 'GPFORUM_OS_MIN_RECOMMENDED_WORKERS',
        default => 2,
        type    => 'integer',
        check   => 'positive',
        section => 'operating_system',
        summary => 'The worker count below which the host preflight warns.',
    },
    {
        name    => 'os_max_open_file_descriptors',
        env     => 'GPFORUM_OS_MAX_OPEN_FILE_DESCRIPTORS',
        default => 65_536,
        type    => 'integer',
        check   => 'positive',
        section => 'operating_system',
        summary => 'The open-file limit the host preflight expects.',
    },

    # auto, the default, is sized from the host's memory by
    # automatic_local_cache_max_entries.
    {
        name      => 'local_cache_max_entries',
        env       => 'GPFORUM_LOCAL_CACHE_MAX_ENTRIES',
        default   => $AUTOMATIC,
        type      => 'integer',
        automatic => 1,
        check     => 'positive',
        section   => 'cache',
        summary   => 'Entries each web process keeps in its own cache; auto'
          . q{ sizes them from the host's memory.},
    },
    {
        name    => 'category_cache_ttl_seconds',
        env     => 'GPFORUM_CATEGORY_CACHE_TTL_SECONDS',
        default => 60,
        type    => 'integer',
        check   => 'positive',
        section => 'cache',
        summary => 'Seconds a cached category list is kept.',
    },
    {
        name    => 'realtime_listener_enabled',
        env     => 'GPFORUM_REALTIME_LISTENER_ENABLED',
        default => 1,
        type    => 'boolean',
        check   => 'boolean',
        section => 'realtime',
        summary => 'Internal: live updates through PostgreSQL LISTEN; leave'
          . ' it on.',
    },
    {
        name    => 'realtime_listener_poll_interval_seconds',
        env     => 'GPFORUM_REALTIME_LISTENER_POLL_INTERVAL_SECONDS',
        default => 1,
        type    => 'integer',
        check   => 'positive',
        section => 'realtime',
        summary => 'Seconds between checks for live-update notifications.',
    },
    {
        name    => 'realtime_listener_reconnect_backoff_seconds',
        env     => 'GPFORUM_REALTIME_LISTENER_RECONNECT_BACKOFF_SECONDS',
        default => 5,
        type    => 'integer',
        check   => 'positive',
        section => 'realtime',
        summary => 'Seconds before the live-update listener reconnects.',
    },
    {
        name    => 'realtime_listener_heartbeat_interval_seconds',
        env     => 'GPFORUM_REALTIME_LISTENER_HEARTBEAT_INTERVAL_SECONDS',
        default => 30,
        type    => 'integer',
        check   => 'positive',
        section => 'realtime',
        summary => 'Seconds between live-update heartbeats.',
    },
    {
        name    => 'warmup_enabled',
        env     => 'GPFORUM_WARMUP_ENABLED',
        default => 1,
        type    => 'boolean',
        check   => 'boolean',
        section => 'processes',
        summary => 'Render the main pages once before the workers fork, so'
          . ' their first requests are as fast as the rest (on or off).',
    },
    {
        name    => 'minion_enabled',
        env     => 'GPFORUM_MINION_ENABLED',
        default => 0,
        type    => 'boolean',
        check   => 'boolean',
        section => 'jobs',
        summary => 'Also run background jobs through Minion (on or off); the'
          . ' outbox worker needs no Minion.',
    },
    {
        name    => 'minion_pg_url',
        env     => 'GPFORUM_MINION_PG_URL',
        default => q{},
        check   => 'required_by_minion',
        section => 'jobs',
        summary => q{Minion's PostgreSQL URL, required while Minion is on.},
        example => 'postgresql://gpforum@/gpforum',
    },

    # How long the event log is kept: the partitions job lists each monthly
    # partition older than this as due to detach.
    {
        name    => 'event_retention_days',
        env     => 'GPFORUM_EVENT_RETENTION_DAYS',
        default => 365,
        type    => 'integer',
        check   => 'positive',
        section => 'jobs',
        summary => 'Days the event log is kept before its monthly partitions'
          . ' are listed as due to detach.',
    },
    {
        name    => 'metrics_token',
        env     => 'GPFORUM_METRICS_TOKEN',
        default => q{},
        check   => 'metrics_token',
        section => 'security',
        summary => 'The token /metrics and the full /health/ready report ask'
          . ' for; required in staging and production.',
        operator => 1,
        generate => $SECRET_GENERATOR,
    },
    {
        name    => 'previous_metrics_tokens',
        env     => 'GPFORUM_METRICS_TOKENS',
        type    => 'list',
        section => 'security',
        summary => 'Earlier metrics tokens, comma separated, still accepted'
          . ' while scrapers move to the new one.',
    },

    # ADR 0142: the key two-step sign-in secrets are sealed with. Empty in
    # development uses a fixed development key; empty where the forum is
    # deployed leaves two-step sign-in off until one is set.
    {
        name    => 'second_factor_key',
        env     => 'GPFORUM_SECOND_FACTOR_KEY',
        default => q{},
        check   => 'second_factor_key',
        section => 'security',
        summary => 'Seals two-step sign-in secrets: a long random string;'
          . ' without one, deployed forums offer no two-step sign-in.',
        generate => $SECRET_GENERATOR,
    },
    {
        name    => 'previous_second_factor_keys',
        env     => 'GPFORUM_SECOND_FACTOR_KEYS',
        type    => 'list',
        section => 'security',
        summary => 'Earlier two-step sign-in keys, comma separated, still'
          . ' opening the secrets they sealed.',
    },

    # Optional everywhere (D2): without one each process keeps its own cache,
    # which is all a single host needs.
    {
        name    => 'glifistore_url',
        env     => 'GPFORUM_GLIFISTORE_URL',
        default => q{},
        check   => 'glifistore',
        section => 'cache',
        summary => 'A GlifiStore shared cache; empty keeps each process to its'
          . ' own cache, which suits one host.',
        example => 'unix://var/run/glifistore.sock',
    },
    {
        name    => 'session_touch_interval_seconds',
        env     => 'GPFORUM_SESSION_TOUCH_INTERVAL_SECONDS',
        default => 300,
        type    => 'integer',
        check   => 'positive',
        section => 'security',
        summary => q{How often, at most, a signed-in member's session is}
          . ' marked as used.',
    },

    # Forum pages are read through a rate limit per visitor -- a member, or
    # an address -- so one client cannot read the whole forum in a loop. A
    # capacity run from one address raises it for its window (stress-load.md).
    {
        name    => 'forum_read_rate_limit',
        env     => 'GPFORUM_FORUM_READ_RATE_LIMIT',
        default => 60,
        type    => 'integer',
        check   => 'positive',
        section => 'security',
        summary => 'Forum pages one visitor may read per minute; raise it only'
          . ' for a load test from one address.',
    },

    {
        name    => 'password_memory_mib',
        env     => 'GPFORUM_PASSWORD_MEMORY_MIB',
        default => 32,
        type    => 'integer',
        check   => 'password_cost',
        section => 'security',
        summary =>
'Argon2id memory in MiB (19..256); doctor --calibrate-password measures this host.',
    },
    {
        name    => 'password_iterations',
        env     => 'GPFORUM_PASSWORD_ITERATIONS',
        default => 3,
        type    => 'integer',
        check   => 'password_cost',
        section => 'security',
        summary => 'Argon2id iterations (2..10).',
    },

    # log writes each message, link included, to the log: development's
    # default, so a laptop without a mail server can still verify an account.
    # test keeps messages in memory for the test suite.
    {
        name         => 'mail_transport',
        env          => 'GPFORUM_MAIL_TRANSPORT',
        default      => 'test',
        check        => 'mail_transport',
        one_of       => [qw(sendmail smtp log test)],
        default_when => [
            [ environment => \@DEPLOYED,      'sendmail' ],
            [ environment => ['development'], 'log' ],
        ],
        section => 'mail',
        summary => 'How mail leaves: sendmail (the local mail server), smtp,'
          . ' or log (development only: writes it to the log).',
        operator => 1,
        example  => 'sendmail',
    },
    {
        name    => 'mail_from',
        env     => 'GPFORUM_MAIL_FROM',
        default => 'noreply@localhost',
        check   => 'mail_from',
        section => 'mail',
        summary => 'The sender of every message: an address at the forum'
          . q{'s own domain.},
        operator => 1,
        example  => 'forum@forum.example.com',
    },
    {
        name    => 'dkim_domain',
        env     => 'GPFORUM_DKIM_DOMAIN',
        default => q{},
        section => 'mail',
        summary => 'DKIM signing domain, matching the sender domain.',
    },
    {
        name    => 'dkim_selector',
        env     => 'GPFORUM_DKIM_SELECTOR',
        default => 'forum',
        section => 'mail',
        summary => 'DKIM DNS selector.',
    },
    {
        name    => 'dkim_key_file',
        env     => 'GPFORUM_DKIM_KEY_FILE',
        default => q{},
        section => 'mail',
        summary =>
          'Private RSA key file (0600); empty leaves signing to the MTA.',
    },
    {
        name          => 'smtp_host',
        env           => 'GPFORUM_SMTP_HOST',
        default       => q{},
        check         => 'smtp_host',
        section       => 'mail',
        summary       => 'The SMTP server, when mail leaves by smtp.',
        example       => 'smtp.example.com',
        operator_when => [ mail_transport => 'smtp' ],
    },
    {
        name          => 'smtp_port',
        env           => 'GPFORUM_SMTP_PORT',
        default       => 587,
        type          => 'integer',
        check         => 'positive',
        section       => 'mail',
        summary       => 'The SMTP port; 587 is the submission port.',
        operator_when => [ mail_transport => 'smtp' ],
    },
    {
        name          => 'smtp_username',
        env           => 'GPFORUM_SMTP_USERNAME',
        default       => q{},
        section       => 'mail',
        summary       => 'The SMTP login, when the server asks for one.',
        operator_when => [ mail_transport => 'smtp' ],
    },
    {
        name          => 'smtp_password',
        env           => 'GPFORUM_SMTP_PASSWORD',
        default       => q{},
        section       => 'mail',
        summary       => 'The SMTP password.',
        operator_when => [ mail_transport => 'smtp' ],
    },

    # TLS follows the port unless the operator says otherwise: STARTTLS on
    # 587, the submission port, implicit TLS on 465.
    {
        name         => 'smtp_tls',
        env          => 'GPFORUM_SMTP_TLS',
        default      => 'starttls',
        one_of       => [qw(starttls implicit off)],
        default_when => [ [ smtp_port => [$IMPLICIT_TLS_PORT], 'implicit' ] ],
        section      => 'mail',
        summary      => 'TLS to the SMTP server: starttls, implicit or off; it'
          . ' follows the port, starttls on 587 and implicit on 465.',
    },

    # The free antivirus the operating system installed (ADR 0108): clamd, a
    # command, or none. The socket defaults to the one the OS package
    # declares. Deployed profiles scan uploads with the system's clamd unless
    # the operator says otherwise; development and test do not assume one is
    # installed.
    {
        name         => 'antivirus',
        env          => 'GPFORUM_ANTIVIRUS',
        default      => 'none',
        one_of       => [qw(clamd command none)],
        default_when => [ [ environment => \@DEPLOYED, 'clamd' ] ],
        section      => 'antivirus',
        summary      => 'How uploads are scanned: clamd, command or none.',
        operator     => 1,
        example      => 'clamd',
    },
    {
        name    => 'antivirus_socket',
        env     => 'GPFORUM_ANTIVIRUS_SOCKET',
        default => q{},
        section => 'antivirus',
        summary => q{The clamd socket; empty uses the one the system's package}
          . ' installs.',
        example => '/var/run/clamav/clamd.ctl',
    },
    {
        name    => 'antivirus_command',
        env     => 'GPFORUM_ANTIVIRUS_COMMAND',
        type    => 'words',
        check   => 'command_for_antivirus',
        section => 'antivirus',
        summary => 'The scanner run on each upload when the antivirus is'
          . ' command.',
        example => 'clamscan --no-summary',
    },
    {
        name         => 'antivirus_timeout_seconds',
        env          => 'GPFORUM_ANTIVIRUS_TIMEOUT_SECONDS',
        default      => $CLAMD_TIMEOUT,
        type         => 'integer',
        check        => 'positive',
        default_when => [ [ antivirus => ['command'], $COMMAND_TIMEOUT ] ],
        section      => 'antivirus',
        summary      => 'Seconds a scan may take.',
    },
);

# Every row, defaults filled in, read-only.
sub rows ($class) {
    return \@SETTINGS;
}

sub deployed_environments ($class) {
    return @DEPLOYED;
}

sub development_session_secret ($class) {
    return $DEVELOPMENT_SESSION_SECRET;
}

sub minimum_production_secret ($class) {
    return $MINIMUM_PRODUCTION_SECRET;
}

sub automatic_word ($class) {
    return $AUTOMATIC;
}

1;

__END__

=head1 NAME

GPForum::Config::Settings - The table of every GPForum setting.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $rows = GPForum::Config::Settings->rows;

=head1 DESCRIPTION

The data L<GPForum::Config> reads from: one row for each setting, with its
environment variable, default, type, section, summary, rule name and example.
The row fields are described in the comment above the table in this file's
source. L<GPForum::Config> owns the reading, the rules that check a value and
the problems an operator is shown; this module owns only what the settings
are.

=head1 SUBROUTINES/METHODS

=head2 rows

The array reference of rows, in the order L<GPForum::Config> reads them. Each
row is read-only; copy before changing.

=head2 deployed_environments

The environments that count as deployed: production and staging.

=head2 development_session_secret

The session secret a development node uses when none is given.

=head2 minimum_production_secret

The shortest session secret production accepts, in characters.

=head2 automatic_word

The word that asks for a value worked out from the host: C<auto>.

=head1 DIAGNOSTICS

None of its own.

=head1 CONFIGURATION AND ENVIRONMENT

None: it names the variables, it does not read them.

=head1 DEPENDENCIES

Const::Fast.

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
