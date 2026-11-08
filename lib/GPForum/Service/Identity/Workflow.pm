# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::Workflow;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
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

    return $self->_login_answer(
        $self->_try_store(
            sub { return $self->store->authenticate_login($input); }
        )
    );
}

# login on the worker's pooled asynchronous connections, Argon2 in a child
# of the CPU lane on plain data.
async sub login_p ( $self, $input, $context = undef ) {
    return $self->login($input) if !$self->_native;
    my $invalid = $self->_missing_fields( $input, [qw(identifier password)] );
    return $invalid if $invalid;

    return $self->_login_answer(
        await $self->_try_store_p(
            sub {
                return $self->store->authenticate_login_p( $input, $context );
            }
        )
    );
}

sub _login_answer ( $self, $tried ) {
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
    return $self->_second_factor_answer(
        $self->_try_store(
            sub { return $self->store->complete_second_factor($input); }
        )
    );
}

# complete_second_factor on the worker's pooled asynchronous connections.
async sub complete_second_factor_p ( $self, $input, $context = undef ) {
    return $self->complete_second_factor($input) if !$self->_native;

    return $self->_second_factor_answer(
        await $self->_try_store_p(
            sub {
                return $self->store->complete_second_factor_p( $input,
                    $context );
            }
        )
    );
}

sub _second_factor_answer ( $self, $tried ) {
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
            %{ _logout_command($input) },
            run => sub {
                return _signed_out() if !length trimmed( $input->{session_id} );
                return $self->_public_consume_result(
                    sub { return $self->store->revoke_session($input); } );
            },
        }
    );
}

# logout on the worker's pooled asynchronous connections: the command
# log's steps and the revocation commit in one transaction.
async sub logout_p ( $self, $input, $context = undef ) {
    return $self->logout($input) if !$self->_native;
    my $invalid = $self->_missing_fields( $input, ['command_id'] );
    return $invalid if $invalid;

    return await $self->_commanded_write_p(
        {
            %{ _logout_command($input) },
            run_p => async sub ($scope) {
                return _signed_out() if !length trimmed( $input->{session_id} );
                return await $self->_public_consume_result_p(
                    sub {
                        return $self->store->revoke_session_p( $input,
                            $context, $scope );
                    }
                );
            },
        },
        $context
    );
}

sub _logout_command ($input) {
    return {
        actor_id     => $input->{user_id},
        command_id   => $input->{command_id},
        command_type => 'identity.logout',
        request      => {
            session_id => trimmed( $input->{session_id} ),
            user_id    => trimmed( $input->{user_id} ),
        },
    };
}

sub _signed_out {
    return workflow_result(
        status => 'ok',
        stored => { skipped => 1 },
    );
}

sub request_password_reset ( $self, $input ) {
    my $invalid = $self->_missing_fields( $input, [qw(command_id identifier)] );
    if ($invalid) {
        return $invalid;
    }

    return $self->_commanded_token_write(
        {
            %{ _password_reset_command($input) },
            run => sub {
                return $self->store->request_password_reset($input);
            },
        }
    );
}

# The account writes below, each on the worker's pooled asynchronous
# connections: the command log's steps and the store's writes commit in
# one transaction, Argon2 in a child of the CPU lane.
async sub request_password_reset_p ( $self, $input, $context = undef ) {
    return $self->request_password_reset($input) if !$self->_native;
    my $invalid = $self->_missing_fields( $input, [qw(command_id identifier)] );
    return $invalid if $invalid;

    return await $self->_commanded_token_write_p(
        {
            %{ _password_reset_command($input) },
            run_p => sub ($scope) {
                return $self->store->request_password_reset_p( $input,
                    $context, $scope );
            },
        },
        $context
    );
}

sub _password_reset_command ($input) {
    return {
        actor_id     => undef,
        command_id   => $input->{command_id},
        command_type => 'identity.password_reset',
        request      => { identifier => trimmed( $input->{identifier} ) },
    };
}

sub reset_password ( $self, $input ) {
    return $self->_token_consume_write( _reset_job($input),
        sub { return $self->store->reset_password($input); } );
}

