# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::Workflow;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use Mojo::Util   qw(monkey_patch);
use Scalar::Util qw(blessed);

use GPForum::Infrastructure::ResultRow::IdentityUser;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Text qw(has_text trimmed);
use GPForum::Service::Identity::Support;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Service::SessionToken;
use GPForum::Service::WorkflowResult qw(log_error workflow_result);
use GPForum::X::Conflict;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $REGISTER => 'identity.register';

# What a command's recorded answer keeps of what it stored (_command_log_response).
const my @RECORDED_STORED =>
  qw(ok skipped user_id revoked_sessions email_change_withdrawn);
const my $REGISTER_ATTEMPTS  => 2;
const my $USER_ID_CONSTRAINT => 'users_pkey';

# api.identity_register_command's parameters after the command log, in its
# order; `answer`, `accepted` and `refused` are the answers it may record.
const my @REGISTER_PARAMETERS => qw(
  answer accepted refused user credential event event_outbox_id audit token
  token_audit mail_event mail_outbox_id mail_outbox_extras invitation_hash
);

# Each account write a member sends under a command id: its type, the
# fields it requires, the member it is recorded for, the request its
# fingerprint hashes, the store's write and how the stored answer is told.
# A command whose request leaves out what the member may correct -- a
# password, a token's companion -- abandons its refusals (refusal =>
# 'abandon'), so the corrected form sent again under the same id runs.
my %COMMAND = (

    # Signing out of no session is already done.
    logout => {
        type     => 'identity.logout',
        required => [qw(command_id)],
        actor    => 'user_id',
        request  => sub ($input) {
            return {
                session_id => trimmed( $input->{session_id} ),
                user_id    => trimmed( $input->{user_id} ),
            };
        },
        done => sub ($input) {
            return
              length trimmed( $input->{session_id} ) ? undef : _signed_out();
        },
        write  => 'revoke_session',
        answer => \&_consumed,
    },
    request_password_reset => {
        type     => 'identity.password_reset',
        required => [qw(command_id identifier)],
        request  => \&_identifier_request,
        write    => 'request_password_reset',
        answer   => \&_issued,
    },

    # A reset to the same secret still revokes sessions.
    reset_password => {
        type     => 'identity.password_reset_complete',
        required => [qw(command_id token password)],
        refusal  => 'abandon',
        request  => \&_token_request,
        write    => 'reset_password',
        answer   => \&_consumed,
    },

    # The request names the member alone: a password is no thing to
    # fingerprint.
    change_password => {
        type     => 'identity.password_change',
        required => [qw(command_id current_password new_password user_id)],
        actor    => 'user_id',
        refusal  => 'abandon',
        request  => sub ($input) { return { user_id => $input->{user_id} } },
        write    => 'change_password',
        answer   => \&_consumed,
    },

    # The current password is not in the request either.
    request_email_change => {
        type     => 'identity.email_change',
        required => [qw(command_id current_password)],
        actor    => 'user_id',
        refusal  => 'abandon',
        request  => sub ($input) {
            return {
                email   => trimmed( $input->{email} ),
                user_id => $input->{user_id},
            };
        },
        write  => 'request_email_change',
        answer => \&_issued,
    },
    request_email_verification => {
        type     => 'identity.email_verification',
        required => [qw(command_id identifier)],
        request  => \&_identifier_request,
        write    => 'request_email_verification',
        answer   => \&_issued,
    },
    verify_email => {
        type     => 'identity.email_verification_complete',
        required => [qw(command_id token)],
        request  => \&_token_request,
        write    => 'confirm_email_verification',
        answer   => \&_consumed,
    },
    confirm_email_change => {
        type     => 'identity.email_change_complete',
        required => [qw(command_id token)],
        request  => \&_token_request,
        write    => 'confirm_email_change',
        answer   => \&_consumed,
    },
    update_preferred_locale =>
      _preference( 'identity.locale_change', 'preferred_locale', 1 ),
    update_preferred_theme =>
      _preference( 'identity.theme_change', 'preferred_theme', 1 ),
    update_bio => _preference( 'identity.bio_change', 'bio' ),

    # An empty zone is a choice (the forum's default), so only the command
    # and the member are required.
    update_preferred_timezone =>
      _preference( 'identity.timezone_change', 'preferred_timezone' ),
    update_profile => {
        type     => 'identity.profile_change',
        required => [qw(command_id user_id)],
        actor    => 'user_id',
        request  => sub ($input) {
            return { map { $_ => trimmed( $input->{$_} ) }
                  qw(user_id display_name bio) };
        },
        write  => 'update_profile',
        answer => sub ($result) {
            return _kept( $result, qw(display_name bio) );
        },
    },
);

