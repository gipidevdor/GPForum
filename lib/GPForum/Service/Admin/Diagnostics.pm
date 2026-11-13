# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Admin::Diagnostics;

use Const::Fast;
use Scalar::Util qw(blessed);
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::AsyncWork;
use GPForum::Infrastructure::SqlFunction;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Service::Admin::AuditReview;
use GPForum::Service::Admin::ConsoleReader;
use GPForum::Service::Admin::Settings;
use GPForum::Service::Clock;
use GPForum::Service::Identity::Mailer;
use GPForum::Service::Operations::AntivirusCheck;
use GPForum::Service::Operations::EvidenceMeta qw(evidence_scrub_structure);
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $SCHEMA_VERSION   => 1;
const my $MAIL_ACTION      => 'admin.mail_test_sent';
const my $ANTIVIRUS_ACTION => 'admin.antivirus_checked';
const my $MAX_ERROR_LENGTH => 500;
const my $RECIPIENT        => '[recipient]';

# The send runs inside a web request, and Hypnotoad restarts a worker that
# sends no heartbeat for heartbeat_interval + heartbeat_timeout -- ten
# seconds as shipped. Email::Sender waits 120 seconds on each SMTP step by
# default; five lets one stalled step fail, and be reported, in time.
const my $SMTP_TIMEOUT_SECONDS => 5;

# Both checks run inside their command's transaction, which sits idle while
# the SMTP server or clamd answers. PostgreSQL ends a transaction idle for
# database_idle_in_transaction_timeout_ms -- ten seconds as shipped -- and
# the audit row goes with it: a stalled clamd takes three seconds on each of
# the check's four calls, twelve in all, and the console then had nothing to
# show for the check meant to find it. This transaction alone is allowed a
# minute, longer than either check can wait; SET LOCAL ends with it.
const my $SLOW_ANSWER_IDLE_MS => 60_000;

has accounts => sub ($self) {
    return GPForum::Service::Admin::ConsoleReader->new(
        schema => $self->schema );
};

# The scanner the application scans uploads with, or undef when scanning is
# off (GPForum::Infrastructure::Antivirus->from_config).
has antivirus    => undef;         # optional: the configured engine is reported
has audit_review => sub ($self) {
    return GPForum::Service::Admin::AuditReview->new( schema => $self->schema );
};
has clock => sub { return GPForum::Service::Clock->new; };
__PACKAGE__->requires(qw(config));
has id_service => sub { return GPForum::Infrastructure::Id->new; };
has mailer     => sub ($self) {
    return GPForum::Service::Identity::Mailer->new(
        config       => $self->config,
        smtp_timeout => $SMTP_TIMEOUT_SECONDS,
    );
};
has recorder => \&GPForum::Infrastructure::EventRecorder::for_service;
has schema   => undef;       # optional: the defaults and the call layer read it
has settings => sub ($self) {
    return GPForum::Service::Admin::Settings->new( config => $self->config );
};

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each operation is written once, as its promise method (ADR 0177); the
# address and audit readers it awaits block with it.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(overview send_test_mail check_antivirus));
GPForum::Infrastructure::SqlFunction->blocking_parts(qw(accounts audit_review));

# What the settings page shows beside its two buttons: where a test message
# would go, how mail and scanning are configured, and the last audited
# result of each. The three reads are sent before the first is awaited, so
# on pooled connections they run together.
async sub overview_p ( $self, $user_id, $context = undef ) {
    my $antivirus = $self->_latest_p( $ANTIVIRUS_ACTION, $context );
    my $mail      = $self->_latest_p( $MAIL_ACTION,      $context );
    my $recipient = $self->accounts->email_of_p( $user_id, $context );
    return $self->_overview( await $antivirus, await $mail, await $recipient );
}

sub _overview ( $self, $antivirus, $mail, $recipient ) {
    return {
        antivirus => {
            engine     => $self->config->antivirus,
            in_request => $self->_scans_in_request,
            latest     => $antivirus,
        },
        mail => {
            latest    => $mail,
            recipient => $recipient,
            transport => $self->config->mail_transport,
        },
    };
}