async sub reset_password_p ( $self, $input, $context = undef ) {
    return $self->reset_password($input) if !$self->_native;

    return await $self->_token_consume_write_p(
        _reset_job($input),
        sub ($scope) {
            return $self->store->reset_password_p( $input, $context, $scope );
        },
        $context
    );
}

sub _reset_job ($input) {
    return {
        command_type => 'identity.password_reset_complete',
        extra_fields => ['password'],
        input        => $input,
        refusal      => 'abandon',
    };
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
            %{ _password_change_command($input) },
            run => sub {
                return $self->_public_consume_result(
                    sub { return $self->store->change_password($input); } );
            },
        }
    );
}

async sub change_password_p ( $self, $input, $context = undef ) {
    return $self->change_password($input) if !$self->_native;
    my $invalid = $self->_missing_fields( $input,
        [qw(command_id current_password new_password user_id)] );
    return $invalid if $invalid;

    return await $self->_commanded_write_p(
        {
            %{ _password_change_command($input) },
            run_p => sub ($scope) {
                return $self->_public_consume_result_p(
                    sub {
                        return $self->store->change_password_p( $input,
                            $context, $scope );
                    }
                );
            },
        },
        $context
    );
}

sub _password_change_command ($input) {
    return {
        actor_id     => $input->{user_id},
        command_id   => $input->{command_id},
        command_type => 'identity.password_change',
        refusal      => 'abandon',
        request      => { user_id => $input->{user_id} },
    };
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
            %{ _email_change_command($input) },
            run => sub {
                return $self->store->request_email_change($input);
            },
        }
    );
}

async sub request_email_change_p ( $self, $input, $context = undef ) {
    return $self->request_email_change($input) if !$self->_native;
    my $invalid =
      $self->_missing_fields( $input, [qw(command_id current_password)] );
    return $invalid if $invalid;

    return await $self->_commanded_token_write_p(
        {
            %{ _email_change_command($input) },
            run_p => sub ($scope) {
                return $self->store->request_email_change_p( $input,
                    $context, $scope );
            },
        },
        $context
    );
}

sub _email_change_command ($input) {
    return {
        actor_id     => $input->{user_id},
        command_id   => $input->{command_id},
        command_type => 'identity.email_change',
        refusal      => 'abandon',
        request      => {
            email   => trimmed( $input->{email} ),
            user_id => $input->{user_id},
        },
    };
}

sub request_email_verification ( $self, $input ) {
    my $invalid = $self->_missing_fields( $input, [qw(command_id identifier)] );
    if ($invalid) {
        return $invalid;
    }

    return $self->_commanded_token_write(
        {
            %{ _email_verification_command($input) },
            run => sub {
                return $self->store->request_email_verification($input);
            },
        }
    );
}

async sub request_email_verification_p ( $self, $input, $context = undef ) {
    return $self->request_email_verification($input) if !$self->_native;
    my $invalid = $self->_missing_fields( $input, [qw(command_id identifier)] );
    return $invalid if $invalid;

    return await $self->_commanded_token_write_p(
        {
            %{ _email_verification_command($input) },
            run_p => sub ($scope) {
                return $self->store->request_email_verification_p( $input,
                    $context, $scope );
            },
        },
        $context
    );
}

sub _email_verification_command ($input) {
    return {
        actor_id     => undef,
        command_id   => $input->{command_id},
        command_type => 'identity.email_verification',
        request      => { identifier => trimmed( $input->{identifier} ) },
    };
}

sub verify_email ( $self, $input ) {
    return $self->_token_consume_write(
        _token_job( 'identity.email_verification_complete', $input ),
        sub { return $self->store->confirm_email_verification($input); }
    );
}

async sub verify_email_p ( $self, $input, $context = undef ) {
    return $self->verify_email($input) if !$self->_native;

    return await $self->_token_consume_write_p(
        _token_job( 'identity.email_verification_complete', $input ),
        sub ($scope) {
            return $self->store->confirm_email_verification_p( $input,
                $context, $scope );
        },
        $context
    );
}