has logger => undef;    # optional: errors are dropped without one
__PACKAGE__->requires(qw(command_idempotency registration store));
has support => sub { return GPForum::Service::Identity::Support->new; };

# The store's call layer (Infrastructure::SqlFunction): a registration is
# one call on it.
has functions => sub ($self) {
    my $store = $self->store;
    return blessed $store
      && $store->can('functions') ? $store->functions : undef;
};

# Each command is written once, as its promise method (ADR 0177).
monkey_patch __PACKAGE__,
  map { ( "${_}_p" => _commanded( $COMMAND{$_} ) ) } keys %COMMAND;
GPForum::Infrastructure::SqlFunction->blocking_twins( keys %COMMAND,
    qw(register login complete_second_factor) );
GPForum::Infrastructure::SqlFunction->blocking_parts(
    qw(command_idempotency store));

sub _preference ( $type, $field, $required = 0 ) {
    return {
        type     => $type,
        required => [ qw(command_id user_id), $required ? $field : () ],
        actor    => 'user_id',
        request  => sub ($input) {
            return {
                $field  => trimmed( $input->{$field} ),
                user_id => $input->{user_id},
            };
        },
        write  => "update_$field",
        answer => sub ($result) { return _kept( $result, $field ); },
    };
}

sub _commanded ($command) {
    return sub ( $self, $input, $context = undef ) {
        return $self->_command_p( $command, $input, $context );
    };
}

# The command under its command log: a command id seen before answers what
# it answered then, a new one runs and is recorded, and one reused for
# another request is a conflict. The log's steps and the store's writes
# commit in one transaction, whose call layer the write is handed; a failed
# or abandoned answer rolls the whole command back.
async sub _command_p ( $self, $command, $input, $context ) {
    my $invalid = _missing_fields( $input, $command->{required} );
    return $invalid if $invalid;
    my $write = "$command->{write}_p";
    my $run_p = async sub ( $scope = undef ) {
        my $done = $command->{done} && $command->{done}->($input);
        return $done if $done;
        return $command->{answer}->(
            await $self->_stored_p(
                sub { return $self->store->$write( $input, $context, $scope ) }
            )
        );
    };

    my $result;
    try {
        $result = await $self->command_idempotency->result_of_p(
            {
                actor_id => $command->{actor} && $input->{ $command->{actor} },
                command_id   => trimmed( $input->{command_id} ),
                command_type => $command->{type},
                request      => $command->{request}->($input),
                refusal      => $command->{refusal},
                response     => \&_command_log_response,
                run_p        => $run_p,
            },
            $context
        );
    }
    catch ($error) {
        log_error( $self->logger, "identity command log failed: $error" );
        return _failed_result();
    };
    return $result;
}

# A login is never answered from the command log. It was: a replay keyed on
# the command id and the identifier handed the stored session -- bearer
# token included -- to whoever sent them, whatever the password, and the
# token sat in command_log in plain. Every attempt now checks the password;
# a retried login whose response was lost opens another session, which is
# harmless.
async sub login_p ( $self, $input, $context = undef ) {
    my $invalid = _missing_fields( $input, [qw(identifier password)] );
    return $invalid if $invalid;

    my $tried = await $self->_tried_p(
        sub { return $self->store->authenticate_login_p( $input, $context ) } );
    return _failed_result() if $tried->{failed};
    my $stored   = $tried->{value};
    my $two_step = _second_step($stored);
    return $two_step if $two_step;
    if ( !$stored || !$stored->{ok} ) {
        my $unverified =
          $stored && ( $stored->{error} || q{} ) eq q{unverified};
        my $error =
          $unverified ? q{unverified} : q{login request could not be accepted};
        return workflow_result( error => $error, status => q{rejected} );
    }

    return $self->_signed_in($stored);
}

# ADR 0142: the password verified and the member has two-step sign-in on:
# the challenge's token for the cookie, or the lock after ten wrong answers.
sub _second_step ($stored) {
    my $error = $stored ? $stored->{error} // q{} : q{};
    if ( $error eq 'second_factor' ) {
        return workflow_result(
            error  => $error,
            status => 'second_factor',
            stored => {
                challenge_token => $stored->{challenge_token},
                user_id         => $stored->{user_id},
            },
        );
    }
    if ( $error eq 'second_factor_locked' ) {
        return workflow_result(
            error  => $error,
            status => 'second_factor_locked'
        );
    }

    return undef;
}

