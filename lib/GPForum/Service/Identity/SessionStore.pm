# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::SessionStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::Text qw(has_text);
use GPForum::Service::Clock;
use GPForum::Service::Identity::Support;
use GPForum::Service::SessionToken;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $SESSION_DAYS                   => 30;
const my $DAY_SECONDS                    => 86_400;
const my $DEFAULT_TOUCH_INTERVAL_SECONDS => 300;

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };
__PACKAGE__->requires(qw(schema));
has session_seconds => sub { return $SESSION_DAYS * $DAY_SECONDS; };
has session_touch_interval_seconds =>
  sub { return $DEFAULT_TOUCH_INTERVAL_SECONDS; };
has session_tokens => sub { return GPForum::Service::SessionToken->new; };
has support        => sub { return GPForum::Service::Identity::Support->new; };
has functions      => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(create_session revoke_session validate_session live_session_ids
      revoke_user_sessions)
);

# The raw token travels back to the caller so it can reach the cookie: the
# session_hash column holds the digest of the secret the cookie carries. See
# docs/QUALITY_PROGRAM.md 2.1.
#
# api.session_create inserts the row and recovers the first unique
# collision in a subtransaction: a session id already stored is this very
# session, committed by an earlier attempt, or another one, and then Perl
# mints a new id; a token hash already stored is reminted with its token,
# and that one is the token whose hash is stored and must reach the cookie.
# On $scope: the transaction that holds the credential it opens for.
async sub create_session_p (
    $self, $user, $input,
    $context = undef,
    $scope = undef
  )
{
    $scope //= $self->_functions;

    my ( $raw_token, $values ) = $self->_session_values( $user, $input );
    my $row = await $scope->row_p( 'session_create', { %{$values}, retry => 0 },
        $context );
    if ( _retry_session($row) ) {
        $raw_token = $self->_redrawn_session( $row, $raw_token, $values );
        $row       = await $scope->row_p( 'session_create',
            { %{$values}, retry => 1 }, $context );
    }
    return _created_session( $row, $raw_token );
}

# The application issues the bearer token and its digest; the row is drawn
# here and inserted by api.session_create.
sub _session_values ( $self, $user, $input ) {
    my $raw_token  = $self->session_tokens->issue_token;
    my $created_at = $self->clock->now_iso8601;
    my $row        = {
        created_at => $created_at,
        expires_at => $self->support->iso8601_from_epoch(
            $self->clock->now_epoch + $self->session_seconds
        ),
        ip_hash      => $self->support->hash_value( $input->{request_address} ),
        last_seen_at => $created_at,
        revoked_at   => undef,
        session_hash => $self->session_tokens->hash_token($raw_token),
        session_id   => $self->id_service->uuid,
        user_agent_hash => $self->support->hash_value( $input->{user_agent} ),
        user_id         => $self->support->column( $user, 'id' ),
    };
    return ( $raw_token, $row );
}

sub _retry_session ($row) {
    my $code = $row->{result_code};
    return $code eq 'retry_id' || $code eq 'retry_token' ? 1 : 0;
}

# A new session id, or a new token, for the one already taken; answers the
# raw token the session now has.
sub _redrawn_session ( $self, $row, $raw_token, $values ) {
    if ( $row->{result_code} eq 'retry_id' ) {
        $values->{session_id} = $self->id_service->uuid;
        return $raw_token;
    }
    $raw_token = $self->session_tokens->issue_token;
    $values->{session_hash} = $self->session_tokens->hash_token($raw_token);
    return $raw_token;
}

sub _created_session ( $row, $raw_token ) {
    my $code = delete $row->{result_code};
    return {
        session       => GPForum::Infrastructure::ResultRow->from($row),
        session_token => $raw_token,
        ( $code eq 'skipped' ? ( skipped => 1 ) : () ),
    };
}

# One session revoked by id through api.session_revoke, matched on its
# member's id too when one is given; a second revocation keeps the first's
# time. On $scope: the transaction a command log runs it in.
async sub revoke_session_p ( $self, $input, $context = undef, $scope = undef ) {
    return { ok => 0, error => 'not_found' }
      if !has_text( $input->{session_id} );
    $scope //= $self->_functions;

    return _revoked_session(
        await $scope->row_p(
            'session_revoke', $self->_revoke_values($input), $context
        )
    );
}

sub _revoke_values ( $self, $input ) {
    return {
        session_id => $input->{session_id},
        user_id    => has_text( $input->{user_id} ) ? $input->{user_id} : undef,
        revoked_at => $self->clock->now_iso8601,
    };
}

sub _revoked_session ($row) {
    return { ok => 0, error => 'not_found' } if !$row;
    my $code = delete $row->{result_code};
    return { ok => 0, error => 'not_found' } if $code eq 'not_found';
    return {
        ok      => 1,
        session => GPForum::Infrastructure::ResultRow->from($row),
        ( $code eq 'skipped' ? ( skipped => 1 ) : () ),
    };
}

