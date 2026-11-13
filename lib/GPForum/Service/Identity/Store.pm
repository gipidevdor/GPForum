# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::Store;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::Service::Identity::AccountStore;
use GPForum::Service::Identity::Audit;
use GPForum::Service::Identity::AuthStore;
use GPForum::Service::Identity::CredentialStore;
use GPForum::Service::Identity::PreferenceStore;
use GPForum::Service::Identity::RegistrationStore;
use GPForum::Service::Identity::SecondFactor;
use GPForum::Service::Identity::SessionStore;
use GPForum::Service::Identity::Support;
use GPForum::Service::Identity::TokenStore;
use GPForum::Service::Password;
use GPForum::Service::SessionToken;

our $VERSION = '0.001';

const my $DAY_SECONDS  => 86_400;
const my $SESSION_DAYS => 30;

has schema => undef;    # optional: handed to the stores it builds lazily

# The call layer (Infrastructure::SqlFunction) on PostgreSQL, handed to
# every store built here so the stores and the workflow share it. The stores
# have no other path (ADR 0177): without it they raise Unavailable.
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# A workflow's blocking twin settles its promise method on a copy of this
# store (ADR 0177); the stores it forwards to are copied onto the blocking
# layer with it, or a login would wait on Argon2 in a child the settled
# promise never sees finish.
GPForum::Infrastructure::SqlFunction->blocking_parts(
    qw(account_store auth_store credential_store preference_store
      registration_store session_store token_store)
);
has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
has password => sub { return GPForum::Service::Password->new; };
has recorder => sub {
    my ($self) = @_;

    return GPForum::Infrastructure::EventRecorder->new(
        functions  => $self->functions,
        id_service => $self->id_service,
        schema     => $self->schema,
    );
};
has session_tokens  => sub { return GPForum::Service::SessionToken->new; };
has session_seconds => sub { return $SESSION_DAYS * $DAY_SECONDS; };
has session_touch_interval_seconds => undef;    # optional: SessionStore default
has support => sub { return GPForum::Service::Identity::Support->new; };

# ADR 0142: two-step sign-in, which a login asks for once the password
# verifies (Service::Identity::SecondFactor). Without the configured keys
# a member who has it on is still asked, and cannot answer: it fails
# closed.
has second_factor => sub ($self) {
    return GPForum::Service::Identity::SecondFactor->new(
        schema => $self->schema );
};
has mail_token => undef;    # optional: Audit seals with the configured secrets
has audit      => sub {
    my ($self) = @_;

    return GPForum::Service::Identity::Audit->new(
        clock      => $self->clock,
        id_service => $self->id_service,
        recorder   => $self->recorder,
        schema     => $self->schema,
        ( $self->mail_token ? ( mail_token => $self->mail_token ) : () ),
    );
};
has credential_store => sub {
    my ($self) = @_;

    return GPForum::Service::Identity::CredentialStore->new(
        functions  => $self->functions,
        clock      => $self->clock,
        id_service => $self->id_service,
        schema     => $self->schema,
        support    => $self->support,
    );
};
has session_store => sub {
    my ($self) = @_;

    return GPForum::Service::Identity::SessionStore->new(
        functions       => $self->functions,
        clock           => $self->clock,
        id_service      => $self->id_service,
        schema          => $self->schema,
        session_seconds => $self->session_seconds,
        session_tokens  => $self->session_tokens,
        support         => $self->support,
        _session_touch_arguments($self),
    );
};
has token_store => sub {
    my ($self) = @_;

    return GPForum::Service::Identity::TokenStore->new(
        functions      => $self->functions,
        clock          => $self->clock,
        id_service     => $self->id_service,
        schema         => $self->schema,
        session_tokens => $self->session_tokens,
        support        => $self->support,
    );
};
has preference_store => sub {
    my ($self) = @_;

    return GPForum::Service::Identity::PreferenceStore->new(
        functions => $self->functions,
        clock     => $self->clock,
        schema    => $self->schema,
        support   => $self->support,
    );
};
has account_store => sub {
    my ($self) = @_;

    return GPForum::Service::Identity::AccountStore->new(
        functions        => $self->functions,
        audit            => $self->audit,
        clock            => $self->clock,
        credential_store => $self->credential_store,
        password         => $self->password,
        schema           => $self->schema,
        session_store    => $self->session_store,
        support          => $self->support,
        token_store      => $self->token_store,
    );
};
has auth_store => sub {
    my ($self) = @_;

    return GPForum::Service::Identity::AuthStore->new(
        functions        => $self->functions,
        credential_store => $self->credential_store,
        password         => $self->password,
        schema           => $self->schema,
        second_factor    => $self->second_factor,
        session_store    => $self->session_store,
        support          => $self->support,
    );
};
has registration_store => sub {
    my ($self) = @_;

    return GPForum::Service::Identity::RegistrationStore->new(
        functions        => $self->functions,
        audit            => $self->audit,
        credential_store => $self->credential_store,
        id_service       => $self->id_service,
        schema           => $self->schema,
    );
};

