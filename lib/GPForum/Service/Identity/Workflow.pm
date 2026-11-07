# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::Workflow;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::Text qw(has_text trimmed);
use GPForum::Service::Identity::Support;

use Scalar::Util qw(blessed);

use GPForum::Infrastructure::ResultRow::IdentityUser;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Service::WorkflowResult qw(log_error workflow_result);
use GPForum::X::Conflict;
use GPForum::Service::SessionToken;

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

has command_idempotency => undef;    # optional: writes run unlogged without one
has logger              => undef;    # optional: errors are dropped without one
__PACKAGE__->requires(qw(registration store));
has support => sub { return GPForum::Service::Identity::Support->new; };

sub register ( $self, $input ) {
    my $invalid = $self->_missing_fields( $input, ['command_id'] );
    if ($invalid) {
        return $invalid;
    }

    return $self->_register_by_function($input)
      if $self->command_idempotency && $self->_functions;

    return $self->_commanded_write(
        {
            actor_id     => undef,
            command_id   => $input->{command_id},
            command_type => 'identity.register',
            request      => {
                email    => trimmed( $input->{email} ),
                username => trimmed( $input->{username} ),
            },
            run => sub { return $self->_register_account($input); },
        }
    );
}

# A login is never answered from the command log. It was: a replay keyed on
# the command id and the identifier handed the stored session -- bearer
# token included -- to whoever sent them, whatever the password, and the
# token sat in command_log in plain. Every attempt now checks the password;
# a retried login whose response was lost opens another session, which is
# harmless.
sub login ( $self, $input ) {
    my $invalid = $self->_missing_fields( $input, [qw(identifier password)] );
    if ($invalid) {
        return $invalid;
    }

    my $tried = $self->_try_store(
        sub { return $self->store->authenticate_login($input); } );
    if ( $tried->{failed} ) {
        return _failed_result();
    }
    my $stored   = $tried->{value};
    my $two_step = _second_step($stored);
    if ($two_step) {
        return $two_step;
    }
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
sub complete_second_factor ( $self, $input ) {
    my $tried = $self->_try_store(
        sub { return $self->store->complete_second_factor($input); } );
    if ( $tried->{failed} ) {
        return _failed_result();
    }
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

# Signing out of no session is already done.
sub logout ( $self, $input ) {
    my $invalid = $self->_missing_fields( $input, ['command_id'] );
    if ($invalid) {
        return $invalid;
    }

    return $self->_commanded_write(
        {
            actor_id     => $input->{user_id},
            command_id   => $input->{command_id},
            command_type => 'identity.logout',
            request      => {
                session_id => trimmed( $input->{session_id} ),
                user_id    => trimmed( $input->{user_id} ),
            },
            run => sub {
                if ( !length trimmed( $input->{session_id} ) ) {
                    return workflow_result(
                        status => 'ok',
                        stored => { skipped => 1 },
                    );
                }
                return $self->_public_consume_result(
                    sub { return $self->store->revoke_session($input); } );
            },
        }
    );
}

sub request_password_reset ( $self, $input ) {
    my $invalid = $self->_missing_fields( $input, [qw(command_id identifier)] );
    if ($invalid) {
        return $invalid;
    }

    return $self->_commanded_token_write(
        {
            actor_id     => undef,
            command_id   => $input->{command_id},
            command_type => 'identity.password_reset',
            request      => { identifier => trimmed( $input->{identifier} ) },
            run          => sub {
                return $self->store->request_password_reset($input);
            },
        }
    );
}

sub reset_password ( $self, $input ) {
    return $self->_token_consume_write(
        {
            command_type => 'identity.password_reset_complete',
            extra_fields => ['password'],
            input        => $input,
            refusal      => 'abandon',
            run          => sub {
                return $self->store->reset_password($input);
            },
        }
    );
}

sub change_password ( $self, $input ) {
    my $invalid = $self->_missing_fields( $input,
        [qw(command_id current_password new_password user_id)] );
    if ($invalid) {
        return $invalid;
    }

    # The request names the member alone: a password is no thing to
    # fingerprint. So a refusal (the current password wrong, the new one
    # weak) is not this command's answer, or the corrected form, sent again
    # under its command id, got the refusal back until the page was reloaded.
    return $self->_commanded_write(
        {
            actor_id     => $input->{user_id},
            command_id   => $input->{command_id},
            command_type => 'identity.password_change',
            refusal      => 'abandon',
            request      => { user_id => $input->{user_id} },
            run          => sub {
                return $self->_public_consume_result(
                    sub { return $self->store->change_password($input); } );
            },
        }
    );
}

sub request_email_change ( $self, $input ) {
    my $invalid =
      $self->_missing_fields( $input, [qw(command_id current_password)] );
    if ($invalid) {
        return $invalid;
    }

    # The current password is not in the request either (see change_password).
    return $self->_commanded_token_write(
        {
            actor_id     => $input->{user_id},
            command_id   => $input->{command_id},
            command_type => 'identity.email_change',
            refusal      => 'abandon',
            request      => {
                email   => trimmed( $input->{email} ),
                user_id => $input->{user_id},
            },
            run => sub {
                return $self->store->request_email_change($input);
            },
        }
    );
}

sub request_email_verification ( $self, $input ) {
    my $invalid = $self->_missing_fields( $input, [qw(command_id identifier)] );
    if ($invalid) {
        return $invalid;
    }

    return $self->_commanded_token_write(
        {
            actor_id     => undef,
            command_id   => $input->{command_id},
            command_type => 'identity.email_verification',
            request      => { identifier => trimmed( $input->{identifier} ) },
            run          => sub {
                return $self->store->request_email_verification($input);
            },
        }
    );
}

sub verify_email ( $self, $input ) {
    return $self->_token_consume_write(
        {
            command_type => 'identity.email_verification_complete',
            input        => $input,
            run          => sub {
                return $self->store->confirm_email_verification($input);
            },
        }
    );
}

sub confirm_email_change ( $self, $input ) {
    return $self->_token_consume_write(
        {
            command_type => 'identity.email_change_complete',
            input        => $input,
            run          => sub {
                return $self->store->confirm_email_change($input);
            },
        }
    );
}

sub update_preferred_locale ( $self, $input ) {
    return $self->_preference_write(
        {
            command_type => 'identity.locale_change',
            field        => 'preferred_locale',
            input        => $input,
            required     => [qw(command_id user_id preferred_locale)],
            run          => sub {
                return $self->store->update_preferred_locale($input);
            },
        }
    );
}

sub update_preferred_theme ( $self, $input ) {
    return $self->_preference_write(
        {
            command_type => 'identity.theme_change',
            field        => 'preferred_theme',
            input        => $input,
            required     => [qw(command_id user_id preferred_theme)],
            run          => sub {
                return $self->store->update_preferred_theme($input);
            },
        }
    );
}

# An empty zone is a choice (the forum's default), so only the command and
# the member are required.
sub update_bio ( $self, $input ) {
    return $self->_preference_write(
        {
            command_type => 'identity.bio_change',
            field        => 'bio',
            input        => $input,
            required     => [qw(command_id user_id)],
            run          => sub { return $self->store->update_bio($input); },
        }
    );
}

sub update_profile ( $self, $input ) {
    my $invalid = $self->_missing_fields( $input, [qw(command_id user_id)] );
    return $invalid if $invalid;
    return $self->_commanded_write(
        {
            actor_id     => $input->{user_id},
            command_id   => $input->{command_id},
            command_type => 'identity.profile_change',
            request      => {
                map { $_ => trimmed( $input->{$_} ) }
                  qw(user_id display_name bio)
            },
            run => sub {
                my $result = $self->_store_write(
                    sub { return $self->store->update_profile($input); } );
                return $result if !$result->{ok};
                return workflow_result(
                    status => 'ok',
                    stored => {
                        ok => 1,
                        map { $_ => $result->{stored}{$_} }
                          qw(display_name bio)
                    }
                );
            },
        }
    );
}

sub update_preferred_timezone ( $self, $input ) {
    return $self->_preference_write(
        {
            command_type => 'identity.timezone_change',
            field        => 'preferred_timezone',
            input        => $input,
            required     => [qw(command_id user_id)],
            run          => sub {
                return $self->store->update_preferred_timezone($input);
            },
        }
    );
}

# A preference write answers with the value stored and nothing else.
sub _preference_write ( $self, $job ) {
    my $input   = $job->{input};
    my $field   = $job->{field};
    my $invalid = $self->_missing_fields( $input, $job->{required} );
    if ($invalid) {
        return $invalid;
    }

    return $self->_commanded_write(
        {
            actor_id     => $input->{user_id},
            command_id   => $input->{command_id},
            command_type => $job->{command_type},
            request      => {
                $field  => trimmed( $input->{$field} ),
                user_id => $input->{user_id},
            },
            run => sub {
                my $result = $self->_store_write( $job->{run} );
                if ( !$result->{ok} ) {
                    return $result;
                }
                return workflow_result(
                    status => 'ok',
                    stored => {
                        ok     => 1,
                        $field => $result->{stored}{$field},
                    },
                );
            },
        }
    );
}

# The store's call layer (Infrastructure::SqlFunction), when the command
# log runs on one too: then a registration is one call. A command log that
# is a double, or a store that is, keeps the Perl path (ADR 0126, section
# 10: the unit tests stand on doubles of the call layer).
sub _functions ($self) {
    return undef if !_call_layer( $self->command_idempotency );
    return _call_layer( $self->store );
}

sub _call_layer ($service) {
    return blessed $service && $service->can('functions')
      ? $service->functions
      : undef;
}

# The registration as one call (ADR 0126, section 5): the command log's
# steps, the duplicates, the user and the credential, the registration's
# event and audit, the verification token with its audit and its mail run
# in api.identity_register_command, which records the answer the Perl path
# records. The composer's refusal is recorded without a write; a taken
# username or email records the refusal prepared here. A user id the
# database already holds for another account is drawn again, once.
sub _invitation_hash ($input) {
    my $token = trimmed( $input->{invitation} );
    return
      length $token
      ? GPForum::Service::SessionToken->new->hash_token($token)
      : undef;
}

sub _register_by_function ( $self, $input ) {
    my $request = {
        email    => trimmed( $input->{email} ),
        username => trimmed( $input->{username} ),
    };

    if ( my $hash = _invitation_hash($input) ) {
        $request->{invitation_hash} = $hash;
    }

    # The command log's ids and time are drawn before the registration's, as
    # CommandIdempotency draws them before the work it guards. The password
    # is hashed before the database says whether the username or the address
    # is taken, on purpose: a taken one is refused in the same words and the
    # same time as any other refusal, so nobody learns from the answer, or
    # from how fast it came, which accounts exist.
    my $log = $self->_command_log( $input, $REGISTER, $request );
    my $tried =
      $self->_try_store( sub { return $self->registration->prepare($input); } );
    my $prepared = $tried->{value};
    if ( $tried->{failed} || !$prepared ) {
        return _failed_result();
    }
    if ( !$prepared->{ok} ) {
        my $invalid = workflow_result(
            errors => $prepared->{errors},
            status => 'invalid',
            stored => { values => $prepared->{values} },
        );
        my $row = $self->_registered( $log, { answer => $invalid } );
        return $row->{result} // $invalid;
    }
    my $registration = $prepared->{registration};
    my $refused      = workflow_result(
        errors => {
            registration => 'registration request could not be accepted',
        },
        status => 'invalid',
        stored => { values => $prepared->{values} },
    );
    for my $attempt ( 1 .. $REGISTER_ATTEMPTS ) {
        my $call;
        try {
            $call = $self->store->register_call( $registration, $input );
        }
        catch ($error) {
            log_error( $self->logger, "identity registration failed: $error" );
            return _failed_result();
        };
        my $row = $self->_registered(
            $log,
            {
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
            }
        );
        if ( $row->{retry} && $attempt < $REGISTER_ATTEMPTS ) {
            $registration->{user}{id} = $self->store->id_service->uuid;
            next;
        }
        if ( !$row->{recorded} ) {
            return $row->{result} // _failed_result();
        }
        if ( ( $row->{response}{status} // q{} ) ne 'ok' ) {
            return $refused;
        }
        return workflow_result(
            status => 'ok',
            stored => {
                registration => $registration,
                user => GPForum::Infrastructure::ResultRow::IdentityUser->from(
                    $row->{stored_user}, $self->_functions
                ),
                values => $prepared->{values},
            },
        );
    }
    return _failed_result();
}

# One call to api.identity_register_command, with the answers to record
# reduced as the command log keeps them. Answers: the result to return
# when the call did not record (a replay, a conflict, a failure), `retry`
# when the user's id is another account's, or `recorded` with the row's
# response and the user stored.
sub _registered ( $self, $log, $call ) {
    my %documents = %{$call};
    for my $answer ( grep { $documents{$_} } qw(answer accepted refused) ) {
        $documents{$answer} = _command_log_response( $documents{$answer} );
    }
    my $row;
    try {
        $row = $self->_functions->row(
            'identity_register_command',
            {
                log => $log,
                map { $_ => $documents{$_} } @REGISTER_PARAMETERS
            }
        );
    }
    catch ($error) {
        my $conflict = GPForum::X::Conflict->caught($error);
        return { retry => 1 }
          if $conflict && $conflict->on($USER_ID_CONSTRAINT);
        log_error( $self->logger, "identity command log failed: $error" );
        return { result => _failed_result() };
    };
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

# The registration is prepared, then stored. A stored account is sent its
# verification mail; a mail that cannot be queued does not undo the account.
sub _register_account ( $self, $input ) {
    my $tried =
      $self->_try_store( sub { return $self->registration->prepare($input); } );
    my $prepared = $tried->{value};
    if ( $tried->{failed} || !$prepared ) {
        return _failed_result();
    }
    if ( !$prepared->{ok} ) {
        return workflow_result(
            errors => $prepared->{errors},
            status => 'invalid',
            stored => { values => $prepared->{values} },
        );
    }

    my $stored = $self->_try_store(
        sub {
            return $self->store->create_registration(
                $prepared->{registration} );
        }
    );
    if ( $stored->{failed} ) {
        return _failed_result();
    }
    my $created = $stored->{value};
    if ( !$created || !$created->{ok} ) {
        return workflow_result(
            errors => {
                registration => 'registration request could not be accepted',
            },
            status => 'invalid',
            stored => { values => $prepared->{values} },
        );
    }

    $self->_try_store(
        sub {
            return $self->store->request_email_verification(
                { user_id => $self->support->column( $created->{user}, 'id' ) }
            );
        }
    );

    return workflow_result(
        status => 'ok',
        stored => {
            registration => $prepared->{registration},
            user         => $created->{user},
            values       => $prepared->{values},
        },
    );
}

sub _token_consume_write ( $self, $job ) {
    my $input   = $job->{input};
    my $invalid = $self->_missing_fields( $input,
        [ 'command_id', 'token', @{ $job->{extra_fields} || [] } ] );
    if ($invalid) {
        return $invalid;
    }

    return $self->_commanded_write(
        {
            actor_id     => undef,
            command_id   => $input->{command_id},
            command_type => $job->{command_type},
            refusal      => $job->{refusal},
            request      => { token => trimmed( $input->{token} ) },
            run          => sub {
                return $self->_public_consume_result( $job->{run} );
            },
        }
    );
}

sub _public_consume_result ( $self, $code ) {
    my $result = $self->_store_write($code);
    if ( !$result->{ok} ) {
        return $result;
    }

    return workflow_result(
        status => 'ok',
        stored => { ok => 1 },
    );
}

sub _login_preference ( $self, $stored, $name ) {
    if ( has_text( $stored->{$name} ) ) {
        return $stored->{$name};
    }

    return $self->support->column( $stored->{user}, $name );
}

# Without a command log a write just runs. With one, a command id seen
# before answers what it answered then, a new one runs and is recorded, and
# one reused for another request is a conflict.
sub _commanded_write ( $self, $job ) {
    if ( !$self->command_idempotency ) {
        return $job->{run}->();
    }

    my $guarded;
    try {
        $guarded = $self->command_idempotency->run(
            {
                actor_id     => $job->{actor_id},
                command_id   => trimmed( $job->{command_id} ),
                command_type => $job->{command_type},
                request      => $job->{request} || {},
                refusal      => $job->{refusal},
            },
            sub { return $job->{run}->(); },
            sub ($result) { return _command_log_response($result); },
        );
    }
    catch ($error) {
        log_error( $self->logger, "identity command log failed: $error" );
        return _failed_result();
    };
    if ( $guarded->{replayed} ) {
        return $guarded->{response};
    }
    if ( $guarded->{recorded} ) {
        return $guarded->{result};
    }
    if ( $guarded->{invalid} ) {
        return workflow_result(
            errors => { command_id => 'command_id is required' },
            status => 'invalid',
        );
    }

    return workflow_result(
        error  => $guarded->{error},
        status => 'conflict',
    );
}

# A write that issues a token answers without its raw value or its hash.
sub _commanded_token_write ( $self, $job ) {
    return $self->_commanded_write(
        {
            actor_id     => $job->{actor_id},
            command_id   => $job->{command_id},
            command_type => $job->{command_type},
            refusal      => $job->{refusal},
            request      => $job->{request},
            run          => sub {
                my $result = $self->_store_write( $job->{run} );
                if ( !$result->{ok} ) {
                    return $result;
                }
                return _public_write_result($result);
            },
        }
    );
}

# What the command log keeps of a result: whether it was done and why not,
# and the ids a replay or an operator reads -- the user's, the token's --
# never a value the member sent or the account holds: the password a refused
# registration was sent, an address, a bio, a hash. Nothing purges the log,
# and an erasure cannot find a registration's answer, whose actor is nobody.
sub _command_log_response ($result) {
    my $public = _public_write_result($result);
    if ( ref $public ne 'HASH' ) {
        return {};
    }

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
    if ( ref $value ) {
        return undef;
    }

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

sub _store_write ( $self, $code ) {
    my $tried = $self->_try_store($code);
    my $value = $tried->{value};
    if ( $tried->{failed} || !$value ) {
        return _failed_result();
    }
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

sub _missing_fields ( $, $input, $names ) {
    my %errors;
    for my $name ( @{$names} ) {
        if ( !length trimmed( $input->{$name} ) ) {
            $errors{$name} = "$name is required";
        }
    }
    if (%errors) {
        return workflow_result(
            errors => \%errors,
            status => 'invalid',
        );
    }

    return undef;
}

sub _try_store ( $self, $code ) {
    my $value;
    try {
        $value = $code->();
    }
    catch ($error) {
        log_error( $self->logger, "identity write failed: $error" );
        return { failed => 1 };
    };

    return { value => $value };
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

    my $result = $workflow->login(
        {
            command_id => $command_id,
            identifier => $identifier,
            password   => $password,
        }
    );

=head1 DESCRIPTION

Application boundary for registration, login, logout, password, email, and
preference writes. Validates required fields, delegates persistence to
C<Identity::Registration> and C<Identity::Store>, and returns a normalized
result hash without raw tokens. Token mail is queued on the identity
outbox by the store in the same transaction as issuance. Registration,
password-reset, email-change, and verification-resend require C<command_id>
and replay from C<command_log> when the helper is present. Registration
request hashes include email and username only, never the password. A login
is never recorded: every attempt checks the password. Token-consume commands
(password-reset complete, email-change complete, and verification complete)
request hashes include the token only, never a new password, and the
recorded result is JSON-safe. A recorded answer keeps, of what the command
stored, whether it was done and the ids a replay reads -- never a password,
an address, a bio or a hash. Stores keep transaction, event, audit, and
outbox ownership.

=head1 SUBROUTINES/METHODS

=head2 register

Prepares and stores a registration, hiding duplicate-account details.
Requires C<command_id>.

=head2 login

Authenticates an identifier and password, which it requires; it records
no command. Failed credentials are C<rejected> without enumerating whether the account exists.
A member with two-step sign-in on (ADR 0142) is answered with status
C<second_factor> and the challenge's C<challenge_token> instead of a
session, or C<second_factor_locked>.

=head2 complete_second_factor

Takes C<challenge_token>, C<code>, C<request_address> and C<user_agent>
and answers the challenge: status C<ok> with the session as L</login>
answers it, plus C<method> and C<recovery_left>; or C<expired>, C<wrong>
(with C<attempts_left>), C<locked> or C<failed>.

=head2 logout

Revokes a server-side session when a session id is present. Requires
C<command_id>. Command hashes include C<session_id> and C<user_id> only.

=head2 request_password_reset

Starts a password reset for an identifier. Requires C<command_id>.

=head2 reset_password

Completes a password reset with a token. Requires C<command_id>.
A reset to the same secret still revokes sessions. The command's request
names the token alone, never the password, so its refusals are not its
answers: the log abandons them (L<GPForum::Service::Operations::CommandIdempotency/run>,
C<< refusal => 'abandon' >>), and the form sent again under the same
command id with the password corrected runs.

=head2 change_password

Changes the password of an authenticated member. Requires C<command_id>.
Command hashes include C<user_id> only, never the current or new password,
so a refusal (the current password wrong, the new one weak) is not the
command's answer: the log abandons it, and the form sent again under the
same command id with the passwords corrected runs instead of getting the
refusal back.

=head2 request_email_change

Starts an email change for an authenticated member. Requires C<command_id>
and C<current_password>, which the store checks; command hashes include the
address and C<user_id>, never the password, so the log abandons a refusal
as it does for L</change_password>. A request for the member's
already-verified address does not issue a token.

=head2 confirm_email_change

Completes an email change with a token. Requires C<command_id>.

=head2 request_email_verification

Starts a registration verification resend for an identifier. Requires
C<command_id>.

=head2 verify_email

Completes registration verification with a token. Requires C<command_id>.

=head2 update_preferred_locale

Persists an authenticated member locale preference. Requires C<command_id>.

=head2 update_preferred_timezone

Persists a member's time zone, or the forum's default for an empty one.
Requires C<command_id>.

=head2 update_bio

Persists the few words a member shows on their profile (C<bio>, plain
text up to 500 characters; empty takes it down). Requires C<command_id>.

=head2 update_profile

Saves a member's display name and biography with an independent idempotent command.
Recorded responses retain no profile text.

=head2 update_preferred_theme

Persists an authenticated member theme preference. Requires C<command_id>.

=head1 DIAGNOSTICS

Returns C<invalid>, C<rejected>, or C<failed> statuses instead of throwing for
expected write outcomes. Unexpected store exceptions are logged and mapped to
C<failed>, login's included.

=head1 CONFIGURATION AND ENVIRONMENT

Uses registration and identity store services supplied by the composition
root.

=head1 DEPENDENCIES

Uses L<GPForum::Base>.

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
