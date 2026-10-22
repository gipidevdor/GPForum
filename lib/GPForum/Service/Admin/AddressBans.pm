# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Admin::AddressBans;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use Socket qw(AF_INET AF_INET6 inet_ntop inet_pton);

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

# ADR 0146: what a ban is audited as, its scopes and lengths, and the
# widest range it may cover: an IPv4 /16 (65,536 addresses) and an IPv6
# /32 (one provider's allocation).
const my $TARGET         => 'address_ban';
const my $SCHEMA         => 1;
const my $MAXIMUM_REASON => 500;
const my $LIST_LIMIT     => 200;
const my @SCOPES         => qw(registration sign_in writes);
const my @DURATIONS      => qw(1h 1d 7d 30d 90d 365d);
const my %DURATION => (
    '1h'   => 3_600,
    '1d'   => 86_400,
    '7d'   => 604_800,
    '30d'  => 2_592_000,
    '90d'  => 7_776_000,
    '365d' => 31_536_000,
);
const my %ACTION => (
    place => 'address_ban.placed',
    edit  => 'address_ban.edited',
    lift  => 'address_ban.lifted',
);
const my $IPV4          => 4;
const my $IPV6          => 6;
const my %BITS          => ( $IPV4 => 32, $IPV6 => 128 );
const my %WIDEST        => ( $IPV4 => 16, $IPV6 => 32 );
const my $LONGEST_INPUT => 64;

# An IPv4-mapped IPv6 address, ::ffff:a.b.c.d, is the IPv4 address in its
# last 32 bits: a dual-stack listener reports IPv4 clients so.
const my $MAPPED_BITS   => 96;
const my $MAPPED_PREFIX => ( '0' x 80 ) . ( '1' x 16 );

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };
has recorder   => sub ($self) {
    return GPForum::Infrastructure::EventRecorder->new(
        id_service => $self->id_service,
        schema     => $self->schema,
    );
};
__PACKAGE__->requires(qw(schema));

# A schema without the function layer -- the in-memory doubles -- holds no
# bans: the lookup finds none and every write is unavailable.
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

sub scopes ($self) { return [@SCOPES]; }

sub durations ($self) { return [@DURATIONS]; }

sub maximum_reason ($self) { return $MAXIMUM_REASON; }