# The second step of a sign-in (ADR 0142): the session, as a login answers
# it, with how it passed; or the refusal, status expired, wrong (with
# attempts_left) or locked.
async sub complete_second_factor_p ( $self, $input, $context = undef ) {
    my $tried = await $self->_tried_p(
        sub {
            return $self->store->complete_second_factor_p( $input, $context );
        }
    );
    return _failed_result() if $tried->{failed};
    my $stored = $tried->{value} || { error => 'expired' };
    if ( !$stored->{ok} ) {
        return {
            %{
                workflow_result(
                    error  => $stored->{error},
                    status => $stored->{error}
                )
            },
            attempts_left => $stored->{attempts_left} // 0,
        };
    }

    my $signed_in = $self->_signed_in($stored);
    $signed_in->{stored}{method}        = $stored->{method};
    $signed_in->{stored}{recovery_left} = $stored->{recovery_left};

    return $signed_in;
}

sub _signed_in ( $self, $stored ) {
    return workflow_result(
        status => 'ok',
        stored => {
            preferred_locale =>
              $self->_login_preference( $stored, 'preferred_locale' ),
            preferred_theme =>
              $self->_login_preference( $stored, 'preferred_theme' ),
            preferred_timezone =>
              $self->_login_preference( $stored, 'preferred_timezone' ),
            session_id => $stored->{session_id},

            # The per-session bearer token. It reaches the cookie and nowhere
            # else: the database keeps only its SHA-256, which is what
            # validate_session compares on every request.
            session_token => $stored->{session_token},
            user_id       => $stored->{user_id},
        },
    );
}

sub _login_preference ( $self, $stored, $name ) {
    return $stored->{$name} if has_text( $stored->{$name} );

    return $self->support->column( $stored->{user}, $name );
}

# The registration as one call (ADR 0126, section 5): the command log's
# steps, the duplicates, the user and the credential, the registration's
# event and audit, the verification token with its audit and its mail run
# in api.identity_register_command. The composer's refusal is recorded
# without a write; a taken username or email records the refusal prepared
# here. A user id the database already holds for another account is drawn
# again, once.
async sub register_p ( $self, $input, $context = undef ) {
    my $invalid = _missing_fields( $input, ['command_id'] );
    return $invalid if $invalid;
    my $functions = $self->_functions;

    # The command log's ids and time are drawn before the registration's, as
    # CommandIdempotency draws them before the work it guards. The password
    # is hashed before the database says whether the username or the address
    # is taken, on purpose: a taken one is refused in the same words and the
    # same time as any other refusal, so nobody learns from the answer, or
    # from how fast it came, which accounts exist.
    my $log =
      $self->_command_log( $input, $REGISTER, _register_request($input) );
    my $tried = await $self->_tried_p(
        sub { return $self->_prepared_p( $input, $functions ) } );
    my $prepared = $tried->{value};
    return _failed_result() if $tried->{failed} || !$prepared;
    if ( !$prepared->{ok} ) {
        my $refusal = _invalid_registration($prepared);
        my $row =
          await $self->_registered_p( $log, { answer => $refusal }, $context );
        return $row->{result} // $refusal;
    }
    my $registration = $prepared->{registration};
    my $refused      = _refused_registration($prepared);
    for my $attempt ( 1 .. $REGISTER_ATTEMPTS ) {
        my $call;
        try {
            $call = $self->store->register_call( $registration, $input );
        }
        catch ($error) {
            log_error( $self->logger, "identity registration failed: $error" );
            return _failed_result();
        };
        my $row =
          await $self->_registered_p( $log,
            _register_documents( $call, $input, $prepared, $refused ),
            $context );
        if ( $row->{retry} && $attempt < $REGISTER_ATTEMPTS ) {
            $registration->{user}{id} = $self->store->id_service->uuid;
            next;
        }
        return $self->_registration_result( $row, $prepared, $refused );
    }
    return _failed_result();
}

# The registration prepared, its password hashed by Argon2: in a child of
# the CPU lane on the asynchronous layer, in the process on the blocking
# one, whose settled promise a child would leave pending (ADR 0177).
async sub _prepared_p ( $self, $input, $functions ) {
    return $self->registration->prepare($input) if $functions->blocking;

    return await $self->registration->prepare_p($input);
}