sub confirm_email_change ( $self, $input ) {
    return $self->_token_consume_write(
        _token_job( 'identity.email_change_complete', $input ),
        sub { return $self->store->confirm_email_change($input); }
    );
}

async sub confirm_email_change_p ( $self, $input, $context = undef ) {
    return $self->confirm_email_change($input) if !$self->_native;

    return await $self->_token_consume_write_p(
        _token_job( 'identity.email_change_complete', $input ),
        sub ($scope) {
            return $self->store->confirm_email_change_p( $input, $context,
                $scope );
        },
        $context
    );
}

sub _token_job ( $command_type, $input ) {
    return {
        command_type => $command_type,
        input        => $input,
    };
}

sub update_preferred_locale ( $self, $input ) {
    return $self->_preference_write( _locale_job($input) );
}

# update_preferred_locale on the worker's pooled asynchronous connections:
# the command log's steps and the write commit in one transaction.
async sub update_preferred_locale_p ( $self, $input, $context = undef ) {
    return await $self->_preference_write_p( _locale_job($input), $context );
}

sub _locale_job ($input) {
    return {
        command_type => 'identity.locale_change',
        field        => 'preferred_locale',
        input        => $input,
        method       => 'update_preferred_locale',
        required     => [qw(command_id user_id preferred_locale)],
    };
}

sub update_preferred_theme ( $self, $input ) {
    return $self->_preference_write( _theme_job($input) );
}

# update_preferred_theme on the worker's pooled asynchronous connections.
async sub update_preferred_theme_p ( $self, $input, $context = undef ) {
    return await $self->_preference_write_p( _theme_job($input), $context );
}

sub _theme_job ($input) {
    return {
        command_type => 'identity.theme_change',
        field        => 'preferred_theme',
        input        => $input,
        method       => 'update_preferred_theme',
        required     => [qw(command_id user_id preferred_theme)],
    };
}

sub update_bio ( $self, $input ) {
    return $self->_preference_write( _bio_job($input) );
}

# update_bio on the worker's pooled asynchronous connections.
async sub update_bio_p ( $self, $input, $context = undef ) {
    return await $self->_preference_write_p( _bio_job($input), $context );
}

sub _bio_job ($input) {
    return {
        command_type => 'identity.bio_change',
        field        => 'bio',
        input        => $input,
        method       => 'update_bio',
        required     => [qw(command_id user_id)],
    };
}

sub update_profile ( $self, $input ) {
    my $invalid = $self->_missing_fields( $input, [qw(command_id user_id)] );
    return $invalid if $invalid;
    return $self->_commanded_write(
        {
            %{ _profile_command($input) },
            run => sub {
                return _profile_answer(
                    $self->_store_write(
                        sub { return $self->store->update_profile($input); }
                    )
                );
            },
        }
    );
}

# update_profile on the worker's pooled asynchronous connections.
async sub update_profile_p ( $self, $input, $context = undef ) {
    return $self->update_profile($input) if !$self->_native;
    my $invalid = $self->_missing_fields( $input, [qw(command_id user_id)] );
    return $invalid if $invalid;
    return await $self->_commanded_write_p(
        {
            %{ _profile_command($input) },
            run_p => async sub ($scope) {
                return _profile_answer(
                    await $self->_store_write_p(
                        sub {
                            return $self->store->update_profile_p( $input,
                                $context, $scope );
                        }
                    )
                );
            },
        },
        $context
    );
}

sub _profile_command ($input) {
    return {
        actor_id     => $input->{user_id},
        command_id   => $input->{command_id},
        command_type => 'identity.profile_change',
        request      => {
            map { $_ => trimmed( $input->{$_} ) } qw(user_id display_name bio)
        },
    };
}

sub _profile_answer ($result) {
    return $result if !$result->{ok};
    return workflow_result(
        status => 'ok',
        stored => {
            ok => 1,
            map { $_ => $result->{stored}{$_} } qw(display_name bio)
        }
    );
}

