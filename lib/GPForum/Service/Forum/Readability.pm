# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::Readability;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Forum::ViewerResolver;
use GPForum::Service::Forum::Visibility;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my @PLACEMENT_COLUMNS => qw(
  category_id category_visibility space_id space_visibility
  thread_author thread_visibility post_author post_visibility
);
const my @LEVELS         => qw(space category thread post);
const my %VISIBLE_THREAD => ( visible => 1, locked => 1 );

# The sources a placement is read for, each by api.forum_<type>_placement.
const my %SOURCE_TYPES => ( post => 1, thread => 1 );

__PACKAGE__->requires('schema');
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

has viewer_resolver => sub ($self) {
    return GPForum::Service::Forum::ViewerResolver->new(
        schema => $self->schema );
};

# Each operation is written once, as its promise method (ADR 0177); the
# resolver it awaits blocks with it.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(readers_list readable_by));
GPForum::Infrastructure::SqlFunction->blocking_parts('viewer_resolver');

# ADR 0102: whether a reader may read a post or thread -- its space, its
# category, its thread and the post itself. $reader is a resolved Viewer (a
# request's) or a user id, resolved only when the source is not public. A
# source that is missing, removed or hidden, or of a kind this does not
# know, is readable by nobody.
async sub readers_list_p ( $self, $source_type, $source_id, @readers ) {
    my $type = $source_type // q{};
    return []
      if !exists $SOURCE_TYPES{$type}
      || !GPForum::Infrastructure::Id->is_uuid($source_id);
    my $placement = await $self->_functions->row_p( "forum_${type}_placement",
        { source_id => $source_id } );
    return [] if !$placement || !_live($placement);
    my $resource = {
        map  { $_ => $placement->{$_} }
        grep { exists $placement->{$_} } @PLACEMENT_COLUMNS
    };
    return \@readers if _public($resource);
    my @allowed;

    for my $reader (@readers) {
        my $viewer =
          ref $reader
          ? $reader
          : await $self->viewer_resolver->resolve_p($reader);
        if ( GPForum::Service::Forum::Visibility->readable( $viewer, $resource )
          )
        {
            push @allowed, $reader;
        }
    }
    return \@allowed;
}

# Whether one reader may read the post or thread.
async sub readable_by_p ( $self, $reader, $source_type, $source_id,
    $context = undef )
{
    my $readers =
      await $self->readers_list_p( $source_type, $source_id, $reader );

    return @{$readers} ? 1 : 0;
}

# The readers, of those given, who may read a post or thread: one query for
# where the source sits, and for a source that is not public, each reader's
# viewer. A realtime broadcast filters its subscribers this way.
sub readers_of ( $self, @arguments ) {
    return @{ $self->readers_list(@arguments) };
}

# Whether a reader may read a source whose placement is already in hand --
# the columns forum_post_placement answers, read with the source's row --
# so a listing judges each row without the statement readers_of makes.
# An absent reader is a visitor.
sub may_read ( $self, $reader, $placement ) {
    return 0 if !_live($placement);
    return 1 if _public($placement);

    my $viewer =
      defined $reader
      ? $self->_viewer($reader)
      : GPForum::Service::Forum::Viewer->anonymous;

    return GPForum::Service::Forum::Visibility->readable( $viewer, $placement )
      ? 1
      : 0;
}

# Rows that point at a post or thread by a type column and an id column --
# notifications, mentions, bookmarks, feed items -- as an SQL condition that
# keeps only those whose source the reader may read, live and not hidden.
# Lists filter with it before LIMIT, so keyset pages stay full (ADR 0102);
# a row of any other type is left out.
#
# Each subquery is correlated on the row's id: PostgreSQL runs it per row as
# a primary-key lookup. Uncorrelated, under the OR it became a hashed subplan
# that read every thread in the forum for a page of twenty-five.
sub sources_condition ( $self, $reader, $type_column, $id_column ) {
    my $viewer = $self->_viewer($reader);

    # The type test first in each arm: PostgreSQL evaluates an AND inside an
    # OR in the order written, so a thread row never runs the post lookup.
    return {
        -or => [
            {
                -and => [
                    { $type_column => 'post' },
                    {
                        $id_column => {
                            -in => $self->_readable_post( $viewer, $id_column )
                        }
                    },
                ]
            },
            {
                -and => [
                    { $type_column => 'thread' },
                    {
                        $id_column => {
                            -in =>
                              $self->_readable_thread( $viewer, $id_column )
                        }
                    },
                ]
            },
        ],
    };
}

