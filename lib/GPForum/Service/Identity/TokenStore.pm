# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::TokenStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;

use GPForum::Infrastructure::Text qw(has_text trimmed);
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Clock;
use GPForum::Service::Identity::Support;
use GPForum::Service::SessionToken;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $HASH_CONSTRAINT => 'identity_tokens_hash_key';
const my $ID_CONSTRAINT   => 'identity_tokens_pkey';

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
__PACKAGE__->requires(qw(schema));
has session_tokens => sub { return GPForum::Service::SessionToken->new; };
has support        => sub { return GPForum::Service::Identity::Support->new; };
has functions      => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(create_token withdraw_open_token token_user_id consume_token));

# A minted token id already stored is this very token, committed by an
# earlier attempt, or another one, and then a new id is minted. A token
# hash already stored is reminted with its token. Any other conflict is
# idx_identity_tokens_open_user_type: the member already holds an open token
# of this type, which is rotated rather than duplicated. On $scope, the
# transaction the caller holds: each insert is tried in a savepoint of it.
async sub create_token_p ( $self, $input, $context = undef, $scope = undef ) {
    $scope //= $self->_functions;
    my $issued = $self->new_token_issue($input);
    my $insert = sub ($savepoint) {
        return $self->_insert_issued_p( $issued, $context, $savepoint );
    };
    my ( $created, $error ) =
      await GPForum::Infrastructure::UniqueConflict->attempt_p( $scope,
        $insert );
    return $created if $created;

    my $conflict = GPForum::Infrastructure::UniqueConflict->conflict_of($error);
    if ( $conflict->on($ID_CONSTRAINT) ) {
        my $stored = GPForum::Infrastructure::ResultRow->from(
            await $scope->row_p(
                'identity_token_by_id', { token_id => $issued->{token_id} },
                $context
            )
        );
        return $self->_reused_token($stored)
          if $self->_same_issued_token( $stored, $issued );
        $issued = $self->_reissued_id($issued);
    }
    elsif ( $conflict->on($HASH_CONSTRAINT) ) {
        $issued = $self->_reissued_hash($issued);
    }
    else {
        my $existing =
          await $self->_unused_token_p( $issued->{row}, $context, $scope );
        if ( !$existing ) {
            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        }
        return await $self->_rotate_token_p( $existing, $issued, $context,
            $scope );
    }

    my ( $retried, $retry_error ) =
      await GPForum::Infrastructure::UniqueConflict->attempt_p( $scope,
        $insert );
    return $retried if $retried;

    GPForum::Infrastructure::UniqueConflict->rethrow($retry_error);
}

# A leftover of this very token, committed by an earlier attempt.
sub _reused_token ( $self, $stored ) {
    return {
        row        => $stored,
        skipped    => 1,
        token_hash => $self->support->column( $stored, 'token_hash' ),
        token_id   => $self->support->column( $stored, 'token_id' ),
    };
}

# The issue under a new id, its row too.
sub _reissued_id ( $self, $issued ) {
    my $token_id = $self->id_service->uuid;
    return {
        %{$issued},
        row      => { %{ $issued->{row} }, token_id => $token_id },
        token_id => $token_id,
    };
}

# The issue with a new raw token and its hash.
sub _reissued_hash ( $self, $issued ) {
    my $raw_token  = $self->session_tokens->issue_token;
    my $token_hash = $self->session_tokens->hash_token($raw_token);
    return {
        %{$issued},
        raw_token  => $raw_token,
        row        => { %{ $issued->{row} }, token_hash => $token_hash },
        token_hash => $token_hash,
    };
}

# The member's open token of this type, if there is one, no longer does
# anything: it is rotated to a secret nobody was given, so the link mailed
# for it is dead, and to expire a second from now, the least the table
# allows after a token made this second. It stays the member's open token,
# which the next request rotates as it would any. True when there was one.
# On $scope, the transaction the caller holds.
async sub withdraw_open_token_p (
    $self, $user_id, $token_type,
    $context = undef,
    $scope = undef
  )
{
    $scope //= $self->_functions;
    my $open = await $self->_unused_token_p(
        {
            token_type => $token_type,
            user_id    => $user_id,
        },
        $context, $scope
    );
    return 0 if !$open;

    await $self->_rotate_token_p( $open,
        $self->_withdrawal( $open, $user_id, $token_type ),
        $context, $scope );

    return 1;
}

