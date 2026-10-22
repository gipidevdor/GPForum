# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::AvatarStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

# ADR 0144: the sides a picture is kept at, and what a staff removal is
# audited as.
const my @SIDES          => ( 64, 128, 256 );
const my %SIDE           => map { $_ => 1 } @SIDES;
const my $AUDIT_ACTION   => 'avatar.removed';
const my $AUDIT_TARGET   => 'avatar';
const my $SCHEMA         => 1;
const my $MAXIMUM_REASON => 500;

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
# picture: every call is unavailable.
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

sub sides ($self) { return [@SIDES]; }

sub is_side ( $self, $side ) {
    return defined $side && exists $SIDE{$side} ? 1 : 0;
}

sub variant_type ( $self, $side ) { return "avatar_$side"; }

sub maximum_reason ($self) { return $MAXIMUM_REASON; }

# The upload a member offers as their picture. Answers ok (with the upload
# it replaces as the waiting one, if any), replayed, not_found or invalid.
sub offer ( $self, $user_id, $attachment_id ) {
    return { status => 'invalid' }
      if !_is_uuid($user_id) || !_is_uuid($attachment_id);

    return $self->_functions->row(
        'community_avatar_offer',
        {
            user_id       => $user_id,
            attachment_id => $attachment_id,
            now           => $self->clock->now_iso8601,
        }
    ) // { status => 'invalid' };
}

# What became of the waiting upload: ready or unreadable. Answers ok (with
# the picture a ready one replaces), shown, stale or invalid.
sub settle ( $self, $user_id, $attachment_id, $outcome ) {
    return { status => 'invalid' }
      if !_is_uuid($user_id) || !_is_uuid($attachment_id);

    return $self->_functions->row(
        'community_avatar_settle',
        {
            user_id       => $user_id,
            attachment_id => $attachment_id,
            outcome       => $outcome,
            now           => $self->clock->now_iso8601,
        }
    ) // { status => 'invalid' };
}

# The member takes their picture away, and the one waiting with it.
# Answers ok with the uploads removed, or not_found.
sub remove_own ( $self, $user_id ) {
    return { status => 'not_found', attachment_ids => [] }
      if !_is_uuid($user_id);

    return _removed(
        $self->_functions->rows(
            'community_avatar_remove',
            { user_id => $user_id, attachment_id => undef, audit => undef }
        )
    );
}

# Staff take the picture a member shows away, audited with who did it, the
# member, and the reason given. Answers ok with the upload removed,
# not_found when it is not the picture shown, or invalid (field reason).
sub remove_by_staff ( $self, $input ) {
    return { status => 'not_found', attachment_ids => [] }
      if !_is_uuid( $input->{subject_user_id} )
      || !_is_uuid( $input->{attachment_id} );
    my $reason = $self->reason( $input->{reason} );
    return { status => 'invalid', field => 'reason', attachment_ids => [] }
      if !defined $reason;

    my $now = $self->clock->now_iso8601;
    return _removed(
        $self->_functions->rows(
            'community_avatar_remove',
            {
                user_id       => $input->{subject_user_id},
                attachment_id => $input->{attachment_id},
                audit         => $self->recorder->audit_call(
                    action     => $AUDIT_ACTION,
                    actor_id   => $input->{actor_user_id},
                    created_at => $now,
                    metadata   => {
                        subject_user_id => $input->{subject_user_id},
                        reason          => $reason,
                    },
                    schema_version => $SCHEMA,
                    target_id      => $input->{attachment_id},
                    target_type    => $AUDIT_TARGET,
                )->{audit},
            }
        )
    );
}

