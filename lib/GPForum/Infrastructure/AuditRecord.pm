# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::AuditRecord;

use Const::Fast;
use Digest::SHA qw(sha256_hex);
use English     qw(-no_match_vars);
use JSON::MaybeXS;
use Mojo::Base -base, -signatures;
use v5.40;
use POSIX       qw(strftime);
use Time::Local qw(timegm);

our $VERSION = '0.001';

const my $DEFAULT_SCHEMA_VERSION => 1;

# A time as ISO 8601 or PostgreSQL writes it: date, "T" or a space, clock,
# up to six fractional digits, and a zone ("Z", "+02", "+02:00", "+0200")
# or none, which reads as UTC (the recorder stamps "Z"; PostgreSQL's text is
# in the session's zone, which GPForum keeps at UTC). Assembled from its
# parts so each can be read on its own.
const my $DATE_PART => qr{(?<year>\d{4}) - (?<month>\d\d) - (?<day>\d\d)}msxa;
const my $CLOCK_PART =>
  qr{(?<hour>\d\d) : (?<minute>\d\d) : (?<second>\d\d)}msxa;
const my $FRACTION_PART => qr{(?: [.] (?<fraction>\d{1,6}) )?}msxa;
const my $ZONE_MINUTES  => qr{(?: :? (?<zone_minutes>\d\d) )?}msxa;
const my $OFFSET_ZONE =>
  qr{(?<sign>[+-]) (?<zone_hours>\d\d) $ZONE_MINUTES}msxa;
const my $ZONE_PART => qr{(?: (?<utc>Z) | $OFFSET_ZONE )?}msxa;
const my $TIME_TEXT =>
qr{\A \s* $DATE_PART [T ] $CLOCK_PART $FRACTION_PART \s* $ZONE_PART \s* \z}msxa;
const my $MICROSECOND_DIGITS => 6;
const my $SECONDS_PER_HOUR   => 3600;
const my $SECONDS_PER_MINUTE => 60;

# Read only to mint an audit_id or correlation_id the input leaves out;
# verifying a record, or building one whose ids are given, needs none.
has id_service => undef;    # optional: only an omitted id is minted
has json => sub { return JSON::MaybeXS->new( canonical => 1, utf8 => 1 ); };

sub build ( $self, $input, $chained_hash = undef ) {
    my $audit = {
        action   => $input->{action},
        actor_id => $input->{actor_id},
        audit_id => $self->_text_or(
            $input->{audit_id}, sub { return $self->id_service->uuid; }
        ),
        correlation_id => $self->_text_or(
            $input->{correlation_id},
            sub { return $self->id_service->uuid; }
        ),
        created_at => $self->_text_or(
            $input->{created_at}, sub { return $self->now_iso8601; }
        ),
        metadata       => $input->{metadata} // {},
        previous_hash  => $self->_previous_hash( $input, $chained_hash ),
        record_hash    => q{},
        schema_version => $self->_text_or(
            $input->{schema_version},
            sub { return $DEFAULT_SCHEMA_VERSION; }
        ),
        target_id   => $input->{target_id},
        target_type => $input->{target_type},
    };
    $audit->{record_hash} = $self->record_hash($audit);

    return $audit;
}

sub verify ( $self, $audit ) {
    my $payload = $self->payload_from($audit);
    my $hash    = $payload->{record_hash};
    if ( !$self->has_text($hash) ) {
        return 0;
    }

    return $hash eq $self->record_hash($payload) ? 1 : 0;
}

# The hashed form of a record, from the record as built or from the row as
# the table holds it (ADR 0156): created_at in UTC with microseconds,
# metadata as the structure its jsonb text decodes to, schema_version as a
# number. A row read back verifies as the record did.
sub payload_from ( $self, $audit ) {
    return {
        action         => $self->column( $audit, 'action' ),
        actor_id       => $self->column( $audit, 'actor_id' ),
        audit_id       => $self->column( $audit, 'audit_id' ),
        correlation_id => $self->column( $audit, 'correlation_id' ),
        created_at     =>
          $self->canonical_time( $self->column( $audit, 'created_at' ) ),
        metadata      => $self->_decoded( $self->column( $audit, 'metadata' ) ),
        previous_hash => $self->column( $audit, 'previous_hash' ),
        record_hash   => $self->column( $audit, 'record_hash' ),
        schema_version =>
          $self->_number( $self->column( $audit, 'schema_version' ) ),
        target_id   => $self->column( $audit, 'target_id' ),
        target_type => $self->column( $audit, 'target_type' ),
    };
}