sub _invitation_hash ($input) {
    my $token = trimmed( $input->{invitation} );
    return
      length $token
      ? GPForum::Service::SessionToken->new->hash_token($token)
      : undef;
}

sub _register_request ($input) {
    my $request = {
        email    => trimmed( $input->{email} ),
        username => trimmed( $input->{username} ),
    };
    if ( my $hash = _invitation_hash($input) ) {
        $request->{invitation_hash} = $hash;
    }

    return $request;
}

sub _invalid_registration ($prepared) {
    return workflow_result(
        errors => $prepared->{errors},
        status => 'invalid',
        stored => { values => $prepared->{values} },
    );
}

sub _refused_registration ($prepared) {
    return workflow_result(
        errors => {
            registration => 'registration request could not be accepted',
        },
        status => 'invalid',
        stored => { values => $prepared->{values} },
    );
}

sub _register_documents ( $call, $input, $prepared, $refused ) {
    my $registration = $prepared->{registration};
    return {
        %{$call},
        invitation_hash => _invitation_hash($input),
        accepted        => workflow_result(
            status => 'ok',
            stored => {
                registration => $registration,
                user         => $registration->{user},
                values       => $prepared->{values},
            }
        ),
        refused => $refused,
    };
}

# What a registration call's row answers: the result it recorded, or the
# refusal, or the result to return when it did not record.
sub _registration_result ( $self, $row, $prepared, $refused ) {
    return $row->{result} // _failed_result() if !$row->{recorded};
    return $refused if ( $row->{response}{status} // q{} ) ne 'ok';

    return workflow_result(
        status => 'ok',
        stored => {
            registration => $prepared->{registration},
            user => GPForum::Infrastructure::ResultRow::IdentityUser->from(
                $row->{stored_user}, $self->functions
            ),
            values => $prepared->{values},
        },
    );
}

# One call to api.identity_register_command, with the answers to record
# reduced as the command log keeps them. Answers: the result to return
# when the call did not record (a replay, a conflict, a failure), `retry`
# when the user's id is another account's, or `recorded` with the row's
# response and the user stored.
async sub _registered_p ( $self, $log, $call, $context ) {
    my $row;
    try {
        $row = await $self->_functions->row_p( 'identity_register_command',
            _register_parameters( $log, $call ), $context );
    }
    catch ($error) {
        my $conflict = GPForum::X::Conflict->caught($error);
        return { retry => 1 }
          if $conflict && $conflict->on($USER_ID_CONSTRAINT);
        log_error( $self->logger, "identity command log failed: $error" );
        return { result => _failed_result() };
    };
    return _register_outcome($row);
}

sub _register_parameters ( $log, $call ) {
    my %documents = %{$call};
    for my $answer ( grep { $documents{$_} } qw(answer accepted refused) ) {
        $documents{$answer} = _command_log_response( $documents{$answer} );
    }

    return { log => $log, map { $_ => $documents{$_} } @REGISTER_PARAMETERS };
}

sub _register_outcome ($row) {
    my $outcome = $row->{outcome} // q{};
    return { result => $row->{response} } if $outcome eq 'replayed';
    return {
        result => workflow_result(
            error =>
              GPForum::Service::Operations::CommandIdempotency->refusal_error(
                $outcome),
            status => 'conflict',
        )
      }
      if $outcome ne 'recorded';
    return {
        recorded    => 1,
        response    => $row->{response},
        stored_user => $row->{stored_user},
    };
}

# The command log's row as CommandIdempotency writes it, its ids and time
# drawn in its order.
sub _command_log ( $self, $input, $type, $request ) {
    my $log = $self->command_idempotency;
    return {
        actor_id               => undef,
        command_id             => $log->id_service->uuid,
        command_correlation_id => $log->id_service->uuid,
        command_at             => $log->clock->now_iso8601,
        command_type           => $type,
        idempotency_key        => trimmed( $input->{command_id} ),
        request_hash           => $log->request_hash($request),
    };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'registration needs the PostgreSQL function layer' );
}

sub _identifier_request ($input) {
    return { identifier => trimmed( $input->{identifier} ) };
}

sub _token_request ($input) {
    return { token => trimmed( $input->{token} ) };
}

sub _signed_out {
    return workflow_result(
        status => 'ok',
        stored => { skipped => 1 },
    );
}

# A write that consumes a token, or a session, answers that it was done.
sub _consumed ($result) {
    return $result if !$result->{ok};

    return workflow_result(
        status => 'ok',
        stored => { ok => 1 },
    );
}