sub create_registration ( $self, $registration ) {
    return $self->registration_store->create_registration($registration);
}

# What a registration as one call sends (api.identity_register_command):
# the rows and the documents create_registration and the verification
# request would write one by one, drawn in the order they would draw them.
# The raw token goes to the mail's outbox payload, as record_mail's does,
# and is answered to the caller for nothing else.
sub register_call ( $self, $registration, $input = {} ) {
    my $user       = $registration->{user};
    my $credential = $registration->{credential};
    $user->{password_hash} ||= $credential->{secret_hash};
    my $credential_row = $self->credential_store->new_password_credential_row(
        {
            secret_hash => $credential->{secret_hash},
            type        => $credential->{type},
            user_id     => $user->{id},
        }
    );
    my $recorded =
      $self->audit->registration_calls( $user, $self->id_service->uuid );
    my $verification =
      $self->account_store->verification_calls( $user, $input );
    return {
        user               => $user,
        credential         => $credential_row,
        event              => $recorded->{event}{event},
        event_outbox_id    => $recorded->{event}{outbox_id},
        audit              => $recorded->{audit}{audit},
        token              => $verification->{token},
        token_audit        => $verification->{audit}{audit},
        mail_event         => $verification->{mail}{event},
        mail_outbox_id     => $verification->{mail}{outbox_id},
        mail_outbox_extras => $verification->{mail}{outbox_extras},
    };
}

sub authenticate_login ( $self, $input ) {
    return $self->auth_store->authenticate_login($input);
}

sub account_id_for ( $self, $identifier ) {
    return $self->auth_store->account_id_for($identifier);
}

sub account_id_for_p ( $self, $identifier, $context = undef ) {
    return $self->auth_store->account_id_for_p( $identifier, $context );
}

sub complete_second_factor ( $self, $input ) {
    return $self->auth_store->complete_second_factor($input);
}

sub request_password_reset ( $self, $input ) {
    return $self->account_store->request_password_reset($input);
}

sub reset_password ( $self, $input ) {
    return $self->account_store->reset_password($input);
}

sub change_password ( $self, $input ) {
    return $self->account_store->change_password($input);
}

sub request_email_change ( $self, $input ) {
    return $self->account_store->request_email_change($input);
}

sub confirm_email_change ( $self, $input ) {
    return $self->account_store->confirm_email_change($input);
}

sub request_email_verification ( $self, $input ) {
    return $self->account_store->request_email_verification($input);
}

sub confirm_email_verification ( $self, $input ) {
    return $self->account_store->confirm_email_verification($input);
}

sub revoke_session ( $self, $input ) {
    return $self->session_store->revoke_session($input);
}

sub live_session_ids_p ( $self, $session_ids, $context = undef ) {
    return $self->session_store->live_session_ids_p( $session_ids, $context );
}

sub live_session_ids ( $self, $session_ids ) {
    return $self->session_store->live_session_ids($session_ids);
}

sub validate_session ( $self, $input ) {
    return $self->session_store->validate_session($input);
}

sub validate_session_p ( $self, $input, $context = undef ) {
    return $self->session_store->validate_session_p( $input, $context );
}

sub preferred_locale_for_user ( $self, $input ) {
    return $self->preference_store->preferred_locale_for_user($input);
}

sub update_preferred_locale ( $self, $input ) {
    return $self->preference_store->update_preferred_locale($input);
}

sub preferred_theme_for_user ( $self, $input ) {
    return $self->preference_store->preferred_theme_for_user($input);
}

sub update_preferred_theme ( $self, $input ) {
    return $self->preference_store->update_preferred_theme($input);
}

sub update_preferred_timezone ( $self, $input ) {
    return $self->preference_store->update_preferred_timezone($input);
}

sub bio_for_user ( $self, $input ) {
    return $self->preference_store->bio_for_user($input);
}