# A session is valid for the member it belongs to, with the token whose hash
# it stores, unrevoked and unexpired: api.session_validate decides, revokes
# an expired one when it sees it, and touches a valid one at most once per
# touch interval.
async sub validate_session_p ( $self, $input, $context = undef ) {
    return { ok => 0, error => 'not_found' }
      if !has_text( $input->{session_id} ) || !has_text( $input->{user_id} );
    my $presented = $input->{session_token};
    my $row       = await $self->_functions->row_p(
        'session_validate',
        {
            session_id => $input->{session_id},
            user_id    => $input->{user_id},
            token_hash => has_text($presented)
            ? $self->session_tokens->hash_token($presented)
            : undef,
            now                    => $self->clock->now_iso8601,
            touch_interval_seconds => $self->session_touch_interval_seconds,
        },
        $context
    );
    return { ok => 0, error => 'not_found' } if !$row;
    my $code = delete $row->{result_code};
    return { ok => 0, error => $code } if $code ne 'ok' && $code ne 'expired';
    my $session = GPForum::Infrastructure::ResultRow->from($row);
    return { ok => 0, error => 'expired', session => $session }
      if $code eq 'expired';
    return { ok => 1, session => $session };
}

# ADR 0148: which of these sessions are live -- not revoked, not past their
# expiry -- as a set, in one call. An id that is not a uuid names no
# session.
async sub live_session_ids_p ( $self, $session_ids, $context = undef ) {
    my @ids =
      grep { GPForum::Infrastructure::Id->is_uuid($_) } @{ $session_ids || [] };
    return {} if !@ids;

    my $rows = await $self->_functions->rows_p( 'session_live',
        { session_ids => \@ids, now => $self->clock->now_iso8601 }, $context );
    return { map { ( lc $_->{session_id} => 1 ) } @{$rows} };
}

# $keep_session_id lets a password CHANGE evict every other device while
# leaving the browser the user is currently typing in signed in. A password
# RESET passes nothing, because there is no session to keep. One UPDATE: a
# session committed since the caller's last statement is revoked with the
# rest. On $scope, the transaction the caller holds, given after the query
# context.
async sub revoke_user_sessions_p (
    $self, $user_id, $revoked_at,
    $keep_session_id = undef,
    $context         = undef,
    $scope           = undef
  )
{
    $scope //= $self->_functions;

    my $row = await $scope->row_p(
        'session_revoke_user',
        {
            user_id         => $user_id,
            revoked_at      => $revoked_at,
            keep_session_id =>
              GPForum::Infrastructure::Id->is_uuid($keep_session_id)
            ? $keep_session_id
            : undef,
        },
        $context
    );
    return $row ? 0 + $row->{revoked_count} : 0;
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'sessions need the PostgreSQL database' );
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::SessionStore - Server session persistence.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Identity::SessionStore->new(
        schema => $schema,
    );

=head1 DESCRIPTION

Creates, validates, and revokes identity sessions, each through a versioned
function in schema C<api>.

Each operation is written once, as its promise method, against the
PostgreSQL function layer; the blocking methods are its twins (ADR 0177).
There is no fallback: without the function layer a call raises
L<GPForum::X::Unavailable>.

=head1 SUBROUTINES/METHODS

Every C<_p> method takes an optional query context after its arguments;
the writes take an optional call layer after it, the transaction to write
in.

=head2 create_session_p

Creates a hashed server-side session for a user. A unique C<session_hash>
collision remints the hash once and does not return another user's session.
A unique C<session_id> collision remints the id once and does not return
another user's session. A leftover unique C<session_id> with this user and
hash reuses the session. Answers C<session>, C<session_token> (the raw
token, for the cookie) and C<skipped> for a reused one.

=head2 revoke_session_p

Revokes one session by id. Given a C<user_id>, the session must belong to
that member or the answer is C<not_found>; the member is matched in the
query, not after the row is fetched. A second revoke of the same session,
or one a concurrent revocation beat, keeps the original timestamp and
answers C<skipped>. The session is revoked at the store's clock, or at its
own C<created_at> when that is later.

=head2 validate_session_p

Accepts a live session, or rejects revoked/expired rows. The session is
looked up by its id and its member's together, so a session presented under
another member's id is C<not_found>, and the presented token must match the
stored hash (C<invalid_token>). An expired session is revoked when seen.
C<last_seen_at> is written only when the stored value is at least
C<session_touch_interval_seconds> old (default 300), so an authenticated
request does not turn into a session UPDATE every time.

=head2 live_session_ids_p

Takes an array reference of session ids and answers a hash reference whose
keys are those still live: not revoked and not past their expiry (ADR 0148).
One call, through C<api.session_live>; it revokes nothing. Ids that are not
uuids are omitted.

=head2 revoke_user_sessions_p

Takes a user id, a revocation time and, optionally, a session id to keep.
Revokes every live session of the user in one UPDATE and answers how many it
revoked. With the session id it keeps that one session, which is what a
password change uses to evict other devices without signing the user out
where they are. Each session is revoked at the time given, or at its own
C<created_at> when that is later, so a session a concurrent login committed
after the caller read its clock is revoked rather than failing
C<sessions_revoked_after_created_check>.

=head2 create_session, revoke_session, validate_session, live_session_ids, revoke_user_sessions

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise.

=head1 DIAGNOSTICS

Missing or invalid sessions answer C<not_found>, C<invalid_token>,
C<revoked>, or C<expired>. Without the function layer a call raises
L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

Requires the PostgreSQL function layer. The
C<session_touch_interval_seconds> attribute is wired from
C<GPFORUM_SESSION_TOUCH_INTERVAL_SECONDS> through L<GPForum::Config>.

=head1 DEPENDENCIES

Uses L<GPForum::Infrastructure::SqlFunction>, L<GPForum::Infrastructure::Id>,
L<GPForum::Service::Identity::Support>, and L<GPForum::Service::SessionToken>.

Extends L<GPForum::Base>: built without C<schema> it throws
L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Tokens are hashed before persistence; the raw token is returned only to the
caller that places it in the signed cookie.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