# 6.5: the console's gpforum mail-check. One message, to the signed-in
# administrator's own address and never to one the request names -- the
# console must not become a relay -- and the outcome audited either way:
# inside the caller's transaction ($scope) when given. The SMTP exchange
# runs in a CPU-only child that never touches PostgreSQL.
async sub send_test_mail_p ( $self, $input, $context = undef, $scope = undef ) {
    my $functions     = $scope // $self->_functions;
    my $actor_user_id = $input->{actor_user_id};
    my $to = await $self->accounts->email_of_p( $actor_user_id, $context );
    my $outcome =
      ( defined $to && length $to )
      ? await $self->_slowly_p( $functions,
        sub { return $self->_send($to); }, $context )
      : _no_address();
    my $result = { %{$outcome}, transport => $self->config->mail_transport };
    await $self->_audit_p( $functions, _mail_audit( $actor_user_id, $result ),
        $context );

    return $result;
}

sub _no_address {
    return {
        error   => 'this account has no email address',
        outcome => 'failed'
    };
}

# The recipient is the actor, so the audit row names them as its target
# instead of copying their address into the log; the result, which the
# command log keeps as the command's answer, leaves it out for the same
# reason.
sub _mail_audit ( $actor_user_id, $result ) {
    return {
        action        => $MAIL_ACTION,
        actor_user_id => $actor_user_id,
        metadata      => {
            (
                defined $result->{error}
                ? ( error => $result->{error} )
                : ()
            ),
            outcome   => $result->{outcome},
            transport => $result->{transport},
            via       => 'web',
        },
        target_id   => $actor_user_id,
        target_type => 'user',
    };
}

# 6.5: the console's gpforum antivirus-check, audited with its report: the
# scan in a CPU-only child that never touches PostgreSQL, its audit row
# inside the caller's transaction ($scope) when given.
async sub check_antivirus_p ( $self, $input, $context = undef, $scope = undef )
{
    my $functions = $scope // $self->_functions;
    my $report    = await $self->_slowly_p( $functions,
        sub { return $self->_scrubbed_report; }, $context );
    await $self->_audit_p( $functions,
        $self->_antivirus_audit( $input, $report ), $context );

    return $report;
}

sub _scrubbed_report ($self) {
    return evidence_scrub_structure( $self->_antivirus_report,
        $self->settings->secret_values );
}

sub _antivirus_audit ( $self, $input, $report ) {
    my $correlation_id = $self->id_service->uuid;
    return {
        action         => $ANTIVIRUS_ACTION,
        actor_user_id  => $input->{actor_user_id},
        correlation_id => $correlation_id,
        metadata       => { %{$report}, via => 'web' },
        target_id      => $correlation_id,
        target_type    => 'antivirus',
    };
}

# Work that waits on another server -- SMTP, clamd -- with the transaction
# it holds open allowed to sit idle that long. It runs in a CPU-only child,
# except on the blocking layer: a child would leave the blocking caller's
# promise pending, so a command waits for it in the process.
async sub _slowly_p ( $self, $functions, $work, $context ) {
    my $configured = $self->config->database_idle_in_transaction_timeout_ms;
    if (   $functions->in_transaction
        && $configured
        && $configured < $SLOW_ANSWER_IDLE_MS )
    {
        await $functions->row_p( 'admin_allow_slow_answer',
            { idle_ms => $SLOW_ANSWER_IDLE_MS }, $context );
    }
    return $work->() if $functions->blocking;
    return await GPForum::Infrastructure::AsyncWork->shared->cpu_p($work);
}

# A transport failure is the outcome being tested, not an error of this
# command: it is caught here, so the audit row recording it commits. It
# touches no database, so catching it leaves the command's transaction as
# it was. A server's refusal often quotes the recipient ("<a@b>: Recipient
# address rejected"); the address is replaced, as it is kept out of the
# audit row everywhere else.
sub _send ( $self, $to ) {
    try {
        $self->mailer->send_test_message( { to => $to } );
    }
    catch ($error) {
        return {
            error   => $self->_scrubbed( $error, $to ),
            outcome => 'failed',
        };
    };

    return { outcome => 'sent' };
}

