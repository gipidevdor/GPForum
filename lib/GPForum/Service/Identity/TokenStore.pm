# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::TokenStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::ResultRow::IdentityUser;

use GPForum::Infrastructure::Storage;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Clock;
use GPForum::Service::Identity::Support;
use GPForum::Service::SessionToken;
use GPForum::X::Conflict;

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

# A minted token id already stored is this very token, committed by an
# earlier attempt, or another one, and then a new id is minted. A token
# hash already stored is reminted with its token. Any other conflict is
# idx_identity_tokens_open_user_type: the member already holds an open token
# of this type, which is rotated rather than duplicated.
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

sub create_token ( $self, $input ) {
    my $issued = $self->new_token_issue($input);
    my ( $created, $error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
        sub { return $self->_insert_issued($issued); } );
    if ($created) {
        return $created;
    }

    my $conflict = GPForum::X::Conflict->caught($error);
    if ( !$conflict ) {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }
    if ( $conflict->on($ID_CONSTRAINT) ) {
        my $stored =
          $self->functions
          ? GPForum::Infrastructure::ResultRow->from(
            $self->functions->row(
                'identity_token_by_id', { token_id => $issued->{token_id} }
            )
          )
          : $self->_tokens->find( { token_id => $issued->{token_id} } );
        if ( $self->_same_issued_token( $stored, $issued ) ) {
            return {
                row        => $stored,
                skipped    => 1,
                token_hash => $self->support->column( $stored, 'token_hash' ),
                token_id   => $self->support->column( $stored, 'token_id' ),
            };
        }
        my $token_id = $self->id_service->uuid;
        $issued = {
            %{$issued},
            row      => { %{ $issued->{row} }, token_id => $token_id },
            token_id => $token_id,
        };
    }
    elsif ( $conflict->on($HASH_CONSTRAINT) ) {
        my $raw_token  = $self->session_tokens->issue_token;
        my $token_hash = $self->session_tokens->hash_token($raw_token);
        $issued = {
            %{$issued},
            raw_token  => $raw_token,
            row        => { %{ $issued->{row} }, token_hash => $token_hash },
            token_hash => $token_hash,
        };
    }
    else {
        my $existing = $self->_unused_token( $issued->{row} );
        if ( !$existing ) {
            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        }
        return $self->_rotate_token( $existing, $issued );
    }

    my ( $retried, $retry_error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
        sub { return $self->_insert_issued($issued); } );
    if ($retried) {
        return $retried;
    }

    GPForum::Infrastructure::UniqueConflict->rethrow($retry_error);
}

# The member's open token of this type, if there is one, no longer does
# anything: it is rotated to a secret nobody was given, so the link mailed
# for it is dead, and to expire a second from now, the least the table
# allows after a token made this second. It stays the member's open token,
# which the next request rotates as it would any. True when there was one.
sub withdraw_open_token ( $self, $user_id, $token_type ) {
    my $open = $self->_unused_token(
        {
            token_type => $token_type,
            user_id    => $user_id,
        }
    );
    if ( !$open ) {
        return 0;
    }

    my $dead = $self->new_token_issue(
        {
            email_normalized =>
              $self->support->column( $open, 'email_normalized' ),
            metadata    => { withdrawn => 1 },
            token_type  => $token_type,
            ttl_seconds => 1,
            user_id     => $user_id,
        }
    );
    $self->_rotate_token( $open, $dead );

    return 1;
}

