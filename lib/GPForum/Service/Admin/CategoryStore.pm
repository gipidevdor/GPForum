# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Admin::CategoryStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::Row  qw(column_of);
use GPForum::Infrastructure::Text qw(trimmed);
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Admin::Event;
use GPForum::Service::Clock;
use GPForum::X::Conflict;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $DEFAULT_SPACE_SLUG       => 'general';
const my $DEFAULT_SPACE_TITLE      => 'General';
const my $SCHEMA_VERSION           => 1;
const my $CATEGORY_ID_CONSTRAINT   => 'categories_pkey';
const my $CATEGORY_SLUG_CONSTRAINT => 'categories_space_slug_key';
const my $SPACE_ID_CONSTRAINT      => 'spaces_pkey';
const my $SPACE_SLUG_CONSTRAINT    => 'spaces_slug_key';
const my $SLUG_TAKEN               => 'slug is taken';

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };
has recorder   => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));
has events => sub { return GPForum::Service::Admin::Event->new; };

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each write and read is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(create_category update_category list_categories));

# The two category writes run inside the caller's transaction ($scope, the
# call layer transaction_p hands its work) or in one of their own.
async sub create_category_p ( $self, $input, $context = undef, $scope = undef )
{
    my $work = sub ($functions) {
        return $self->_create_once_p( $functions, $input, $context );
    };
    return await(
          $scope
        ? $work->($scope)
        : $self->_functions->transaction_p( $work, $context )
    );
}

async sub update_category_p ( $self, $input, $context = undef, $scope = undef )
{
    my $work = sub ($functions) {
        return $self->_update_once_p( $functions, $input, $context );
    };
    return await(
          $scope
        ? $work->($scope)
        : $self->_functions->transaction_p( $work, $context )
    );
}

# A live category already holding the slug in the space is this create,
# committed by an earlier attempt, and is reused. A concurrent create, or a
# minted id already stored, is answered by the live category then found; a
# minted id with none is minted once more.
#
# The slug key holds every row, soft-deleted ones too, while the store looks
# only for a live category. A slug conflict with no live row behind it is a
# soft-deleted category's slug: the slug is taken, as a validation error, not
# a database failure. The INSERT ran in a savepoint, so nothing was written.
async sub _create_once_p ( $self, $functions, $input, $context ) {
    my $space = await $self->_ensure_space_p( $functions, $input, $context );
    return undef if !$space;

    my $category = {
        %{$input},
        slug     => _slug($input),
        space_id => $space->{space_id},
    };
    my $find = sub {
        return $functions->row_p( _live_category_call($category), $context );
    };
    my $existing = await $find->();
    return await $self->_finish_leftover_category_p( $functions, $existing,
        $category, $context )
      if $existing;

    my $create = async sub ($savepoint) {
        my $row = $self->_new_category($category);
        await $savepoint->row_p( 'admin_insert_category', { values => $row },
            $context );
        await $self->_record_write_p( $savepoint,
            _created_write( $category, $row ), $context );
        return $row;
    };
    for my $retry ( 0, 1 ) {
        my ( $created, $error ) =
          await GPForum::Infrastructure::UniqueConflict->attempt_p( $functions,
            $create );
        return $created if $created;

        my $on =
          $retry
          ? q{}
          : _conflict_on( $error, $CATEGORY_ID_CONSTRAINT,
            $CATEGORY_SLUG_CONSTRAINT );
        if ( !$on ) {
            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        }
        $existing = await $find->();
        return await $self->_finish_leftover_category_p( $functions, $existing,
            $category, $context )
          if $existing;
        return _slug_taken() if $on ne 'id';
    }
    return;
}

# Which key a unique conflict is on: the minted id's (id), the other key
# (key), or neither (an empty string).
sub _conflict_on ( $error, $id_key, $other_key ) {
    my $conflict = GPForum::X::Conflict->caught($error);
    return q{}  if !$conflict;
    return 'id' if $conflict->on($id_key);
    return $conflict->on($other_key) ? 'key' : q{};
}