# The dead token an open one is rotated to when it is withdrawn.
sub _withdrawal ( $self, $open, $user_id, $token_type ) {
    return $self->new_token_issue(
        {
            email_normalized =>
              $self->support->column( $open, 'email_normalized' ),
            metadata    => { withdrawn => 1 },
            token_type  => $token_type,
            ttl_seconds => 1,
            user_id     => $user_id,
        }
    );
}

async sub _insert_issued_p ( $self, $issued, $context, $scope ) {
    my $row = GPForum::Infrastructure::ResultRow->from(
        await $scope->row_p(
            'identity_insert_token', { values => $issued->{row} }, $context
        )
    );
    return {
        expires_at => $issued->{expires_at},
        raw_token  => $issued->{raw_token},
        row        => $row,
        token_hash => $issued->{token_hash},
        token_id   => $issued->{token_id},
    };
}

# The same member and the same token hash: the row is this token.
sub _same_issued_token ( $self, $stored, $issued ) {
    if ( !$stored ) {
        return 0;
    }
    my %expected = (
        token_hash => $issued->{token_hash},
        user_id    => $issued->{row}{user_id},
    );
    for my $column ( sort keys %expected ) {
        my $value = $self->support->column( $stored, $column );
        if (   !defined $value
            || !defined $expected{$column}
            || $value ne $expected{$column} )
        {
            return 0;
        }
    }

    return 1;
}

async sub _unused_token_p ( $self, $input, $context, $scope ) {
    return undef if !has_text( $input->{user_id} );

    return GPForum::Infrastructure::ResultRow->from(
        await $scope->row_p(
            'identity_unused_token',
            {
                user_id    => $input->{user_id},
                token_type => $input->{token_type}
            },
            $context
        )
    );
}

async sub _rotate_token_p ( $self, $row, $issued, $context, $scope ) {
    my $stored = await $scope->row_p(
        'identity_rotate_token',
        {
            token_id => $self->support->column( $row, 'token_id' ),
            values   => $issued->{row}
        },
        $context
    );
    my $rotated = GPForum::Infrastructure::ResultRow->from(
        { %{$stored}, expires_at => $issued->{expires_at} } );

    return {
        expires_at => $issued->{expires_at},
        raw_token  => $issued->{raw_token},
        rotated    => 1,
        row        => $rotated,
        token_hash => $issued->{token_hash},
        token_id   => $self->support->column( $rotated, 'token_id' ),
    };
}

# A token as create_token issues it, drawn and not stored: the time, the
# raw token and its hash, the expiry, a new id, and the row. Public so a
# command that stores the token in one call (api.identity_register_command)
# sends the same row and mails the same token.
sub new_token_issue ( $self, $input ) {
    my $created_at = $self->clock->now_iso8601;
    my $raw_token  = $self->session_tokens->issue_token;
    my $expires_at = $self->support->iso8601_from_epoch(
        $self->clock->now_epoch + $input->{ttl_seconds} );
    my $token_id   = $self->id_service->uuid;
    my $token_hash = $self->session_tokens->hash_token($raw_token);

    return {
        expires_at => $expires_at,
        raw_token  => $raw_token,
        token_hash => $token_hash,
        token_id   => $token_id,
        row        => {
            created_at       => $created_at,
            email_normalized => $input->{email_normalized},
            expires_at       => $expires_at,
            metadata         => $input->{metadata} || {},
            token_hash       => $token_hash,
            token_id         => $token_id,
            token_type       => $input->{token_type},
            used_at          => undef,
            user_id          => $input->{user_id},
        },
    };
}