sub profile_for_user ( $self, $input ) {
    return $self->preference_store->profile_for_user($input);
}

sub profile_for_user_p ( $self, $input, $context = undef ) {
    return $self->preference_store->profile_for_user_p( $input, $context );
}

sub update_profile ( $self, $input ) {
    return $self->preference_store->update_profile($input);
}

sub update_bio ( $self, $input ) {
    return $self->preference_store->update_bio($input);
}

# The writes above as promises on the worker's pooled asynchronous
# connections, each with an optional query context and call layer (the
# transaction a command log holds) last.
sub authenticate_login_p ( $self, @arguments ) {
    return $self->auth_store->authenticate_login_p(@arguments);
}

sub complete_second_factor_p ( $self, @arguments ) {
    return $self->auth_store->complete_second_factor_p(@arguments);
}

sub revoke_session_p ( $self, @arguments ) {
    return $self->session_store->revoke_session_p(@arguments);
}

sub update_preferred_locale_p ( $self, @arguments ) {
    return $self->preference_store->update_preferred_locale_p(@arguments);
}

sub update_preferred_theme_p ( $self, @arguments ) {
    return $self->preference_store->update_preferred_theme_p(@arguments);
}

sub update_preferred_timezone_p ( $self, @arguments ) {
    return $self->preference_store->update_preferred_timezone_p(@arguments);
}

sub update_profile_p ( $self, @arguments ) {
    return $self->preference_store->update_profile_p(@arguments);
}

sub update_bio_p ( $self, @arguments ) {
    return $self->preference_store->update_bio_p(@arguments);
}

sub request_password_reset_p ( $self, @arguments ) {
    return $self->account_store->request_password_reset_p(@arguments);
}

sub reset_password_p ( $self, @arguments ) {
    return $self->account_store->reset_password_p(@arguments);
}

sub change_password_p ( $self, @arguments ) {
    return $self->account_store->change_password_p(@arguments);
}

sub request_email_change_p ( $self, @arguments ) {
    return $self->account_store->request_email_change_p(@arguments);
}

sub confirm_email_change_p ( $self, @arguments ) {
    return $self->account_store->confirm_email_change_p(@arguments);
}

sub request_email_verification_p ( $self, @arguments ) {
    return $self->account_store->request_email_verification_p(@arguments);
}

sub confirm_email_verification_p ( $self, @arguments ) {
    return $self->account_store->confirm_email_verification_p(@arguments);
}