# A command scanner (clamscan) loads its signatures for every file; the
# three scans would outlast the request. Only a resident clamd answers in
# time, and only within the request budget Clamd->within_request sets.
sub _antivirus_report ($self) {
    my $scanner = $self->antivirus;
    my $engine  = $self->config->antivirus;
    if ( !$self->_scans_in_request ) {
        return {
            engine   => $engine,
            problems => [],
            reason   => 'command_scanner',
            status   => 'not_run',
        };
    }

    my $check = GPForum::Service::Operations::AntivirusCheck->new(
        clock  => $self->clock,
        config => $self->config,
        ( $scanner ? ( scanner => $scanner->within_request ) : () ),
    );
    my ( $report, $failure );
    try {
        $report = $check->run;
    }
    catch ($error) {
        $failure = $error;
    };
    if ( !$report ) {
        return {
            engine   => $engine,
            problems => [ $self->_scrubbed($failure) ],
            status   => 'fail',
        };
    }

    # The shell's wording speaks of "this shell"; the console has none.
    if ( $report->{status} eq 'disabled' ) {
        $report->{detail} =
            'scanning is off (GPFORUM_ANTIVIRUS=none): uploads are checked'
          . ' for format only';
    }

    return $report;
}

sub _scans_in_request ($self) {
    my $scanner = $self->antivirus;

    return ( !$scanner || $scanner->answers_immediately ) ? 1 : 0;
}

# The newest audited result of an action, which is what the page shows: it
# survives the redirect and is the same for every administrator.
async sub _latest_p ( $self, $action, $context ) {
    my $page = await $self->audit_review->page_p( { action => $action },
        { limit => 1 }, $context );
    my ($row) = @{ $page->{rows} || [] };
    my $none;
    return $none if !$row;

    return {
        actor_id => column_of( $row, 'actor_id' ),
        at       => column_of( $row, 'created_at' ),
        result   => _metadata($row),
    };
}

# get_column hands back a JSON column as its text; the inflated value is the
# hash it was written from.
sub _metadata ($row) {
    my $metadata =
        ref $row eq 'HASH'               ? $row->{metadata}
      : $row->can('get_inflated_column') ? $row->get_inflated_column('metadata')
      :                                    undef;

    return ref $metadata eq 'HASH' ? $metadata : {};
}

# An Email::Sender::Failure stringifies with its stack trace, whose frames
# can carry the arguments of the SMTP login; its message is what went wrong.
# Not every failure is one: without Authen::SASL, Email::Sender confesses
# that SMTP AUTH is impossible, a plain string whose tab-indented frames name
# the server's paths and the arguments of every call down to this one, the
# recipient included. Only the line before the frames is kept.
sub _scrubbed ( $self, $error, $recipient = undef ) {
    my $text =
        !defined $error                              ? 'unknown failure'
      : ( blessed $error && $error->can('message') ) ? $error->message
      :                                                "$error";
    $text =~ s/\n\t.*\z//msx;
    $text =~ s/\s+ at \s+ \S+ \s+ line \s+ \d+ [.]? \s* \z//msx;
    $text =~ s/\s+\z//msx;
    if ( defined $recipient && length $recipient ) {
        $text =~ s/\Q$recipient\E/$RECIPIENT/gmsxi;
    }

    # Redacted before it is shortened, so the cut cannot leave half a secret.
    $text = $self->settings->redact($text);
    if ( length $text > $MAX_ERROR_LENGTH ) {
        $text = substr( $text, 0, $MAX_ERROR_LENGTH ) . q{...};
    }

    return $text;
}

sub _audit_p ( $self, $functions, $input, $context ) {
    return $functions->row_p( 'ops_record_audit',
        $self->recorder->audit_call( %{ $self->_audit_row($input) } ),
        $context );
}