# An empty zone is a choice (the forum's default), so only the command and
# the member are required.
sub update_preferred_timezone ( $self, $input ) {
    return $self->_preference_write( _timezone_job($input) );
}

# update_preferred_timezone on the worker's pooled asynchronous connections.
async sub update_preferred_timezone_p ( $self, $input, $context = undef ) {
    return await $self->_preference_write_p( _timezone_job($input), $context );
}

sub _timezone_job ($input) {
    return {
        command_type => 'identity.timezone_change',
        field        => 'preferred_timezone',
        input        => $input,
        method       => 'update_preferred_timezone',
        required     => [qw(command_id user_id)],
    };
}

# A preference write answers with the value stored and nothing else.
sub _preference_write ( $self, $job ) {
    my $invalid = $self->_missing_fields( $job->{input}, $job->{required} );
    return $invalid if $invalid;

    my $method = $job->{method};
    return $self->_commanded_write(
        {
            %{ _preference_command($job) },
            run => sub {
                return _preference_answer(
                    $job->{field},
                    $self->_store_write(
                        sub { return $self->store->$method( $job->{input} ); }
                    )
                );
            },
        }
    );
}

async sub _preference_write_p ( $self, $job, $context ) {
    return $self->_preference_write($job) if !$self->_native;
    my $invalid = $self->_missing_fields( $job->{input}, $job->{required} );
    return $invalid if $invalid;

    my $method = $job->{method} . '_p';
    return await $self->_commanded_write_p(
        {
            %{ _preference_command($job) },
            run_p => async sub ($scope) {
                return _preference_answer(
                    $job->{field},
                    await $self->_store_write_p(
                        sub {
                            return $self->store->$method( $job->{input},
                                $context, $scope );
                        }
                    )
                );
            },
        },
        $context
    );
}

sub _preference_command ($job) {
    my $input = $job->{input};
    my $field = $job->{field};
    return {
        actor_id     => $input->{user_id},
        command_id   => $input->{command_id},
        command_type => $job->{command_type},
        request      => {
            $field  => trimmed( $input->{$field} ),
            user_id => $input->{user_id},
        },
    };
}

sub _preference_answer ( $field, $result ) {
    return $result if !$result->{ok};
    return workflow_result(
        status => 'ok',
        stored => {
            ok     => 1,
            $field => $result->{stored}{$field},
        },
    );
}

# Whether the writes run natively on the pooled asynchronous connections:
# the store is on PostgreSQL, and so is the command log when there is one.
# Doubles keep the blocking path.
sub _native ($self) {
    return 0 if !_call_layer( $self->store );
    return 1 if !$self->command_idempotency;
    return _call_layer( $self->command_idempotency ) ? 1 : 0;
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
    my $request = _register_request($input);

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
        my $invalid = _invalid_registration($prepared);
        my $row     = $self->_registered( $log, { answer => $invalid } );
        return $row->{result} // $invalid;
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
        my $row = $self->_registered( $log,
            _register_documents( $call, $input, $prepared, $refused ) );
        if ( $row->{retry} && $attempt < $REGISTER_ATTEMPTS ) {
            $registration->{user}{id} = $self->store->id_service->uuid;
            next;
        }
        return $self->_registration_result( $row, $prepared, $refused );
    }
    return _failed_result();
}

