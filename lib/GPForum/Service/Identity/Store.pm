# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
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
use GPForum::Service::Identity::SessionStore;
use GPForum::Service::Identity::Support;
use GPForum::Service::Identity::TokenStore;
use GPForum::Service::Password;
use GPForum::Service::SessionToken;

our $VERSION = '0.001';

const my $DAY_SECONDS  => 86_400;
const my $SESSION_DAYS => 30;

has schema => undef;    # optional: handed to the stores it builds lazily

# The call layer (Infrastructure::SqlFunction) on PostgreSQL, undef on a
# double, handed to every store built here so the stores and the workflow
# take the same path; a differential test passes undef to keep the Perl one.
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};
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
has audit   => sub {
    my ($self) = @_;

    return GPForum::Service::Identity::Audit->new(
        id_service => $self->id_service,
        recorder   => $self->recorder,
        schema     => $self->schema,
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

sub validate_session ( $self, $input ) {
    return $self->session_store->validate_session($input);
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

sub update_bio ( $self, $input ) {
    return $self->preference_store->update_bio($input);
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

=head2 validate_session

Validates and refreshes a live server session.

=head2 preferred_locale_for_user

Delegates locale reads to the preference store.

=head2 update_preferred_locale

Delegates locale writes to the preference store.

=head2 update_preferred_timezone

Delegates to L<GPForum::Service::Identity::PreferenceStore>.

=head2 bio_for_user

The preference store's L<GPForum::Service::Identity::PreferenceStore/bio_for_user>.

=head2 update_bio

The preference store's L<GPForum::Service::Identity::PreferenceStore/update_bio>.

=head2 preferred_theme_for_user

Delegates theme reads to the preference store.

=head2 update_preferred_theme

Delegates theme writes to the preference store.

=head1 DIAGNOSTICS

Duplicate usernames/emails return field errors. Invalid credentials return
C<invalid_credentials>.

=head1 CONFIGURATION AND ENVIRONMENT

Requires a DBIx::Class schema with User, Credential, Session, and
IdentityToken resultsets.

=head1 DEPENDENCIES

Uses the identity registration, account, auth, credential, session, token,
preference, and audit stores.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Preference updates are not transactional with notification settings.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
