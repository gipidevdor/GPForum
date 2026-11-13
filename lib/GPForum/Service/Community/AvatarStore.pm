# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::AvatarStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
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
has recorder   => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));

# A schema without the function layer -- the in-memory doubles -- holds no
# picture: every call is unavailable.
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(offer settle remove_own remove_by_staff status image objects));

sub sides ($self) { return [@SIDES]; }

sub is_side ( $self, $side ) {
    return defined $side && exists $SIDE{$side} ? 1 : 0;
}

sub variant_type ( $self, $side ) { return "avatar_$side"; }

sub maximum_reason ($self) { return $MAXIMUM_REASON; }

# The upload a member offers as their picture. Answers ok (with the upload
# it replaces as the waiting one, if any), replayed, not_found or invalid.
async sub offer_p ( $self, $user_id, $attachment_id, $context = undef ) {
    return { status => 'invalid' }
      if !_is_uuid($user_id) || !_is_uuid($attachment_id);

    return (
        await $self->_functions->row_p(
            'community_avatar_offer',
            {
                user_id       => $user_id,
                attachment_id => $attachment_id,
                now           => $self->clock->now_iso8601,
            },
            $context
        )
    ) // { status => 'invalid' };
}

# What became of the waiting upload: ready or unreadable. Answers ok (with
# the picture a ready one replaces), shown, stale or invalid; on the
# transaction $functions belongs to when one is given.
async sub settle_p (
    $self, $user_id, $attachment_id, $outcome,
    $context = undef,
    $functions = undef
  )
{
    return { status => 'invalid' }
      if !_is_uuid($user_id) || !_is_uuid($attachment_id);

    $functions //= $self->_functions;
    return (
        await $functions->row_p(
            'community_avatar_settle',
            {
                user_id       => $user_id,
                attachment_id => $attachment_id,
                outcome       => $outcome,
                now           => $self->clock->now_iso8601,
            },
            $context
        )
    ) // { status => 'invalid' };
}

# The member takes their picture away, and the one waiting with it.
# Answers ok with the uploads removed, or not_found.
async sub remove_own_p ( $self, $user_id, $context = undef ) {
    return { status => 'not_found', attachment_ids => [] }
      if !_is_uuid($user_id);

    return _removed(
        await $self->_functions->rows_p(
            'community_avatar_remove',
            { user_id => $user_id, attachment_id => undef, audit => undef },
            $context
        )
    );
}

# Staff take the picture a member shows away, audited with who did it, the
# member, and the reason given, in the one call that removes it. Answers ok
# with the upload removed, not_found when it is not the picture shown, or
# invalid (field reason).
async sub remove_by_staff_p ( $self, $input, $context = undef ) {
    my $refused = $self->_staff_refusal($input);
    return $refused if $refused;

    return _removed(
        await $self->_functions->rows_p( $self->_staff_values($input),
            $context ) );
}

sub _staff_refusal ( $self, $input ) {
    return { status => 'not_found', attachment_ids => [] }
      if !_is_uuid( $input->{subject_user_id} )
      || !_is_uuid( $input->{attachment_id} );
    return { status => 'invalid', field => 'reason', attachment_ids => [] }
      if !defined $self->reason( $input->{reason} );
    return undef;
}

sub _staff_values ( $self, $input ) {
    my $now = $self->clock->now_iso8601;
    return (
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
                    reason          => $self->reason( $input->{reason} ),
                },
                schema_version => $SCHEMA,
                target_id      => $input->{attachment_id},
                target_type    => $AUDIT_TARGET,
            )->{audit},
        }
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
async sub status_p ( $self, $user_id, $context = undef ) {
    return {} if !_is_uuid($user_id);

    return (
        await $self->_functions->row_p(
            'community_avatar_status', { user_id => $user_id }, $context
        )
    ) // {};
}

# The stored square of the picture a member shows, at a side: its
# attachment, object key, media type and size, or undef.
async sub image_p ( $self, $user_id, $side, $context = undef ) {
    return undef if !_is_uuid($user_id) || !$self->is_side($side);

    return await $self->_functions->row_p(
        'community_avatar_image',
        {
            user_id      => $user_id,
            variant_type => $self->variant_type($side)
        },
        $context
    );
}

# The stored objects of one profile upload, or of every one the member
# linked to their profile; on the transaction $functions belongs to when
# one is given.
async sub objects_p (
    $self, $user_id,
    $attachment_id = undef,
    $context       = undef,
    $functions     = undef
  )
{
    return [] if !_is_uuid($user_id);
    return [] if defined $attachment_id && !_is_uuid($attachment_id);

    $functions //= $self->_functions;
    return await $functions->rows_p( 'community_avatar_objects',
        { user_id => $user_id, attachment_id => $attachment_id }, $context );
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

ADR 0144. Each call is one function of migration 1015; refusals are results.
L<GPForum::Service::Community::Avatars> stores the files and holds the
workflow; this module is its persistence. Each operation is written once,
as its promise method (ADR 0177); the blocking methods are that body
settled on the blocking layer.

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

=head2 offer_p

Takes a member id and an attachment id, then an optional query context.
Answers C<ok> with C<replaced_attachment_id> (the upload no longer waiting,
or undef), C<replayed>, C<not_found> or C<invalid>.

C<offer> is its blocking twin, with the two ids.

=head2 settle_p

Takes a member id, an attachment id and C<ready> or C<unreadable>, then an
optional query context and an optional transaction call layer. Answers
C<ok> with C<replaced_attachment_id> (the picture a ready one replaces),
C<shown> when it already is the picture shown, C<stale> when it is neither
shown nor waiting, or C<invalid>.

C<settle> is its blocking twin, with the ids and the outcome.

=head2 remove_own_p

Takes a member id, then an optional query context. Answers
C<< { status => 'ok', attachment_ids => [...] } >> for the uploads removed
(the picture shown and the one waiting), or C<not_found>.

C<remove_own> is its blocking twin, with the member id.

=head2 remove_by_staff_p

Takes C<subject_user_id>, C<attachment_id> (the picture the staff member
saw), C<actor_user_id> and an optional C<reason>, then an optional query
context. Removes that picture while it is the one shown and audits
C<avatar.removed>, both in one function call. Answers as
L</remove_own_p>, or C<invalid> with C<< field => 'reason' >>.

C<remove_by_staff> is its blocking twin, with the input.

=head2 reason

Takes a reason. Returns it trimmed, or undef when it is longer than
L</maximum_reason>.

=head2 status_p

Takes a member id, then an optional query context. Answers
C<attachment_id> and C<shown_at> for the picture shown,
C<pending_attachment_id>, C<pending_state> (C<checking>, C<unreadable> or
C<refused>) and C<pending_at> for the one waiting, or an empty hash.

C<status> is its blocking twin, with the member id.

=head2 image_p

Takes a member id and a side, then an optional query context. Answers
C<attachment_id>, C<object_key>, C<media_type> and C<byte_size> of the
square, or undef.

C<image> is its blocking twin, with the member id and the side.

=head2 objects_p

Takes a member id and optionally an attachment id, then an optional query
context and an optional transaction call layer. Answers
C<< { attachment_id, object_key } >> rows, the original's and its
variants', read in that transaction when one is given.

C<objects> is its blocking twin, with the ids.

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

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