# The chain a record belongs to (ADR 0156): its target as type:id, ":" for
# a record with no target. What api.core_audit_chain_key_v1 answers.
sub chain_key ( $, $target_type, $target_id ) {
    return ( $target_type // q{} ) . q{:} . ( $target_id // q{} );
}

# A time in the one form the hash covers, YYYY-MM-DDTHH:MM:SS.ffffffZ in
# UTC, whatever zone or precision it was written in; text that is not a
# time stays as it is.
sub canonical_time ( $, $value ) {
    return $value if !defined $value || $value !~ $TIME_TEXT;

    my %part = %LAST_PAREN_MATCH;
    my $epoch;
    try {
        $epoch = timegm(
            $part{second}, $part{minute},    $part{hour},
            $part{day},    $part{month} - 1, $part{year}
        );
    }
    catch ($error) {
        return $value;    # an impossible date is kept as written
    };
    if ( defined $part{sign} ) {
        my $offset = $part{zone_hours} * $SECONDS_PER_HOUR +
          ( $part{zone_minutes} // 0 ) * $SECONDS_PER_MINUTE;
        $epoch -= $part{sign} eq q{-} ? -$offset : $offset;
    }
    my $padded   = ( $part{fraction} // q{} ) . ( '0' x $MICROSECOND_DIGITS );
    my $fraction = substr $padded, 0, $MICROSECOND_DIGITS;

    return strftime( '%Y-%m-%dT%H:%M:%S', gmtime $epoch ) . ".${fraction}Z";
}

# The SHA-256 of the record's stored form (ADR 0156): the hashed fields as
# L</payload_from> reads them, created_at in UTC with microseconds, so the
# record as built and the row as read back hash alike; the record itself
# keeps the time as the caller wrote it.
sub record_hash ( $self, $audit ) {
    my %canonical = %{ $self->payload_from($audit) };
    delete $canonical{record_hash};

    return sha256_hex( $self->json->encode( \%canonical ) );
}

sub column ( $, $row, $name ) {
    if ( !$row ) {
        return undef;
    }
    if ( ref $row eq 'HASH' ) {
        return $row->{$name};
    }

    return $row->can('get_column') ? $row->get_column($name) : undef;
}

sub has_text ( $, $value ) {
    if ( !defined $value ) {
        return 0;
    }

    return length $value ? 1 : 0;
}

sub now_iso8601 {
    return strftime '%Y-%m-%dT%H:%M:%SZ', gmtime time;
}

# A caller can supply the link (ADR 0114 names this sub); otherwise the
# record chains to the hash it was given.
sub _previous_hash ( $self, $input, $chained_hash ) {
    return $self->_text_or( $input->{previous_hash},
        sub { return $chained_hash; } );
}

# jsonb read back is text; the hash covers the structure.
sub _decoded ( $self, $value ) {
    return $value if ref $value || !defined $value || !length $value;

    my $decoded;
    try {
        $decoded = $self->json->decode($value);
    }
    catch ($error) {
        return $value;    # text that is not JSON is kept as written
    };

    return $decoded;
}

# A column read back as digits is the number it holds.
sub _number ( $, $value ) {
    return $value if !defined $value || $value !~ /\A [[:digit:]]+ \z/amsx;

    return 0 + $value;
}

# The value when it has text, else what the fallback makes: an id service
# is asked only for an id the input leaves out.
sub _text_or ( $self, $value, $fallback ) {
    if ( $self->has_text($value) ) {
        return $value;
    }

    return $fallback->();
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::AuditRecord - Canonical audit hash records.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $audit = $records->build( \%input, $previous_hash );
    ok( $records->verify($audit) );

=head1 DESCRIPTION

Owns audit field defaults, canonical JSON hashing, and hash verification.
It does not persist rows or walk previous audit records.
L<GPForum::Infrastructure::EventRecorder> keeps EventLog, OutboxMessage, and
AuditLog writes plus chain lookup.

=head1 SUBROUTINES/METHODS

=head2 build

Returns a complete audit hash including C<record_hash>. Blank C<previous_hash>
inputs fall back to the chained hash supplied by the recorder.

=head2 verify

True when C<record_hash> matches the canonical payload.

=head2 chain_key

Takes a target type and a target id and returns the name of the chain a
record with that target belongs to (ADR 0156), C<type:id>; a record with no
target is in the chain named C<:>. What C<api.core_audit_chain_key_v1>
answers.

=head2 canonical_time

Takes a time as ISO 8601 or PostgreSQL writes it, in any zone, with or
without fractional seconds, and returns it as the hash covers it:
C<YYYY-MM-DDTHH:MM:SS.ffffffZ>, in UTC with microseconds. Text that is not
a time, and C<undef>, come back as they are.

=head2 payload_from

Reads audit fields from a hash or DBIx::Class row.

=head2 record_hash

Hashes the canonical audit payload without C<record_hash>.

=head2 column

Reads a named field from a hash or row.

=head2 has_text

True when the value is defined and non-empty.

=head2 now_iso8601

Returns the current UTC timestamp used when C<created_at> is omitted.

=head1 DIAGNOSTICS

Missing hashes fail verification. Persistence errors stay in the recorder.

=head1 CONFIGURATION AND ENVIRONMENT

Requires an id service only when C<audit_id> or C<correlation_id> are omitted.

=head1 DEPENDENCIES

Uses L<Digest::SHA>, L<JSON::MaybeXS>, and L<POSIX>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Hashing stays here. L<GPForum::Infrastructure::EventRecorder> serializes
previous-hash lookup with a transaction advisory lock when a database handle
is available.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