sub _audit_row ( $self, $input ) {
    return {
        action         => $input->{action},
        actor_id       => $input->{actor_user_id},
        correlation_id => $input->{correlation_id} // $self->id_service->uuid,
        created_at     => $self->clock->now_iso8601,
        metadata       => $input->{metadata},
        previous_hash  => undef,
        record_hash    => q{},
        schema_version => $SCHEMA_VERSION,
        target_id      => $input->{target_id},
        target_type    => $input->{target_type},
    };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'the diagnostics need the PostgreSQL function layer' );
}

1;

__END__

=head1 NAME

GPForum::Service::Admin::Diagnostics - Send a test message and check the antivirus from the console.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $diagnostics = GPForum::Service::Admin::Diagnostics->new(
        antivirus => $scanner,
        config    => $config,
        schema    => $schema,
    );
    my $overview = $diagnostics->overview($admin_id);
    my $mail     = $diagnostics->send_test_mail( { actor_user_id => $admin_id } );
    my $report   = $diagnostics->check_antivirus( { actor_user_id => $admin_id } );

=head1 DESCRIPTION

The console side of two shell checks (quality program 6.5).
C<send_test_mail> is C<gpforum mail-check --send>, restricted to the
signed-in administrator's own address: it never takes a recipient from the
request, so the console cannot be used to send mail anywhere else.
C<check_antivirus> runs L<GPForum::Service::Operations::AntivirusCheck>, what
C<gpforum antivirus-check> runs, against the application's scanner within
the request budget. Each is audited (C<admin.mail_test_sent>,
C<admin.antivirus_checked>) with its outcome, in the caller's transaction, and
a transport error or report is shown with every configured secret redacted
(L<GPForum::Service::Admin::Settings/redact>).

=head1 SUBROUTINES/METHODS

Each operation is written once, as its promise method, and takes an
optional query context; the blocking methods are those bodies settled on
the blocking layer, with the address and audit readers blocking too
(ADR 0177). The checks take the call layer of the caller's transaction
last, when their audit row joins it.

=head2 overview_p

Takes the administrator's user id. Resolves with their own address, the
mail transport, the scanning engine, whether it can be checked within a
request, and the last audited result of each check; the three reads are
sent together. C<overview> is its blocking twin.

=head2 send_test_mail_p

Takes a hash reference with C<actor_user_id>. Sends one test message to the
actor's address and audits the outcome: C<outcome> C<sent> or C<failed>
(with C<error>) and C<transport>. The address is in neither the result nor
the audit row: where the transport's error quotes it, it reads
C<[recipient]>. The SMTP exchange runs in a CPU-only child that never
touches PostgreSQL, and in the process for a blocking caller.
C<send_test_mail> is its blocking twin.

=head2 check_antivirus_p

Takes a hash reference with C<actor_user_id>. Runs the antivirus check and
audits its report: C<status> C<ok>, C<degraded>, C<fail>, C<disabled>, or
C<not_run> when the scanner is a command, which cannot answer within a
request. The scan runs as the test message does. C<check_antivirus> is its
blocking twin.

=head1 DIAGNOSTICS

A transport failure or a failed scan is a result, not an exception. The audit
write dies when the database does; the workflow's transaction then rolls back.
Throws L<GPForum::X::Unavailable> without the function layer.

=head1 CONFIGURATION AND ENVIRONMENT

The C<GPFORUM_MAIL_*>, C<GPFORUM_SMTP_*> and C<GPFORUM_ANTIVIRUS*> settings in
L<GPForum::Config>.

=head1 DEPENDENCIES

L<GPForum::Service::Identity::Mailer>,
L<GPForum::Service::Operations::AntivirusCheck>,
L<GPForum::Service::Admin::Settings>,
L<GPForum::Infrastructure::EventRecorder>.

Extends L<GPForum::Base>: built without C<config> it throws
L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The message is sent, and the scanner checked, inside the request, with the
command's transaction open meanwhile: an SMTP server slower than five
seconds a step fails the test, and that transaction may sit idle for up to a
minute (C<idle_in_transaction_session_timeout>, raised for it alone). A
stalled clamd or SMTP server can hold the request past Hypnotoad's
heartbeat; the worker then finishes it and is restarted. A server that
scans with a command (C<GPFORUM_ANTIVIRUS=command>) is checked from the
shell only.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