# register on the worker's pooled asynchronous connections: the password
# hashed in a child of the CPU lane, then the registration as one call
# (api.identity_register_command), as _register_by_function makes it.
async sub register_p ( $self, $input, $context = undef ) {
    return $self->register($input)
      if !$self->command_idempotency || !$self->_functions;
    my $invalid = $self->_missing_fields( $input, ['command_id'] );
    return $invalid if $invalid;

    my $log =
      $self->_command_log( $input, $REGISTER, _register_request($input) );
    my $tried = await $self->_try_store_p(
        sub { return $self->registration->prepare_p($input); } );
    my $prepared = $tried->{value};
    if ( $tried->{failed} || !$prepared ) {
        return _failed_result();
    }
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
    if ( !$row->{recorded} ) {
        return $row->{result} // _failed_result();
    }
    if ( ( $row->{response}{status} // q{} ) ne 'ok' ) {
        return $refused;
    }
    return workflow_result(
        status => 'ok',
        stored => {
            registration => $prepared->{registration},
            user => GPForum::Infrastructure::ResultRow::IdentityUser->from(
                $row->{stored_user}, $self->_functions
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
sub _registered ( $self, $log, $call ) {
    my $row;
    try {
        $row = $self->_functions->row( 'identity_register_command',
            _register_parameters( $log, $call ) );
    }
    catch ($error) {
        return $self->_register_failure($error);
    };
    return _register_outcome($row);
}

async sub _registered_p ( $self, $log, $call, $context ) {
    my $row;
    try {
        $row = await $self->_functions->row_p( 'identity_register_command',
            _register_parameters( $log, $call ), $context );
    }
    catch ($error) {
        return $self->_register_failure($error);
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

sub _register_failure ( $self, $error ) {
    my $conflict = GPForum::X::Conflict->caught($error);
    return { retry => 1 }
      if $conflict && $conflict->on($USER_ID_CONSTRAINT);
    log_error( $self->logger, "identity command log failed: $error" );
    return { result => _failed_result() };
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

# A write that consumes a token: the job names the command, the run writes.
sub _token_consume_write ( $self, $job, $run ) {
    my $invalid = $self->_token_missing($job);
    if ($invalid) {
        return $invalid;
    }

    return $self->_commanded_write(
        {
            %{ _token_command($job) },
            run => sub {
                return $self->_public_consume_result($run);
            },
        }
    );
}

# _token_consume_write on the pooled connections: $run_p takes the call
# layer to write on.
async sub _token_consume_write_p ( $self, $job, $run_p, $context ) {
    my $invalid = $self->_token_missing($job);
    return $invalid if $invalid;

    return await $self->_commanded_write_p(
        {
            %{ _token_command($job) },
            run_p => sub ($scope) {
                return $self->_public_consume_result_p(
                    sub { return $run_p->($scope); } );
            },
        },
        $context
    );
}

sub _token_missing ( $self, $job ) {
    return $self->_missing_fields( $job->{input},
        [ 'command_id', 'token', @{ $job->{extra_fields} || [] } ] );
}

sub _token_command ($job) {
    my $input = $job->{input};
    return {
        actor_id     => undef,
        command_id   => $input->{command_id},
        command_type => $job->{command_type},
        refusal      => $job->{refusal},
        request      => { token => trimmed( $input->{token} ) },
    };
}

sub _public_consume_result ( $self, $code ) {
    return _consumed( $self->_store_write($code) );
}

async sub _public_consume_result_p ( $self, $code ) {
    return _consumed( await $self->_store_write_p($code) );
}

sub _consumed ($result) {
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

# _commanded_write on the worker's pooled asynchronous connections. The
# job's run_p takes the call layer to write on: the command log's
# transaction, or the store's own without a command log. A failed or
# abandoned answer rolls the whole command back, as the blocking log does.
async sub _commanded_write_p ( $self, $job, $context ) {
    if ( !$self->command_idempotency ) {
        return await $job->{run_p}->( _call_layer( $self->store ) );
    }

    my $result;
    try {
        $result = await $self->command_idempotency->result_of_p(
            {
                actor_id     => $job->{actor_id},
                command_id   => trimmed( $job->{command_id} ),
                command_type => $job->{command_type},
                request      => $job->{request} || {},
                refusal      => $job->{refusal},
                response     => \&_command_log_response,
                run_p        => $job->{run_p},
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

# A write that issues a token answers without its raw value or its hash.
sub _commanded_token_write ( $self, $job ) {
    return $self->_commanded_write(
        {
            %{ _command_of($job) },
            run => sub {
                return _issued( $self->_store_write( $job->{run} ) );
            },
        }
    );
}

# _commanded_token_write on the pooled connections: the job's run_p takes
# the call layer to write on.
async sub _commanded_token_write_p ( $self, $job, $context ) {
    return await $self->_commanded_write_p(
        {
            %{ _command_of($job) },
            run_p => async sub ($scope) {
                return _issued(
                    await $self->_store_write_p(
                        sub { return $job->{run_p}->($scope); }
                    )
                );
            },
        },
        $context
    );
}

sub _command_of ($job) {
    return { map { $_ => $job->{$_} }
          qw(actor_id command_id command_type refusal request) };
}

sub _issued ($result) {
    return $result if !$result->{ok};

    return _public_write_result($result);
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
    return _stored( $self->_try_store($code) );
}

# A store's answer as a workflow result: failed when it died or answered
# nothing, invalid with its reason, or ok with what it stored.
sub _stored ($tried) {
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

async sub _store_write_p ( $self, $code ) {
    return _stored( await $self->_try_store_p($code) );
}

async sub _try_store_p ( $self, $code ) {
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

=head2 register_p

L</register> as a promise, with an optional query context last: Argon2 in
a child of the CPU lane on plain data, then the registration as one call
on the worker's pooled asynchronous connections. Without a command log or
the call layer it is answered by L</register>.

=head2 login

Authenticates an identifier and password, which it requires; it records
no command. Failed credentials are C<rejected> without enumerating whether the account exists.
A member with two-step sign-in on (ADR 0142) is answered with status
C<second_factor> and the challenge's C<challenge_token> instead of a
session, or C<second_factor_locked>.

=head2 login_p

L</login> as a promise, with an optional query context last: the reads
and the session on the worker's pooled asynchronous connections, Argon2
in a child of the CPU lane on plain data. Doubles are answered by
L</login>.

=head2 complete_second_factor

Takes C<challenge_token>, C<code>, C<request_address> and C<user_agent>
and answers the challenge: status C<ok> with the session as L</login>
answers it, plus C<method> and C<recovery_left>; or C<expired>, C<wrong>
(with C<attempts_left>), C<locked> or C<failed>.

=head2 complete_second_factor_p

L</complete_second_factor> as a promise, with an optional query context
last, on the worker's pooled asynchronous connections.

=head2 logout

Revokes a server-side session when a session id is present. Requires
C<command_id>. Command hashes include C<session_id> and C<user_id> only.

=head2 logout_p

L</logout> as a promise, with an optional query context last: the command
log's steps and the write commit in one transaction on the worker's
pooled asynchronous connections, no child process. Doubles of the store or
the command log are answered by L</logout>.

=head2 request_password_reset

Starts a password reset for an identifier. Requires C<command_id>.

=head2 request_password_reset_p

Starts the reset as L</request_password_reset> does,
on the worker's pooled asynchronous connections: the command log's
steps and the store's writes commit in one transaction, Argon2 runs in a
child of the CPU lane, and no child process touches PostgreSQL. Takes an
optional query context last and answers a promise of the same result;
with a double for the store or the command log the blocking write answers.

=head2 reset_password

Completes a password reset with a token. Requires C<command_id>.
A reset to the same secret still revokes sessions. The command's request
names the token alone, never the password, so its refusals are not its
answers: the log abandons them (L<GPForum::Service::Operations::CommandIdempotency/run>,
C<< refusal => 'abandon' >>), and the form sent again under the same
command id with the password corrected runs.

=head2 reset_password_p

Completes the reset as L</reset_password> does,
on the worker's pooled asynchronous connections: the command log's
steps and the store's writes commit in one transaction, Argon2 runs in a
child of the CPU lane, and no child process touches PostgreSQL. Takes an
optional query context last and answers a promise of the same result;
with a double for the store or the command log the blocking write answers.

=head2 change_password

Changes the password of an authenticated member. Requires C<command_id>.
Command hashes include C<user_id> only, never the current or new password,
so a refusal (the current password wrong, the new one weak) is not the
command's answer: the log abandons it, and the form sent again under the
same command id with the passwords corrected runs instead of getting the
refusal back.

=head2 change_password_p

Changes the password as L</change_password> does,
on the worker's pooled asynchronous connections: the command log's
steps and the store's writes commit in one transaction, Argon2 runs in a
child of the CPU lane, and no child process touches PostgreSQL. Takes an
optional query context last and answers a promise of the same result;
with a double for the store or the command log the blocking write answers.

=head2 request_email_change

Starts an email change for an authenticated member. Requires C<command_id>
and C<current_password>, which the store checks; command hashes include the
address and C<user_id>, never the password, so the log abandons a refusal
as it does for L</change_password>. A request for the member's
already-verified address does not issue a token.

=head2 request_email_change_p

Requests the change as L</request_email_change> does,
on the worker's pooled asynchronous connections: the command log's
steps and the store's writes commit in one transaction, Argon2 runs in a
child of the CPU lane, and no child process touches PostgreSQL. Takes an
optional query context last and answers a promise of the same result;
with a double for the store or the command log the blocking write answers.

=head2 confirm_email_change

Completes an email change with a token. Requires C<command_id>.

=head2 confirm_email_change_p

Confirms the change as L</confirm_email_change> does,
on the worker's pooled asynchronous connections: the command log's
steps and the store's writes commit in one transaction, Argon2 runs in a
child of the CPU lane, and no child process touches PostgreSQL. Takes an
optional query context last and answers a promise of the same result;
with a double for the store or the command log the blocking write answers.

=head2 request_email_verification

Starts a registration verification resend for an identifier. Requires
C<command_id>.

=head2 request_email_verification_p

Starts the verification as L</request_email_verification> does,
on the worker's pooled asynchronous connections: the command log's
steps and the store's writes commit in one transaction, Argon2 runs in a
child of the CPU lane, and no child process touches PostgreSQL. Takes an
optional query context last and answers a promise of the same result;
with a double for the store or the command log the blocking write answers.

=head2 verify_email

Completes registration verification with a token. Requires C<command_id>.

=head2 verify_email_p

Completes the verification as L</verify_email> does,
on the worker's pooled asynchronous connections: the command log's
steps and the store's writes commit in one transaction, Argon2 runs in a
child of the CPU lane, and no child process touches PostgreSQL. Takes an
optional query context last and answers a promise of the same result;
with a double for the store or the command log the blocking write answers.

=head2 update_preferred_locale

Persists an authenticated member locale preference. Requires C<command_id>.

=head2 update_preferred_locale_p

L</update_preferred_locale> as a promise, with an optional query context last: the command
log's steps and the write commit in one transaction on the worker's
pooled asynchronous connections, no child process. Doubles of the store or
the command log are answered by L</update_preferred_locale>.

=head2 update_preferred_timezone

Persists a member's time zone, or the forum's default for an empty one.
Requires C<command_id>.

=head2 update_preferred_timezone_p

L</update_preferred_timezone> as a promise, with an optional query context last: the command
log's steps and the write commit in one transaction on the worker's
pooled asynchronous connections, no child process. Doubles of the store or
the command log are answered by L</update_preferred_timezone>.

=head2 update_bio

Persists the few words a member shows on their profile (C<bio>, plain
text up to 500 characters; empty takes it down). Requires C<command_id>.

=head2 update_bio_p

L</update_bio> as a promise, with an optional query context last: the command
log's steps and the write commit in one transaction on the worker's
pooled asynchronous connections, no child process. Doubles of the store or
the command log are answered by L</update_bio>.

=head2 update_profile

Saves a member's display name and biography with an independent idempotent command.
Recorded responses retain no profile text.

=head2 update_profile_p

L</update_profile> as a promise, with an optional query context last: the command
log's steps and the write commit in one transaction on the worker's
pooled asynchronous connections, no child process. Doubles of the store or
the command log are answered by L</update_profile>.

=head2 update_preferred_theme

Persists an authenticated member theme preference. Requires C<command_id>.

=head2 update_preferred_theme_p

L</update_preferred_theme> as a promise, with an optional query context last: the command
log's steps and the write commit in one transaction on the worker's
pooled asynchronous connections, no child process. Doubles of the store or
the command log are answered by L</update_preferred_theme>.

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