sub _session_touch_arguments ($self) {
    if ( !defined $self->session_touch_interval_seconds ) {
        return;
    }

    return ( session_touch_interval_seconds =>
          $self->session_touch_interval_seconds );
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::Store - Identity write workflow.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Identity::Store->new(schema => $schema);

=head1 DESCRIPTION

Coordinates identity writes by delegating to dedicated stores. Registration,
login, password, email, session, and preference persistence live outside this
facade.

=head1 SUBROUTINES/METHODS

=head2 register_call

Takes a prepared registration (its C<user> and C<credential>) and the
request, and returns what C<api.identity_register_command> takes after the
command log and the answers: the user row, the credential row, the
registration's event with its outbox id and its audit, the verification
token with its audit and its mail event, outbox id and outbox payload --
the rows and documents L</create_registration> and
L</request_email_verification> would write one by one, drawn in the order
they would draw them.

=head2 create_registration

Delegates prepared registration persistence to the registration store.

=head2 authenticate_login

Delegates credential verification and session creation to the auth store.

=head2 account_id_for

Takes a login identifier and returns the id of the account it names, or
C<undef>, through the auth store (L<GPForum::Service::Identity::AuthStore/account_id_for>).

=head2 account_id_for_p

L</account_id_for> as a promise, with an optional query context last, read
on the worker's pooled asynchronous connections
(L<GPForum::Service::Identity::AuthStore/account_id_for_p>).

=head2 complete_second_factor

Delegates the second step of a sign-in to the auth store (ADR 0142).

=head2 request_password_reset

Delegates password-reset issuance to the account store.

=head2 reset_password

Delegates reset completion to the account store.

=head2 change_password

Delegates authenticated password rotation to the account store.

=head2 request_email_change

Delegates email-change issuance to the account store.

=head2 confirm_email_change

Delegates email-change confirmation to the account store.

=head2 request_email_verification

Delegates registration verification issuance to the account store.

=head2 confirm_email_verification

Delegates registration verification completion to the account store.

=head2 revoke_session

Revokes one server session.

=head2 authenticate_login_p

L</authenticate_login> as a promise, with an optional query context last
(L<GPForum::Service::Identity::AuthStore/authenticate_login_p>).

=head2 complete_second_factor_p

L</complete_second_factor> as a promise, with an optional query context
last (L<GPForum::Service::Identity::AuthStore/complete_second_factor_p>).

=head2 revoke_session_p

L</revoke_session> as a promise, with an optional query context and call
layer last (L<GPForum::Service::Identity::SessionStore/revoke_session_p>).

=head2 update_preferred_locale_p

L</update_preferred_locale> as a promise, with an optional query context and call layer last
(L<GPForum::Service::Identity::PreferenceStore/update_preferred_locale_p>).

=head2 update_preferred_theme_p

L</update_preferred_theme> as a promise, with an optional query context and call layer last
(L<GPForum::Service::Identity::PreferenceStore/update_preferred_theme_p>).

=head2 update_preferred_timezone_p

L</update_preferred_timezone> as a promise, with an optional query context and call layer last
(L<GPForum::Service::Identity::PreferenceStore/update_preferred_timezone_p>).

=head2 update_profile_p

L</update_profile> as a promise, with an optional query context and call layer last
(L<GPForum::Service::Identity::PreferenceStore/update_profile_p>).

=head2 update_bio_p

L</update_bio> as a promise, with an optional query context and call layer last
(L<GPForum::Service::Identity::PreferenceStore/update_bio_p>).

=head2 request_password_reset_p

L</request_password_reset> as a promise on the worker's pooled asynchronous connections,
with an optional query context and call layer (the transaction a command
log holds) last.

=head2 reset_password_p

L</reset_password> as a promise on the worker's pooled asynchronous connections,
with an optional query context and call layer (the transaction a command
log holds) last.

=head2 change_password_p

L</change_password> as a promise on the worker's pooled asynchronous connections,
with an optional query context and call layer (the transaction a command
log holds) last.

=head2 request_email_change_p

L</request_email_change> as a promise on the worker's pooled asynchronous connections,
with an optional query context and call layer (the transaction a command
log holds) last.

=head2 confirm_email_change_p

L</confirm_email_change> as a promise on the worker's pooled asynchronous connections,
with an optional query context and call layer (the transaction a command
log holds) last.

=head2 request_email_verification_p

L</request_email_verification> as a promise on the worker's pooled asynchronous connections,
with an optional query context and call layer (the transaction a command
log holds) last.

=head2 confirm_email_verification_p

L</confirm_email_verification> as a promise on the worker's pooled asynchronous connections,
with an optional query context and call layer (the transaction a command
log holds) last.

=head2 live_session_ids

The sessions of those given that are still live, as a set (ADR 0148).

=head2 validate_session

Validates and refreshes a live server session.

=head2 preferred_locale_for_user

Delegates locale reads to the preference store.

=head2 update_preferred_locale

Delegates locale writes to the preference store.

=head2 update_preferred_timezone

Delegates to L<GPForum::Service::Identity::PreferenceStore>.

=head2 profile_for_user

Reads the member's public name, biography and profile username.

=head2 profile_for_user_p

L</profile_for_user> as a promise, with an optional query context last, read
on the worker's pooled asynchronous connections.

=head2 update_profile

Read and save the member's public display name and biography through the preference store.

=head2 bio_for_user

The preference store's L<GPForum::Service::Identity::PreferenceStore/bio_for_user>.

=head2 update_bio

The preference store's L<GPForum::Service::Identity::PreferenceStore/update_bio>.

=head2 preferred_theme_for_user

Delegates theme reads to the preference store.

=head2 update_preferred_theme

Delegates theme writes to the preference store.

=head2 live_session_ids_p

Returns a promise for the set of live session ids, using one bounded native query. Invalid ids are omitted; no socket is closed when the lookup fails.

=head2 validate_session_p

Validates and touches the server session through a native promise. Accepts the same input as C<validate_session> and an optional request observation context.

=head1 DIAGNOSTICS

Duplicate usernames/emails return field errors. Invalid credentials return
C<invalid_credentials>.

=head1 CONFIGURATION AND ENVIRONMENT

Requires a PostgreSQL schema: the stores it builds call the function
layer (L<GPForum::Infrastructure::SqlFunction>) and have no other path.

=head1 DEPENDENCIES

Uses the identity registration, account, auth, credential, session, token,
preference, and audit stores.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Preference updates are not transactional with notification settings.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