# A field left out keeps its value; an update that changes nothing is
# skipped. A slug moved onto another category's, live or soft-deleted, meets
# the space and slug key: the slug is taken. The UPDATE ran in a savepoint,
# so the transaction goes on. An id that is not a uuid names no category.
async sub _update_once_p ( $self, $functions, $input, $context ) {
    my $category_id = $input->{category_id};
    return undef if !GPForum::Infrastructure::Id->is_uuid($category_id);
    my $row = GPForum::Infrastructure::ResultRow->from(
        await $functions->row_p(
            'admin_category_by_id', { category_id => $category_id },
            $context
        )
    );
    return undef if !$row || defined column_of( $row, 'deleted_at' );

    my $updates = $self->_category_updates( $row, $input );
    if ( _unchanged_category( $row, $updates ) ) {
        return { %{ _row_hash( $row, _category_columns() ) }, skipped => 1, };
    }

    my ( undef, $error ) =
      await GPForum::Infrastructure::UniqueConflict->attempt_p(
        $functions,
        sub ($savepoint) {
            return $savepoint->row_p( 'admin_update_category',
                { category_id => $category_id, values => $updates }, $context );
        }
      );
    if ($error) {

        # The server's own sentence decides, not the constraint's name
        # anywhere in the text: an over-long slug fails the index (index row
        # size exceeds the maximum for categories_space_slug_key), which is
        # no slug taken.
        my $conflict = GPForum::X::Conflict->caught($error);
        return _slug_taken()
          if $conflict && $conflict->on($CATEGORY_SLUG_CONSTRAINT);
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }

    my $category = { %{ _row_hash( $row, _category_columns() ) }, %{$updates} };
    await $self->_record_write_p( $functions,
        _updated_write( $input, $category ), $context );

    return $category;
}

# The space the request names; without one, the first live space; without
# any, the default space. An id from the request that is not a uuid names
# no row: PostgreSQL would refuse it as a uuid parameter, which would answer
# 503 for what is a 404.
async sub _ensure_space_p ( $self, $functions, $input, $context ) {
    my $space_id = trimmed( $input->{space_id} );
    if ( length $space_id ) {
        return undef if !GPForum::Infrastructure::Id->is_uuid($space_id);
        return await $functions->row_p( 'admin_space_by_id',
            { space_id => $space_id }, $context );
    }

    return ( await $functions->row_p( 'admin_first_live_space', {}, $context ) )
      || await $self->_default_space_p( $functions, $context );
}

# The default space is created once. A concurrent creation, or a minted id
# already stored, is answered by the space then found by its slug; a minted
# id with none is minted once more.
async sub _default_space_p ( $self, $functions, $context ) {
    my $find = sub {
        return $functions->row_p( 'admin_space_by_slug',
            { slug => $DEFAULT_SPACE_SLUG }, $context );
    };
    my $existing = await $find->();
    return $existing if $existing;

    my $create = async sub ($savepoint) {
        my $space = $self->_new_default_space;
        await $savepoint->row_p( 'admin_insert_space', { values => $space },
            $context );
        return $space;
    };
    for my $retry ( 0, 1 ) {
        my ( $created, $error ) =
          await GPForum::Infrastructure::UniqueConflict->attempt_p( $functions,
            $create );
        return $created if $created;

        my $on =
          $retry
          ? q{}
          : _conflict_on( $error, $SPACE_ID_CONSTRAINT,
            $SPACE_SLUG_CONSTRAINT );
        if ( !$on ) {
            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        }
        $existing = await $find->();
        return $existing if $existing;
        if ( $on ne 'id' ) {
            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        }
    }
    return;
}

# An earlier attempt may have committed the category without its event.
async sub _finish_leftover_category_p ( $self, $functions, $existing, $input,
    $context )
{
    my $event_key = join q{:}, 'category.created', $existing->{category_id};
    my $recorded =
      await $functions->row_p( 'ops_event_recorded', { key => $event_key },
        $context );
    if ( !$recorded->{recorded} ) {
        await $self->_record_write_p( $functions,
            _created_write( $input, $existing ), $context );
    }

    return { %{$existing}, idempotent => 1 };
}