sub _insert_issued ( $self, $issued ) {
    my $row =
      $self->functions
      ? GPForum::Infrastructure::ResultRow->from(
        $self->functions->row(
            'identity_insert_token', { values => $issued->{row} }
        )
      )
      : $self->_tokens->create( $issued->{row} );

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

sub _unused_token ( $self, $input ) {
    if ( !$self->support->has_text( $input->{user_id} ) ) {
        return undef;
    }

    if ( $self->functions ) {
        return GPForum::Infrastructure::ResultRow->from(
            $self->functions->row(
                'identity_unused_token',
                {
                    user_id    => $input->{user_id},
                    token_type => $input->{token_type}
                }
            )
        );
    }

    return $self->_tokens->search_rs(
        {
            token_type => $input->{token_type},
            used_at    => undef,
            user_id    => $input->{user_id},
        },
        { rows => 1 },
    )->single;
}

sub _rotate_token ( $self, $row, $issued ) {
    if ( $self->functions ) {
        my $stored = $self->functions->row(
            'identity_rotate_token',
            {
                token_id => $self->support->column( $row, 'token_id' ),
                values   => $issued->{row}
            }
        );
        $row = GPForum::Infrastructure::ResultRow->from(
            { %{$stored}, expires_at => $issued->{expires_at} } );
    }
    else {
        $self->support->update_row(
            $row,
            {
                email_normalized => $issued->{row}{email_normalized},
                expires_at       => $issued->{expires_at},
                metadata         => $issued->{row}{metadata},
                token_hash       => $issued->{token_hash},
            }
        );
    }

    return {
        expires_at => $issued->{expires_at},
        raw_token  => $issued->{raw_token},
        rotated    => 1,
        row        => $row,
        token_hash => $issued->{token_hash},
        token_id   => $self->support->column( $row, 'token_id' ),
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

sub consume_token ( $self, $token_type, $raw_token ) {
    my $token_hash =
      $self->session_tokens->hash_token( $self->support->trimmed($raw_token) );
    if ( $self->functions ) {
        my $result = $self->functions->row(
            'identity_consume_token',
            {
                token_hash => $token_hash,
                token_type => $token_type,
                now        => $self->clock->now_iso8601,
                now_epoch  => $self->clock->now_epoch
            }
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
    $self->_lock_token_hash($token_hash);

    my $row = $self->_tokens->search_rs(
        {
            token_hash => $token_hash,
            token_type => $token_type,
        },
        { rows => 1 }
    )->single;
    if ( !$row ) {
        return { ok => 0, error => 'invalid_token' };
    }
    if ( defined $self->support->column( $row, 'used_at' ) ) {
        return { ok => 0, error => 'token_used' };
    }
    if ( $self->_token_expired($row) ) {
        return { ok => 0, error => 'token_expired' };
    }

    $self->support->update_row( $row,
        { used_at => $self->clock->now_iso8601 } );

    return {
        ok               => 1,
        email_normalized => $self->support->column( $row, 'email_normalized' ),
        row              => $row,
        token_id         => $self->support->column( $row, 'token_id' ),
        user_id          => $self->support->column( $row, 'user_id' ),
    };
}

sub _token_expired ( $self, $row ) {
    my $expires_at    = $self->support->column( $row, 'expires_at' );
    my $expires_epoch = $self->support->epoch_from_timestamp($expires_at);
    if ( !defined $expires_epoch ) {
        return 1;
    }

    return $expires_epoch <= $self->clock->now_epoch ? 1 : 0;
}

sub _lock_token_hash ( $self, $token_hash ) {
    my $dbh = GPForum::Infrastructure::Storage->dbh_of( $self->schema );
    if ( !$dbh ) {
        return undef;
    }

    my $locked = $dbh->selectrow_array(
        'SELECT token_id FROM identity_tokens WHERE token_hash = ? FOR UPDATE',
        undef, $token_hash
    );

    return $locked;
}

sub _tokens ($self) {
    return $self->schema->resultset('IdentityToken');
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

=head1 SUBROUTINES/METHODS

=head2 new_token_issue

Takes what L</create_token> takes and returns the token it would issue,
drawn and not stored: C<expires_at>, C<raw_token>, C<token_hash>,
C<token_id> and C<row>, the row C<api.identity_insert_token> takes. For a
command that stores the token in one call (C<api.identity_register_command>)
and mails the raw token from its outbox payload.

=head2 create_token

Creates a typed identity token and returns the raw token once. A second
unused token for the same user and type rotates the existing row instead of
inserting another. A unique C<token_hash> collision remints the hash once
and does not return another user's token. A unique C<token_id> collision
remints the id once and does not return another user's token. A leftover
unique C<token_id> with this user and hash reuses the token.

=head2 withdraw_open_token

Takes a user id and a token type. When the member holds an open token of
that type, rotates it to a secret nobody was given, expiring a second from
now, with C<withdrawn> as its metadata, and returns 1: the link mailed for
it no longer works. Returns 0 when there is none.

=head2 consume_token

Locks, validates, and marks a token as used.

=head1 DIAGNOSTICS

Invalid, used, or expired tokens return C<invalid_token>, C<token_used>, or
C<token_expired>.

=head1 CONFIGURATION AND ENVIRONMENT

Requires a DBIx::Class schema with an C<IdentityToken> resultset.

=head1 DEPENDENCIES

Uses L<GPForum::Infrastructure::Storage>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict>,
L<GPForum::Service::Identity::Support>, and
L<GPForum::Service::SessionToken>.

Extends L<GPForum::Base>: built without C<schema> it throws
L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Token rows are locked with C<FOR UPDATE> when a database handle is available.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