# A write that issues a token answers without its raw value or its hash.
sub _issued ($result) {
    return $result if !$result->{ok};

    return _public_write_result($result);
}

# A preference or profile write answers with the values stored and nothing
# else.
sub _kept ( $result, @fields ) {
    return $result if !$result->{ok};

    return workflow_result(
        status => 'ok',
        stored => { ok => 1, map { $_ => $result->{stored}{$_} } @fields },
    );
}

# What the command log keeps of a result: whether it was done and why not,
# and the ids a replay or an operator reads -- the user's, the token's --
# never a value the member sent or the account holds: the password a refused
# registration was sent, an address, a bio, a hash. Nothing purges the log,
# and an erasure cannot find a registration's answer, whose actor is nobody.
sub _command_log_response ($result) {
    my $public = _public_write_result($result);
    return {} if ref $public ne 'HASH';

    my %response = %{$public};
    if ( ref $response{stored} eq 'HASH' ) {
        $response{stored} = _recorded_stored( $response{stored} );
    }

    return \%response;
}

sub _recorded_stored ($stored) {
    my %kept = map { exists $stored->{$_} ? ( $_ => $stored->{$_} ) : () }
      @RECORDED_STORED;
    if ( !exists $kept{user_id} && defined $stored->{user} ) {
        $kept{user_id} =
          GPForum::Service::Identity::Support->new->column( $stored->{user},
            'id' );
    }
    if ( ref $stored->{token} eq 'HASH' && defined $stored->{token}{token_id} )
    {
        $kept{token_id} = $stored->{token}{token_id};
    }

    return _jsonable_value( \%kept );
}

# Hashes and arrays are copied; an object, or any other reference, is
# dropped.
sub _jsonable_value ($value) {
    if ( ref $value eq 'HASH' ) {
        return { map { $_ => _jsonable_value( $value->{$_} ) } keys %{$value} };
    }
    if ( ref $value eq 'ARRAY' ) {
        return [ map { _jsonable_value($_) } @{$value} ];
    }
    return undef if ref $value;

    return $value;
}

sub _public_write_result ($result) {
    my $stored = $result->{stored} || {};
    my $token  = $stored->{token};
    if ( ref $token eq 'HASH' ) {
        delete $token->{raw_token};
        delete $token->{token_hash};
    }

    return $result;
}

# A store's answer as a workflow result: failed when it died or answered
# nothing, invalid with its reason, or ok with what it stored.
async sub _stored_p ( $self, $code ) {
    my $tried = await $self->_tried_p($code);
    my $value = $tried->{value};
    return _failed_result() if $tried->{failed} || !$value;
    if ( !$value->{ok} ) {
        return workflow_result(
            error  => $value->{error},
            errors => $value->{errors},
            status => 'invalid',
            stored => $value,
        );
    }

    return workflow_result(
        status => 'ok',
        stored => $value,
    );
}

# The store's answer, or that it failed: a store that died is logged.
async sub _tried_p ( $self, $code ) {
    my $value;
    try {
        $value = await $code->();
    }
    catch ($error) {
        log_error( $self->logger, "identity write failed: $error" );
        return { failed => 1 };
    };

    return { value => $value };
}

sub _missing_fields ( $input, $names ) {
    my %errors = map { $_ => "$_ is required" }
      grep { !length trimmed( $input->{$_} ) } @{$names};
    return undef if !%errors;

    return workflow_result(
        errors => \%errors,
        status => 'invalid',
    );
}

