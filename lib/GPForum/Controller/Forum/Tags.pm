# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Forum::Tags;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Forum::Base', -signatures;
use v5.40;

our $VERSION = '0.001';

const my $HTTP_OK => 200;

# Every tag with how many discussions the reader may read under it.
sub list ($self) {
    my $cache = $self->public_cache_options( 'tags', ['forum:tags'] );
    return if $self->served_from_public_cache($cache);

    my $tags =
      $self->gp_thread_tags->list_tags( { viewer => $self->gp_forum_viewer } );

    return $self->render_payload(
        {
            cache_options => $cache,
            controller    => $self,
            payload  => $self->gp_forum_view_model->tags_page( tags => $tags ),
            status   => $HTTP_OK,
            template => 'forum/tag_index',
        }
    );
}

# The discussions under one tag the reader may read, in every category or,
# with ?category=ID, in one. A tag nothing readable carries is not found,
# as is a category the reader cannot read.
sub show ($self) {
    my $slug = $self->param('slug');
    if ( !$self->gp_thread_tags->is_slug($slug) ) {
        return $self->_not_found('tag not found');
    }
    my $cache = $self->public_cache_options(
        'tag',
        [ 'forum:tags', "forum:tag:$slug" ],
        { path => $self->req->url->path_query }
    );
    return if $self->served_from_public_cache($cache);

    my $viewer   = $self->gp_forum_viewer;
    my $category = $self->_filter_category($viewer);
    if ( length( $self->param('category') // q{} ) && !$category ) {
        return $self->_not_found('category not found');
    }
    my $threads = $self->gp_thread_tags->list_tagged_threads(
        {
            category_id => $category
            ? $self->_column( $category, 'category_id' )
            : undef,
            limit  => $self->list_page_limit,
            slug   => $slug,
            viewer => $viewer,
        }
    );
    my $thread_tags = $self->gp_tags_for_threads($threads);
    my $tag         = _named( $slug, $thread_tags );
    if ( !$tag ) {
        return $self->_not_found('tag not found');
    }

    return $self->render_payload(
        {
            cache_options => $cache,
            controller    => $self,
            payload       => $self->gp_forum_view_model->tag_page(
                category    => $category,
                tag         => $tag,
                thread_tags => $thread_tags,
                threads     => $threads,
            ),
            status   => $HTTP_OK,
            template => 'forum/tag',
        }
    );
}

sub _filter_category ( $self, $viewer ) {
    my $category_id = $self->param('category');
    return undef if !length( $category_id // q{} );

    return $self->gp_category_reader->find_category( $category_id, $viewer );
}

# The tag as a thread carries it (its name), found among the listed
# threads' tags.
sub _named ( $slug, $thread_tags ) {
    for my $tags ( values %{$thread_tags} ) {
        for my $tag ( @{$tags} ) {
            return $tag if $tag->{slug} eq $slug;
        }
    }

    return undef;
}

1;

__END__

=head1 NAME

GPForum::Controller::Forum::Tags - The tag index and the discussions under a tag.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/tags')->to('Forum::Tags#list');
    $routes->get('/tags/:slug')->to('Forum::Tags#show');

=head1 DESCRIPTION

ADR 0135: C</tags> lists every tag with how many discussions the reader may
read under it; C</tags/:slug> lists those discussions, in every category or
in the one C<?category=ID> names. Both are public pages, cached for
anonymous readers under C<forum:tags>, which a thread event purges.

=head1 SUBROUTINES/METHODS

=head2 list

Renders the tag index.

=head2 show

Renders the discussions under one tag, or 404 when nothing readable carries
it, the slug is not one, or the category filter names a category the
reader cannot read.

=head1 DIAGNOSTICS

A failed read of the tags of the listed threads is logged and shows none.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Controller::Forum::Base>, L<GPForum::Service::Forum::ThreadTags>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The tag page has no keyset pagination: it shows the newest discussions up
to the page limit.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