# The owner is read without a lock or a validity decision, so account
# operations can lock the credential before consume_token locks the token.
# On $scope, the transaction the caller holds.
async sub token_user_id_p (
    $self, $token_type, $raw_token,
    $context = undef,
    $scope = undef
  )
{
    $scope //= $self->_functions;
    my $row = await $scope->row_p(
        'identity_token_user',
        {
            token_hash =>
              $self->session_tokens->hash_token( trimmed($raw_token) ),
            token_type => $token_type
        },
        $context
    );

    return $row ? $row->{user_id} : undef;
}

# The token locked, checked and marked used in one api.identity_consume_token
# call. On $scope, the transaction the caller holds.
async sub consume_token_p (
    $self, $token_type, $raw_token,
    $context = undef,
    $scope = undef
  )
{
    $scope //= $self->_functions;
    my $result = await $scope->row_p(
        'identity_consume_token',
        {
            token_hash =>
              $self->session_tokens->hash_token( trimmed($raw_token) ),
            token_type => $token_type,
            now        => $self->clock->now_iso8601,
            now_epoch  => $self->clock->now_epoch
        },
        $context
    );
    return { ok => 0, error => $result->{result_code} }
      if $result->{result_code} ne 'ok';

    my $row = delete $result->{token_row};
    $row->{used_at} = $self->clock->now_iso8601;
    return {
        ok  => 1,
        row => GPForum::Infrastructure::ResultRow->from($row),
        map { $_ => $row->{$_} } qw(email_normalized token_id user_id)
    };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'identity tokens need the PostgreSQL database' );
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::TokenStore - Identity token persistence.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Identity::TokenStore->new(
        schema => $schema,
    );

=head1 DESCRIPTION

Issues and consumes hashed identity tokens for password reset, email
change, and registration verification.

Each operation is written once, as its promise method, against the
PostgreSQL function layer; the blocking methods are its twins (ADR 0177).
There is no fallback: without the function layer a call raises
L<GPForum::X::Unavailable>.

=head1 SUBROUTINES/METHODS

Every C<_p> method takes an optional query context after its arguments and
an optional call layer after it: the transaction the caller holds, or the
store's own layer.

=head2 new_token_issue

Takes what L</create_token_p> takes and returns the token it would issue,
drawn and not stored: C<expires_at>, C<raw_token>, C<token_hash>,
C<token_id> and C<row>, the row C<api.identity_insert_token> takes. For a
command that stores the token in one call (C<api.identity_register_command>)
and mails the raw token from its outbox payload.

=head2 create_token_p

Creates a typed identity token and answers the raw token once. A second
unused token for the same user and type rotates the existing row instead of
inserting another. A unique C<token_hash> collision remints the hash once
and does not return another user's token. A unique C<token_id> collision
remints the id once and does not return another user's token. A leftover
unique C<token_id> with this user and hash reuses the token. Each insert is
tried in a savepoint of the transaction.

=head2 withdraw_open_token_p

Takes a user id and a token type. When the member holds an open token of
that type, rotates it to a secret nobody was given, expiring a second from
now, with C<withdrawn> as its metadata, and answers 1: the link mailed for
it no longer works. Answers 0 when there is none.

=head2 token_user_id_p

Reads the owner of the token's hash and type without locking it or deciding
whether it is usable. Account operations use this to lock the credential
before calling L</consume_token_p>, which checks the token again under its
lock.

=head2 consume_token_p

Locks, validates, and marks a token as used, in one
C<api.identity_consume_token> call. Answers C<ok> with C<row>,
C<email_normalized>, C<token_id> and C<user_id>, or the refusal.

=head2 create_token, withdraw_open_token, token_user_id, consume_token

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise.

=head1 DIAGNOSTICS

Invalid, used, or expired tokens answer C<invalid_token>, C<token_used>, or
C<token_expired>. Without the function layer a call raises
L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

Requires the PostgreSQL function layer.

=head1 DEPENDENCIES

Uses L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Infrastructure::UniqueConflict>,
L<GPForum::Service::Identity::Support>, and
L<GPForum::Service::SessionToken>.

Extends L<GPForum::Base>: built without C<schema> it throws
L<GPForum::X::Argument>.

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