# The reason as stored: trimmed, at most 500 characters, possibly empty;
# undef when too long.
sub reason ( $self, $value ) {
    my $reason = ( $value // q{} ) =~ s/\A \s+ | \s+ \z//grmsx;

    return length $reason <= $MAXIMUM_REASON ? $reason : undef;
}

# The member's picture: the one shown and the one waiting, or {} for a
# member who never offered one.
sub status ( $self, $user_id ) {
    return {} if !_is_uuid($user_id);

    return $self->_functions->row( 'community_avatar_status',
        { user_id => $user_id } ) // {};
}

# The stored square of the picture a member shows, at a side: its
# attachment, object key, media type and size, or undef.
sub image ( $self, $user_id, $side ) {
    return undef if !_is_uuid($user_id) || !$self->is_side($side);

    return $self->_functions->row( 'community_avatar_image',
        { user_id => $user_id, variant_type => $self->variant_type($side) } );
}

# The stored objects of one profile upload, or of every one the member
# linked to their profile.
sub objects ( $self, $user_id, $attachment_id = undef ) {
    return [] if !_is_uuid($user_id);
    return [] if defined $attachment_id && !_is_uuid($attachment_id);

    return $self->_functions->rows( 'community_avatar_objects',
        { user_id => $user_id, attachment_id => $attachment_id } );
}

sub _removed ($rows) {
    my @removed = grep { ( $_->{status} // q{} ) eq 'ok' } @{ $rows // [] };
    return { status => 'not_found', attachment_ids => [] } if !@removed;

    return {
        status         => 'ok',
        attachment_ids => [ map { $_->{attachment_id} } @removed ],
    };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'profile pictures need the PostgreSQL function layer' );
}

sub _is_uuid ($value) {
    return GPForum::Infrastructure::Id->is_uuid_spelling( $value // q{} );
}

1;

__END__

=head1 NAME

GPForum::Service::Community::AvatarStore - The rows of members' profile pictures.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Community::AvatarStore->new(
        schema => $schema );
    my $offered = $store->offer( $user_id, $attachment_id );
    my $settled = $store->settle( $user_id, $attachment_id, 'ready' );
    my $status  = $store->status($user_id);
    my $square  = $store->image( $user_id, 128 );

=head1 DESCRIPTION

ADR 0144. Each call is one function of migration 131; refusals are results.
L<GPForum::Service::Community::Avatars> stores the files and holds the
workflow; this module is its persistence.

=head1 SUBROUTINES/METHODS

=head2 sides

The sides a picture is kept at: 64, 128 and 256 pixels.

=head2 is_side

True for one of L</sides>.

=head2 variant_type

The attachment variant a side is stored as: C<avatar_64>, C<avatar_128>,
C<avatar_256>.

=head2 maximum_reason

The longest reason staff may give, 500 characters.

=head2 offer

Takes a member id and an attachment id. Answers C<ok> with
C<replaced_attachment_id> (the upload no longer waiting, or undef),
C<replayed>, C<not_found> or C<invalid>.

=head2 settle

Takes a member id, an attachment id and C<ready> or C<unreadable>. Answers
C<ok> with C<replaced_attachment_id> (the picture a ready one replaces),
C<shown> when it already is the picture shown, C<stale> when it is neither
shown nor waiting, or C<invalid>.

=head2 remove_own

Takes a member id. Answers C<< { status => 'ok', attachment_ids => [...] } >>
for the uploads removed (the picture shown and the one waiting), or
C<not_found>.

=head2 remove_by_staff

Takes C<subject_user_id>, C<attachment_id> (the picture the staff member
saw), C<actor_user_id> and an optional C<reason>. Removes that picture
while it is the one shown and audits C<avatar.removed>. Answers as
L</remove_own>, or C<invalid> with C<< field => 'reason' >>.

=head2 reason

Takes a reason. Returns it trimmed, or undef when it is longer than
L</maximum_reason>.

=head2 status

Takes a member id. Returns C<attachment_id> and C<shown_at> for the picture
shown, C<pending_attachment_id>, C<pending_state> (C<checking>,
C<unreadable> or C<refused>) and C<pending_at> for the one waiting, or an
empty hash.

=head2 image

Takes a member id and a side. Returns C<attachment_id>, C<object_key>,
C<media_type> and C<byte_size> of the square, or undef.

=head2 objects

Takes a member id and optionally an attachment id. Returns
C<< { attachment_id, object_key } >> rows, the original's and its variants'.

=head1 DIAGNOSTICS

Throws L<GPForum::X::Unavailable> without the PostgreSQL function layer.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>,
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