# An address as the lookup reads it: dotted IPv4 or compressed IPv6, an
# IPv4-mapped IPv6 address made IPv4. Undef for anything else -- the
# connection key a request on the Unix socket without a proxy gets
# (Web::ClientAddress) included.
sub address ( $self, $value ) {
    my $parsed = _parsed( $value // q{} );
    return undef if !$parsed;

    return _written( $parsed->{family}, $parsed->{bits} );
}

# A range as staff write it -- an address, or an address and a prefix
# length -- made the network PostgreSQL stores: the host bits cleared, an
# IPv4-mapped range made IPv4. Answers { range, family, prefix }, or
# { error } with invalid or too_broad.
sub range ( $self, $value ) {
    my $text = ( $value // q{} ) =~ s/\A \s+ | \s+ \z//grmsx;
    my ( $address, $length ) = $text =~ m{\A ([^/]+) (?: / (\d{1,3}) )? \z}msx;
    my $parsed = defined $address ? _parsed($address) : undef;
    return { error => 'invalid' } if !$parsed;

    my $family = $parsed->{family};
    my $prefix = $length // $BITS{$family};
    if ( $parsed->{mapped} && defined $length ) {
        return { error => 'invalid' }   if $length > $BITS{$IPV6};
        return { error => 'too_broad' } if $length < $MAPPED_BITS;
        $prefix = $length - $MAPPED_BITS;
    }
    return { error => 'invalid' }   if $prefix > $BITS{$family};
    return { error => 'too_broad' } if $prefix < $WIDEST{$family};

    my $network = substr( $parsed->{bits}, 0, $prefix )
      . ( '0' x ( $BITS{$family} - $prefix ) );
    return {
        range  => _written( $family, $network ) . "/$prefix",
        family => $family,
        prefix => $prefix,
    };
}

# A range as the console shows it: a single address without its /32 or
# /128.
sub shown_range ( $self, $range ) {
    my $whole = $range =~ /:/msx ? $BITS{$IPV6} : $BITS{$IPV4};

    return $range =~ s{ / $whole \z}{}rmsx;
}

# The reason as stored: one line, its runs of white space made one space,
# the ends trimmed. Undef when nothing is left or it is too long.
sub reason ( $self, $value ) {
    my $reason = ( $value // q{} ) =~ s/\s+/ /grmsx;
    $reason =~ s/\A [ ] | [ ] \z//gmsx;

    return length $reason && length $reason <= $MAXIMUM_REASON
      ? $reason
      : undef;
}

# Places a ban by $input->{actor_user_id}, writing from
# $input->{actor_address}. The form's command id, when it is a uuid, is the
# ban's id, so the same submission again answers replayed. Answers ok,
# replayed, invalid or too_broad (with the field), covers_self, duplicate
# (with the live ban's id) or conflict, and the ban's id.
sub place ( $self, $input ) {
    my $range = $self->range( $input->{range} );
    return { status => $range->{error}, field => 'range' } if $range->{error};
    my $scope = _scope( $input->{scope} );
    return _invalid('scope') if !defined $scope;
    my $reason = $self->reason( $input->{reason} );
    return _invalid('reason') if !defined $reason;
    my $seconds = _seconds( $input->{duration} );
    return _invalid('duration') if !defined $seconds;

    my $ban_id =
      _is_uuid( $input->{command_id} )
      ? $input->{command_id}
      : $self->id_service->uuid;
    my $now        = $self->clock->now_iso8601;
    my $expires_at = $self->clock->epoch_plus_iso8601($seconds);
    return $self->_functions->row(
        'admin_address_ban_place',
        {
            ban_id        => $ban_id,
            range         => $range->{range},
            scope         => $scope,
            reason        => $reason,
            expires_at    => $expires_at,
            actor_user_id => $input->{actor_user_id},
            actor_address => $self->address( $input->{actor_address} ),
            now           => $now,
            audit         => $self->_audit(
                'place',
                $input->{actor_user_id},
                $ban_id,
                {
                    range         => $range->{range},
                    scope         => $scope,
                    expires_at    => $expires_at,
                    reason_length => length $reason,
                },
                $now
            ),
        }
    ) // { status => 'invalid' };
}

# Changes a live ban's scope and reason, and its expiry when a duration is
# given (counted from now; none keeps the expiry). Answers ok, unchanged,
# invalid (with the field), not_found, ended or covers_self.
sub edit ( $self, $input ) {
    return { status => 'not_found' } if !_is_uuid( $input->{ban_id} );
    my $scope = _scope( $input->{scope} );
    return _invalid('scope') if !defined $scope;
    my $reason = $self->reason( $input->{reason} );
    return _invalid('reason') if !defined $reason;
    my $duration = $input->{duration} // q{};
    my $seconds  = _seconds($duration);
    return _invalid('duration') if length $duration && !defined $seconds;

    my $now = $self->clock->now_iso8601;
    my $expires_at =
      defined $seconds ? $self->clock->epoch_plus_iso8601($seconds) : undef;
    return $self->_functions->row(
        'admin_address_ban_edit',
        {
            ban_id        => $input->{ban_id},
            scope         => $scope,
            reason        => $reason,
            expires_at    => $expires_at,
            actor_user_id => $input->{actor_user_id},
            actor_address => $self->address( $input->{actor_address} ),
            now           => $now,
            audit         => $self->_audit(
                'edit',
                $input->{actor_user_id},
                $input->{ban_id},
                {
                    scope         => $scope,
                    expires_at    => $expires_at,
                    reason_length => length $reason,
                },
                $now
            ),
        }
    ) // { status => 'invalid' };
}

# Lifts a live ban now. Answers ok, not_found or ended.
sub lift ( $self, $input ) {
    return { status => 'not_found' } if !_is_uuid( $input->{ban_id} );

    my $now = $self->clock->now_iso8601;
    return $self->_functions->row(
        'admin_address_ban_lift',
        {
            ban_id        => $input->{ban_id},
            actor_user_id => $input->{actor_user_id},
            now           => $now,
            audit         => $self->_audit(
                'lift',               $input->{actor_user_id},
                $input->{ban_id}, {}, $now
            ),
        }
    ) // { status => 'invalid' };
}

# The bans, live first, with who placed, edited and lifted each.
sub list ( $self, $limit = $LIST_LIMIT ) {
    return $self->_functions->rows( 'admin_address_bans',
        { now => $self->clock->now_iso8601, row_limit => $limit } );
}

# The live ban covering an address -- the strongest scope, then the longest
# -- as { ban_id, address_range, scope, expires_at }; undef when none does,
# when the value is no address, and on the in-memory doubles.
sub covering ( $self, $value ) {
    my $functions = $self->functions;
    my $address   = $self->address($value);
    return undef if !$functions || !defined $address;

    return $functions->row( 'admin_address_ban_covering',
        { address => $address, now => $self->clock->now_iso8601 } );
}

sub _audit ( $self, $kind, $actor_user_id, $ban_id, $metadata, $now ) {
    return $self->recorder->audit_call(
        action         => $ACTION{$kind},
        actor_id       => $actor_user_id,
        created_at     => $now,
        metadata       => $metadata,
        schema_version => $SCHEMA,
        target_id      => $ban_id,
        target_type    => $TARGET,
    )->{audit};
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'address bans need the PostgreSQL function layer' );
}

# An address's family and its bits as a string of 0s and 1s, with whether
# it was written IPv4-mapped; undef when it is no address.
sub _parsed ($text) {
    return undef if length $text > $LONGEST_INPUT;
    if ( $text =~ /\A [\d.]+ \z/msx ) {
        my $packed = inet_pton( AF_INET, $text );
        return $packed
          ? { family => $IPV4, bits => unpack 'B*', $packed }
          : undef;
    }
    return undef if $text !~ /\A [[:xdigit:]:.]+ \z/msx;

    my $packed = inet_pton( AF_INET6, $text );
    return undef if !$packed;
    my $bits = unpack 'B*', $packed;
    return { family => $IPV6, bits => $bits }
      if index( $bits, $MAPPED_PREFIX ) != 0;

    return {
        family => $IPV4,
        bits   => substr( $bits, $MAPPED_BITS ),
        mapped => 1,
    };
}

sub _written ( $family, $bits ) {
    return inet_ntop( $family == $IPV4 ? AF_INET : AF_INET6, pack 'B*', $bits );
}

sub _seconds ($duration) {
    my $name = $duration // q{};

    return exists $DURATION{$name} ? $DURATION{$name} : undef;
}

sub _scope ($value) {
    my $scope = $value // q{};
    return ( grep { $_ eq $scope } @SCOPES ) ? $scope : undef;
}

sub _invalid ($field) {
    return { status => 'invalid', field => $field };
}

sub _is_uuid ($value) {
    return GPForum::Infrastructure::Id->is_uuid_spelling( $value // q{} );
}

1;

__END__

=head1 NAME

GPForum::Service::Admin::AddressBans - Address and range bans.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $bans = GPForum::Service::Admin::AddressBans->new( schema => $schema );
    my $placed = $bans->place(
        {
            range         => '203.0.113.0/24',
            scope         => 'writes',
            duration      => '7d',
            reason        => 'Spam wave from one provider.',
            actor_user_id => $staff_id,
            actor_address => '198.51.100.7',
        }
    );
    my $ban = $bans->covering('203.0.113.9');

=head1 DESCRIPTION

The storage of ADR 0146 through the C<api.admin_address_ban*> functions.
Perl parses and bounds the range, the scope, the reason and the length,
reads the clock, builds the audit records (never with the reason's text)
and reads the results; each write changes the ban and records its audit in
one transaction. The lookup every write request makes is L</covering>.

=head1 SUBROUTINES/METHODS

=head2 address

An address as the lookup reads it, or undef.

=head2 range

A written range made the stored network, or why it cannot be.

=head2 shown_range

A stored range as the console shows it.

=head2 reason

The reason as it is stored, or undef.

=head2 place

Places a ban; the form's command id keys it.

=head2 edit

Changes a live ban's scope, reason and expiry.

=head2 lift

Lifts a live ban.

=head2 list

The bans, live first.

=head2 covering

The live ban covering an address, or undef.

=head2 scopes

C<registration>, C<sign_in> and C<writes>.

=head2 durations

The lengths a ban may be placed for: C<1h>, C<1d>, C<7d>, C<30d>, C<90d>
and C<365d>.

=head2 maximum_reason

The longest reason: 500 characters.

=head1 DIAGNOSTICS

Without the PostgreSQL function layer every write and the list raise
L<GPForum::X::Unavailable>; the lookup finds nothing.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Socket>, L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Infrastructure::EventRecorder>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