sub _readable_thread ( $self, $viewer, $id_column ) {
    my $alias = 'readable_thread';

    return $self->schema->resultset('Thread')->search_rs(
        {
            "$alias.thread_id"        => { -ident => $id_column },
            "$alias.deleted_at"       => undef,
            "$alias.moderation_state" =>
              { -in => [ sort keys %VISIBLE_THREAD ] },
            'category.deleted_at' => undef,
            %{ GPForum::Service::Forum::Visibility->readable_condition(
                    $viewer,
                    {
                        category      => 'category.visibility',
                        category_id   => "$alias.category_id",
                        space         => 'space.visibility',
                        space_id      => 'category.space_id',
                        thread        => "$alias.visibility",
                        thread_author => "$alias.author_user_id",
                    }
                )
            },
        },
        { alias => $alias, join => { category => 'space' } }
    )->get_column("$alias.thread_id")->as_query;
}

sub _readable_post ( $self, $viewer, $id_column ) {
    my $alias = 'readable_post';

    return $self->schema->resultset('Post')->search_rs(
        {
            "$alias.post_id"          => { -ident => $id_column },
            "$alias.deleted_at"       => undef,
            "$alias.moderation_state" => 'visible',
            'thread.deleted_at'       => undef,
            'thread.moderation_state' =>
              { -in => [ sort keys %VISIBLE_THREAD ] },
            'category.deleted_at' => undef,
            %{ GPForum::Service::Forum::Visibility->readable_condition(
                    $viewer,
                    {
                        category      => 'category.visibility',
                        category_id   => 'thread.category_id',
                        post          => "$alias.visibility",
                        post_author   => "$alias.author_user_id",
                        space         => 'space.visibility',
                        space_id      => 'category.space_id',
                        thread        => 'thread.visibility',
                        thread_author => 'thread.author_user_id',
                    }
                )
            },
        },
        { alias => $alias, join => { thread => { category => 'space' } } }
    )->get_column("$alias.post_id")->as_query;
}

sub _public ($resource) {
    my @levels = map { $resource->{"${_}_visibility"} }
      grep { exists $resource->{"${_}_visibility"} } @LEVELS;

    return GPForum::Service::Forum::Visibility->effective(@levels) eq 'public'
      ? 1
      : 0;
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'readability needs the PostgreSQL function layer' );
}

sub _viewer ( $self, $reader ) {
    return $reader if ref $reader;

    return $self->viewer_resolver->resolve($reader);
}

sub _live ($place) {
    return 0 if defined $place->{category_deleted_at};
    return 0 if defined $place->{thread_deleted_at};

    # exists: reading a key the restricted hash lacks -- 'hidden' -- dies.
    return 0 if !exists $VISIBLE_THREAD{ $place->{thread_state} // q{} };
    return 1 if !exists $place->{post_state};
    return 0 if defined $place->{post_deleted_at};

    return ( $place->{post_state} // q{} ) eq 'visible' ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::Readability - Who may read a post or thread.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $readability =
      GPForum::Service::Forum::Readability->new( schema => $schema );
    my $ok = $readability->readable_by( $viewer, 'post', $post_id );
    my @subscribers =
      $readability->readers_of( 'thread', $thread_id, @user_ids );

=head1 DESCRIPTION

Effective visibility (ADR 0102) for one post or thread judged away from a
page: the space, the category, the thread and the post, by the rules of
L<GPForum::Service::Forum::Visibility>, and only while the source is live.
Notifications, mentions, attachment downloads and realtime thread channels
ask it.

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>). C<schema>, the L<DBIx::Class> schema, is
required: without it C<new> throws L<GPForum::X::Argument>. C<viewer_resolver>
defaults to a L<GPForum::Service::Forum::ViewerResolver> on the same schema.

=head2 readable_by_p

True when a reader -- a Viewer or a user id -- may read the post or thread.
A promise, with an optional query context last.

=head2 may_read

Takes a reader (a viewer, a user id, or undef for a visitor) and a source's
placement as C<api.forum_post_placement> answers it, with the liveness
columns: the visibility and author of the post and its thread, the category
and the space, and whether each is deleted or hidden. Returns 1 when the
reader may read the source, 0 otherwise, without a statement of its own
(a user id is resolved to a viewer; a viewer is taken as it is).

=head2 readers_of

The readers, of those given, who may read the post or thread, in order: the
list C<readers_list> answers.

=head2 sources_condition

An SQL condition, for DBIx::Class, on a row's source type and id columns:
true only for a post or thread the reader may read.

=head2 readers_list_p

Takes the source's type and id, then the readers. Reads where the source
sits with one call and resolves the viewers of a source that is not public;
answers the readers allowed, in their order.

=head2 readers_list, readable_by

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), the viewer resolver with it, answering the value instead of a
promise.

=head1 DIAGNOSTICS

Dies when the database does. Without the PostgreSQL function layer it
raises L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Service::Forum::ViewerResolver>,
L<GPForum::Service::Forum::Visibility>, L<GPForum::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Resolves one viewer per reader of a source that is not public.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