sub _failed_result {
    return workflow_result(
        error  => 'identity store failed',
        status => 'failed',
    );
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::Workflow - Identity write commands.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = await $workflow->login_p(
        {
            identifier => $identifier,
            password   => $password,
        }
    );

=head1 DESCRIPTION

Application boundary for registration, login, logout, password, email, and
preference writes. Validates required fields, delegates persistence to
C<Identity::Registration> and C<Identity::Store>, and returns a normalized
result hash without raw tokens. Token mail is queued on the identity
outbox by the store in the same transaction as issuance.

Every write but a login runs under the command log, which is required:
a command id seen before answers what it answered then, and one reused for
another request is a conflict. Each command is written once, as its
promise method (ADR 0177): the command log's steps and the store's writes
commit in one transaction on the worker's pooled asynchronous connections,
whose call layer the store writes on, and Argon2 runs in a child of the
CPU lane. Its blocking name is its twin, the same body settled on the
blocking layer with the command log and the store as blocking parts,
Argon2 then in the process. Every C<_p> method takes the input and an
optional query context.

Registration request hashes include email and username only, never the
password. A login is never recorded: every attempt checks the password.
Token-consume commands (password-reset complete, email-change complete,
and verification complete) request hashes include the token only, never a
new password. A recorded answer keeps, of what the command stored, whether
it was done and the ids a replay reads -- never a password, an address, a
bio or a hash. Stores keep transaction, event, audit, and outbox
ownership.

=head1 SUBROUTINES/METHODS

=head2 functions

The store's call layer (L<GPForum::Infrastructure::SqlFunction>).

=head2 register_p

Prepares and stores a registration, hiding duplicate-account details.
Requires C<command_id>. The registration is one call on the call layer
(C<api.identity_register_command>), which needs the function layer.

=head2 login_p

Authenticates an identifier and password, which it requires; it records
no command. Failed credentials are C<rejected> without enumerating whether
the account exists. A member with two-step sign-in on (ADR 0142) is
answered with status C<second_factor> and the challenge's
C<challenge_token> instead of a session, or C<second_factor_locked>.

=head2 complete_second_factor_p

Takes C<challenge_token>, C<code>, C<request_address> and C<user_agent>
and answers the challenge: status C<ok> with the session as L</login_p>
answers it, plus C<method> and C<recovery_left>; or C<expired>, C<wrong>
(with C<attempts_left>), C<locked> or C<failed>.

=head2 logout_p

Revokes a server-side session when a session id is present; signing out
of no session is already done. Requires C<command_id>. Command hashes
include C<session_id> and C<user_id> only.

=head2 request_password_reset_p

Starts a password reset for an identifier. Requires C<command_id>.

=head2 reset_password_p

Completes a password reset with a token. Requires C<command_id>.
A reset to the same secret still revokes sessions. The command's request
names the token alone, never the password, so its refusals are not its
answers: the log abandons them (C<< refusal => 'abandon' >>), and the form
sent again under the same command id with the password corrected runs.

=head2 change_password_p

Changes the password of an authenticated member. Requires C<command_id>.
Command hashes include C<user_id> only, never the current or new password,
so a refusal (the current password wrong, the new one weak) is not the
command's answer: the log abandons it, and the form sent again under the
same command id with the passwords corrected runs instead of getting the
refusal back.

=head2 request_email_change_p

Starts an email change for an authenticated member. Requires C<command_id>
and C<current_password>, which the store checks; command hashes include the
address and C<user_id>, never the password, so the log abandons a refusal
as it does for L</change_password_p>. A request for the member's
already-verified address does not issue a token.

=head2 confirm_email_change_p

Completes an email change with a token. Requires C<command_id>.

=head2 request_email_verification_p

Starts a registration verification resend for an identifier. Requires
C<command_id>.

=head2 verify_email_p

Completes registration verification with a token. Requires C<command_id>.

=head2 update_preferred_locale_p

Persists an authenticated member locale preference. Requires C<command_id>.

=head2 update_preferred_theme_p

Persists an authenticated member theme preference. Requires C<command_id>.

=head2 update_preferred_timezone_p

Persists a member's time zone, or the forum's default for an empty one.
Requires C<command_id>.

=head2 update_bio_p

Persists the few words a member shows on their profile (C<bio>, plain
text up to 500 characters; empty takes it down). Requires C<command_id>.

=head2 update_profile_p

Saves a member's display name and biography with an independent idempotent
command. Recorded responses retain no profile text.

=head2 register, login, complete_second_factor, logout, request_password_reset, reset_password, change_password, request_email_change, confirm_email_change, request_email_verification, verify_email, update_preferred_locale, update_preferred_theme, update_preferred_timezone, update_bio, update_profile

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), the command log and the store with it, answering the value
instead of a promise.

=head1 DIAGNOSTICS

Returns C<invalid>, C<rejected>, C<conflict> or C<failed> statuses instead
of throwing for expected write outcomes. Unexpected store and command-log
exceptions are logged and mapped to C<failed>, login's included. A
registration without the function layer throws
L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the registration, identity store and command log services supplied by
the composition root.

=head1 DEPENDENCIES

Uses L<GPForum::Base> and L<GPForum::Infrastructure::SqlFunction>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Cookie-session rotation remains in the HTTP controller. Locale and theme
cookie writes stay HTTP-specific; persistence goes through this workflow.
Guest cookie writes omit C<command_id>; authenticated preference writes
replay from C<command_log>.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
