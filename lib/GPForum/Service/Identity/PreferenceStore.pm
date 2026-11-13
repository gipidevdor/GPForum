# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::PreferenceStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow::IdentityUser;

use DateTime::TimeZone;

use GPForum::Infrastructure::Text qw(has_text trimmed);
use GPForum::Service::Clock;
use GPForum::Service::Identity::Support;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $BIO_MAX          => 500;
const my $DISPLAY_NAME_MAX => 100;

has clock => sub { return GPForum::Service::Clock->new; };
__PACKAGE__->requires(qw(schema));
has support => sub { return GPForum::Service::Identity::Support->new; };

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(bio_for_user profile_for_user update_profile update_bio
      preferred_locale_for_user preferred_theme_for_user
      update_preferred_locale update_preferred_theme
      update_preferred_timezone)
);

async sub bio_for_user_p ( $self, $input, $context = undef ) {
    return await $self->_read_preference_p( $input, 'bio', $context );
}

# The settings page's read.
async sub profile_for_user_p ( $self, $input, $context = undef ) {
    my $user = await $self->_find_user_by_id_p( $input->{user_id}, $context );
    return { error => 'not_found', ok => 0 } if !$user;
    return {
        ok => 1,
        map { $_ => $self->support->column( $user, $_ ) }
          qw(username display_name bio)
    };
}

# Both public fields are saved together. The session supplies the account id;
# no submitted account identifier or administrative field is accepted. On
# $scope: the transaction a command log runs it in.
async sub update_profile_p ( $self, $input, $context = undef, $scope = undef ) {
    my $refused = _refused_profile($input);
    return $refused if $refused;
    $scope //= $self->_functions;
    my $plan = _profile_plan(
        await $self->_find_user_by_id_p( $input->{user_id}, $context, $scope ),
        $input
    );
    return $plan->{answer} if !$plan->{changes};

    my $row =
      await $scope->row_p( 'identity_update_profile', _profile_values($input),
        $context );
    return $row ? $plan->{answer} : { error => 'not_found', ok => 0 };
}

sub _refused_profile ($input) {
    my $name = trimmed( $input->{display_name} );
    return { error => 'display_name_invalid', ok => 0 }
      if !length $name
      || length $name > $DISPLAY_NAME_MAX
      || $name =~ /\p{Cc}/msx;
    return { error => 'bio_too_long', ok => 0 }
      if length _bio($input) > $BIO_MAX;

    return undef;
}

sub _bio ($input) {
    my $bio = trimmed( $input->{bio} );
    $bio =~ s/\r\n?/\n/gmsx;

    return $bio;
}

sub _profile_values ($input) {
    return {
        user_id      => $input->{user_id},
        display_name => trimmed( $input->{display_name} ),
        bio          => _bio($input),
    };
}