async sub _record_write_p ( $self, $functions, $input, $context ) {
    my $payload = $self->_write_payload($input);
    await $functions->row_p(
        'ops_record_event',
        $self->recorder->event_call(
            %{ $self->events->category_event($payload) }
        ),
        $context
    );
    await $functions->row_p(
        'ops_record_audit',
        $self->recorder->audit_call(
            %{ $self->events->category_audit($payload) }
        ),
        $context
    );
    return;
}

sub _live_category_call ($input) {
    return ( 'admin_live_category_by_slug',
        { slug => $input->{slug}, space_id => $input->{space_id} } );
}

# The visible categories, ordered by position and title.
async sub list_categories_p ( $self, $options, $context = undef ) {
    my $rows = await $self->_functions->rows_p( 'admin_list_categories',
        { row_limit => ( $options || {} )->{limit} }, $context );
    return [ map { GPForum::Infrastructure::ResultRow->from($_) } @{$rows} ];
}

sub _slug_taken {
    return { errors => { slug => $SLUG_TAKEN } };
}

sub _created_write ( $input, $category ) {
    return {
        action        => 'category.created',
        actor_user_id => $input->{actor_user_id},
        category      => $category,
    };
}

sub _new_category ( $self, $input ) {
    my $now = $self->clock->now_iso8601;
    return {
        category_id        => $self->id_service->uuid,
        created_at         => $now,
        deleted_at         => undef,
        description        => trimmed( $input->{description} ),
        permission_version => $SCHEMA_VERSION,
        position           => _position( $input->{position} ),
        slug               => $input->{slug},
        space_id           => $input->{space_id},
        title              => trimmed( $input->{title} ),
        updated_at         => $now,
        version            => $SCHEMA_VERSION,
        visibility         => _kept_text( $input->{visibility}, q{public} ),
    };
}

sub _updated_write ( $input, $category ) {
    return {
        action        => 'category.updated',
        actor_user_id => $input->{actor_user_id},
        category      => $category,
    };
}

# What an update writes: a field left out keeps its value.
sub _category_updates ( $self, $row, $input ) {
    my $position = trimmed( $input->{position} );
    $position =
      length $position ? _position($position) : column_of( $row, q{position} );
    return {
        description =>
          _kept_text( $input->{description}, column_of( $row, 'description' ) ),
        position   => $position,
        slug       => _kept_text( $input->{slug},  column_of( $row, 'slug' ) ),
        title      => _kept_text( $input->{title}, column_of( $row, 'title' ) ),
        updated_at => $self->clock->now_iso8601,
        version    => column_of( $row, 'version' ) + 1,
        visibility =>
          _kept_text( $input->{visibility}, column_of( $row, 'visibility' ) ),
    };
}