# What a checked profile does to the member: the answer, and the changes
# when there are any.
sub _profile_plan ( $user, $input ) {
    my $support = GPForum::Service::Identity::Support->new;
    return { answer => { error => 'not_found', ok => 0 } }
      if !$user
      || ( $support->column( $user, 'status' ) // q{} ) ne 'active';
    my $values = _profile_values($input);
    my %answer = (
        ok           => 1,
        display_name => $values->{display_name},
        bio          => $values->{bio},
    );
    return { answer => { %answer, skipped => 1 } }
      if $values->{display_name} eq
      ( $support->column( $user, 'display_name' ) // q{} )
      && $values->{bio} eq ( $support->column( $user, 'bio' ) // q{} );

    return {
        answer  => \%answer,
        user    => $user,
        changes => {
            display_name => $values->{display_name},
            bio          => $values->{bio}
        },
    };
}

# A few words about the member, plain text, up to $BIO_MAX characters;
# an empty bio is a bio taken down. Line ends are kept as the page shows
# them, one way. On $scope: the transaction a command log runs it in.
async sub update_bio_p ( $self, $input, $context = undef, $scope = undef ) {
    $scope //= $self->_functions;

    return await _written_p(
        $self->_bio_plan(
            await $self->_find_user_by_id_p( $input->{user_id}, $context,
                $scope ),
            $input
        ),
        $context, $scope
    );
}

sub _bio_plan ( $self, $user, $input ) {
    return { answer => { error => 'not_found', ok => 0 } } if !$user;
    my $bio = _bio($input);
    return { answer => { error => 'bio_too_long', ok => 0 } }
      if length $bio > $BIO_MAX;

    return $self->_plan(
        $user,
        { bio => $bio },
        ( $self->support->column( $user, 'bio' ) // q{} ) eq $bio
    );
}

# A plan's answer, with the user changed first when it holds changes.
sub _plan ( $self, $user, $values, $same ) {
    my %answer = ( %{$values}, ok => 1, user => $user );
    return { answer => { %answer, skipped => 1 } } if $same;

    return {
        answer  => \%answer,
        user    => $user,
        changes => { %{$values}, updated_at => $self->clock->now_iso8601 },
    };
}

async sub _written_p ( $plan, $context, $scope ) {
    if ( $plan->{changes} ) {
        await $plan->{user}->update_p( $plan->{changes}, $context, $scope );
    }

    return $plan->{answer};
}

async sub preferred_locale_for_user_p ( $self, $input, $context = undef ) {
    return await $self->_read_preference_p( $input, 'preferred_locale',
        $context );
}

async sub preferred_theme_for_user_p ( $self, $input, $context = undef ) {
    return await $self->_read_preference_p( $input, 'preferred_theme',
        $context );
}

# A non-empty locale. On $scope: the transaction a command log runs it in.
async sub update_preferred_locale_p (
    $self, $input,
    $context = undef,
    $scope = undef
  )
{
    return await $self->_update_preference_p(
        {
            column   => 'preferred_locale',
            input    => $input,
            required => 'locale_required',
        },
        $context, $scope
    );
}

# A non-empty theme. On $scope, as above.
async sub update_preferred_theme_p (
    $self, $input,
    $context = undef,
    $scope = undef
  )
{
    return await $self->_update_preference_p(
        {
            column   => 'preferred_theme',
            input    => $input,
            required => 'theme_required',
        },
        $context, $scope
    );
}

# 9.3. Unlike locale and theme, empty is a choice: the forum's default zone,
# stored as NULL so a member who never chose follows it if it changes. On
# $scope, as above.
async sub update_preferred_timezone_p (
    $self, $input,
    $context = undef,
    $scope = undef
  )
{
    $scope //= $self->_functions;

    return await _written_p(
        $self->_timezone_plan(
            await $self->_find_user_by_id_p( $input->{user_id}, $context,
                $scope ),
            $input
        ),
        $context, $scope
    );
}

sub _timezone_plan ( $self, $user, $input ) {
    return { answer => { error => 'not_found', ok => 0 } } if !$user;

    my $zone = trimmed( $input->{preferred_timezone} );
    if ( length $zone && !DateTime::TimeZone->is_valid_name($zone) ) {
        return { answer => { error => 'timezone_invalid', ok => 0 } };
    }

    my $value = length $zone ? $zone : undef;
    my $held  = $self->support->column( $user, 'preferred_timezone' );

    return $self->_plan(
        $user,
        { preferred_timezone => $value },
        ( $held // q{} ) eq ( $value // q{} )
    );
}

async sub _read_preference_p ( $self, $input, $column, $context ) {
    my $user = await $self->_find_user_by_id_p( $input->{user_id}, $context );
    if ( !$user ) {
        return { error => 'not_found', ok => 0 };
    }

    return {
        ok      => 1,
        $column => $self->support->column( $user, $column ),
        user    => $user,
    };
}

async sub _update_preference_p ( $self, $command, $context, $scope ) {
    $scope //= $self->_functions;

    return await _written_p(
        $self->_preference_plan(
            await $self->_find_user_by_id_p(
                $command->{input}{user_id},
                $context, $scope
            ),
            $command
        ),
        $context, $scope
    );
}

sub _preference_plan ( $self, $user, $command ) {
    return { answer => { error => 'not_found', ok => 0 } } if !$user;
    my $column  = $command->{column};
    my $trimmed = trimmed( $command->{input}{$column} );
    if ( !length $trimmed ) {
        return { answer => { error => $command->{required}, ok => 0 } };
    }
    my $held = $self->support->column( $user, $column );

    return $self->_plan(
        $user,
        { $column => $trimmed },
        defined $held && $held eq $trimmed
    );
}

# The member by id, its writes on $scope; undef for an empty id, which is
# not looked up.
async sub _find_user_by_id_p ( $self, $user_id, $context, $scope = undef ) {
    return undef if !has_text($user_id);
    $scope //= $self->_functions;

    return GPForum::Infrastructure::ResultRow::IdentityUser->from(
        await $scope->row_p(
            'identity_user_by_id', { user_id => $user_id }, $context
        ),
        $scope
    );
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'member preferences need the PostgreSQL database' );
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::PreferenceStore - Locale and theme persistence.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = $store->update_preferred_locale(
        {
            preferred_locale => $locale,
            user_id          => $user_id,
        }
    );

=head1 DESCRIPTION

Owns locale and theme preference reads and writes on the user row. The
identity store facade delegates to this object so HTTP and workflow callers
keep a stable API.

Each operation is written once, as its promise method, against the
PostgreSQL function layer; the blocking methods are its twins (ADR 0177).
There is no fallback: without the function layer a call that reads a
member raises L<GPForum::X::Unavailable>.

=head1 SUBROUTINES/METHODS

Every C<_p> method takes an optional query context after its arguments;
the writes take an optional call layer after it, the transaction a command
log holds.

=head2 preferred_locale_for_user_p

Answers C<< { ok => 1, preferred_locale, user } >> for a user id, or
C<not_found>.

=head2 preferred_theme_for_user_p

Answers C<< { ok => 1, preferred_theme, user } >> for a user id, or
C<not_found>.

=head2 bio_for_user_p

Takes C<user_id>. Answers C<< { ok => 1, bio, user } >>, or
C<< { ok => 0, error => 'not_found' } >>.

=head2 profile_for_user_p

Reads username, display name and biography for the account settings form.

=head2 update_preferred_locale_p

Persists a non-empty locale and refreshes C<updated_at>. A second write of
the same locale answers C<skipped> and does not restamp the user row.

=head2 update_preferred_theme_p

Persists a non-empty theme and refreshes C<updated_at>. A second write of
the same theme answers C<skipped> and does not restamp the user row.

=head2 update_preferred_timezone_p

Persists an IANA time zone, or NULL -- the forum's default -- for an empty
one. C<timezone_invalid> for a name the time zone database does not know.

=head2 update_profile_p

Saves the active member's public name (1 to 100 characters, no control
characters) and biography (at most 500 characters) together. An unchanged
profile is skipped.

=head2 update_bio_p

Takes C<user_id> and C<bio>: plain text, trimmed, line ends made one way,
up to 500 characters (C<bio_too_long> past that); empty takes the bio down.
Answers C<< { ok => 1, bio, user } >>, with C<skipped> when nothing
changed, or C<< { ok => 0, error } >>.

=head2 bio_for_user, profile_for_user, update_profile, update_bio, preferred_locale_for_user, preferred_theme_for_user, update_preferred_locale, update_preferred_theme, update_preferred_timezone

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise.

=head1 DIAGNOSTICS

Missing users answer C<not_found>. Empty values answer C<locale_required> or
C<theme_required>.

=head1 CONFIGURATION AND ENVIRONMENT

Requires the PostgreSQL function layer.

=head1 DEPENDENCIES

Uses L<GPForum::Infrastructure::SqlFunction> and
L<GPForum::Service::Identity::Support>.

Extends L<GPForum::Base>: built without C<schema> it throws
L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Preference writes are not transactional with notification settings.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