# Text compares with undef as empty, the position with undef as 0.
sub _unchanged_category ( $row, $updates ) {
    for my $name (qw(description slug title visibility)) {
        if ( ( column_of( $row, $name ) // q{} ) ne ( $updates->{$name} // q{} )
          )
        {
            return 0;
        }
    }

    return ( column_of( $row, 'position' ) // 0 ) ==
      ( $updates->{position} // 0 )
      ? 1
      : 0;
}

sub _new_default_space ($self) {
    my $now = $self->clock->now_iso8601;
    return {
        created_at         => $now,
        deleted_at         => undef,
        description        => q{},
        permission_version => $SCHEMA_VERSION,
        position           => 0,
        slug               => $DEFAULT_SPACE_SLUG,
        space_id           => $self->id_service->uuid,
        title              => $DEFAULT_SPACE_TITLE,
        updated_at         => $now,
        version            => $SCHEMA_VERSION,
        visibility         => 'public',
    };
}

sub _write_payload ( $self, $input ) {
    return {
        %{$input},
        correlation_id => $self->id_service->uuid,
        created_at     => $input->{category}{updated_at}
          || $input->{category}{created_at},
    };
}

# The slug given, or one made from the title.
sub _slug ($input) {
    my $provided = trimmed( $input->{slug} );
    if ( length $provided ) {
        return $provided;
    }

    my $slug = lc trimmed( $input->{title} );
    $slug =~ s/[^[:alnum:]]+/-/gmsx;
    $slug =~ s/\A [-]+//msx;
    $slug =~ s/[-]+ \z//msx;
    if ( length $slug ) {
        return $slug;
    }

    return $DEFAULT_SPACE_SLUG;
}

sub _position ($value) {
    my $trimmed = trimmed($value);
    if ( $trimmed =~ /\A -? [[:digit:]]+ \z/msx ) {
        return int $trimmed;
    }

    return 0;
}

sub _kept_text ( $value, $current ) {
    my $trimmed = trimmed($value);
    if ( length $trimmed ) {
        return $trimmed;
    }

    return $current;
}

sub _row_hash ( $row, @columns ) {
    if ( !$row ) {
        return undef;
    }

    my %hash = map { $_ => column_of( $row, $_ ) } @columns;

    return \%hash;
}

sub _category_columns {
    return
      qw(category_id space_id slug title description visibility position version created_at updated_at deleted_at);
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'categories need the PostgreSQL function layer' );
}

1;

__END__

=head1 NAME

GPForum::Service::Admin::CategoryStore - Admin category persistence.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $stored = $store->create_category(
        {
            actor_user_id => $user_id,
            title         => $title,
        }
    );

=head1 DESCRIPTION

Owns category create and update transactions for the admin catalog. A missing
space id on a fresh install creates a default public C<general> space so the
first administrator can add the first category without PerformanceSeed. Event,
audit, and outbox rows are written through C<api.ops_record_event> and
C<api.ops_record_audit>, prepared by L<GPForum::Infrastructure::EventRecorder>
from L<GPForum::Service::Admin::Event> hashes, in the write's transaction.

=head1 SUBROUTINES/METHODS

Each write and read is written once, as its promise method; the blocking
methods are those bodies settled on the blocking layer (ADR 0177).

=head2 create_category_p

Takes the actor, the title and the optional slug, description, visibility,
position and space id, an optional query context, and the call layer of
the caller's transaction, when the write joins it. Creates a category, or
resolves with the existing space/slug row idempotently. A unique race on the
default C<general> space slug reuses the existing space instead of inserting
a second row. Resolves with undef when a C<space_id> is given that is not a
uuid or names no space, and with C<< { errors => { slug => 'slug is taken' } } >>
when the slug belongs to a soft-deleted category of the space (the space
and slug key is not partial). C<create_category> is its blocking twin.

=head2 update_category_p

Takes the category id and the fields to change, an optional query context
and the caller's call layer, as L</create_category_p> does. Updates a
visible category. Resolves with undef when the category id is not a uuid
or names no visible category, and with
C<< { errors => { slug => 'slug is taken' } } >> when the new slug belongs
to another category of the space, live or soft-deleted. A second write of
the same title, slug, description, visibility, and position resolves with
C<skipped> and does not bump version, restamp C<updated_at>, or emit another
event, audit, or outbox row. C<update_category> is its blocking twin.

=head2 list_categories_p

Takes a hash reference (or undef) with an optional C<limit> and an optional
query context. Resolves with the visible categories ordered by position and
title. C<list_categories> is its blocking twin.

=head1 DIAGNOSTICS

Returns undef when a requested space or category cannot be resolved, an id
that is not a uuid included: it is checked before any statement is sent.
Returns an C<errors> hash when the slug is taken. Unexpected database errors
propagate to L<GPForum::Service::Admin::Workflow>. Throws
L<GPForum::X::Unavailable> without the function layer.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the schema, clock, and id service supplied by the composition root.

=head1 DEPENDENCIES

Uses L<Const::Fast>, L<GPForum::Base>,
L<GPForum::Infrastructure::EventRecorder>, L<GPForum::Infrastructure::Id>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict>,
L<GPForum::Service::Admin::Event>, and L<GPForum::Service::Clock>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Public category-list cache tags are invalidated by
L<GPForum::Worker::Handler::CacheInvalidation> after the outbox dispatches
C<category.created> and C<category.updated>.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
