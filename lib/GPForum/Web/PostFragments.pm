# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::PostFragments;

use Carp qw(croak);
use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::ByteStream;
use Mojo::Util qw(encode xml_escape);

our $VERSION = '0.001';

const my $MAX_ENTRIES          => 512;
const my $MAX_BYTES            => 64 * 1024;
const my $HALF                 => 2;
const my $REACTION_PICKER_OPEN => '<details class="post-reaction-picker">';
const my $REACTION_CHOICES_OPEN =>
  '<div class="post-reaction-picker__choices">';
const my $REACTION_FORM_ATTRIBUTES =>
'" hx-boost="true" hx-push-url="false" hx-sync:inherited="closest form:drop" hx-disable="findAll button[type=submit]:not(:disabled)">';
const my @CONTENT => qw(
  post_id thread_id position author_username author_display_name author_profile_label
  author_initial author_tint author_user_id author_avatar_id deleted_at
);

has max_entries => $MAX_ENTRIES;
has max_bytes   => $MAX_BYTES;
has stats       => sub { return { hits => 0, misses => 0, writes => 0 }; };

# The entries of two generations, the current one first. A hit in the older
# one moves to the current one; when the current one holds half the bound it
# becomes the older one, and the entries nobody asked for since go. A thread
# page asks for every one of its posts, so a hit is two hash lookups and a
# miss's bookkeeping a store, where an LRU's list and clock cost more than
# the fragments saved.
has generations => sub { return [ {}, {} ]; };

# Only the already-authorized presentation data enters the cache. Forms,
# capabilities, command ids, CSRF, the edit form's text and relative
# timestamps are never stored. The key is the content itself, every value
# the static template reads with its length before it: authors, reply
# targets and deletion select another static entry immediately, with no
# digest that two contents could share.
sub render ( $self, $controller, $post ) {
    my $context = $controller->stash->{'gp.post_fragment_context'} //=
      _context($controller);
    my $key   = _key( $context, $post );
    my $found = $self->_cached($key);
    return $found if $found;

    my $content   = { map { $_ => $post->{$_} } @CONTENT, 'reply_to' };
    my $fragments = {};
    my $rendered  = $controller->render_to_string(
        template      => 'forum/_post_fragments',
        layout        => undef,
        post          => $content,
        fragments     => $fragments,
        media_max_mib => $context->{media_max_mib},
    );
    croak 'Could not render post presentation fragments' if !defined $rendered;
    my $id = $post->{post_id};
    $fragments->{paths} = {
        map { $_ => $controller->ui_path( $_, post_id => $id ) }
          qw(post_edit post_delete post_restore post_like post_unlike
          post_report post_attachment_upload post_attachment_form post_verification)
    };
    return $self->_cache_fragments( $key, $fragments );
}

# Like display has no post-specific path or response credential. Keep it
# independent of author presentation and reaction counts.
sub like_html ( $self, $controller, $post ) {
    my $context = $controller->stash->{'gp.post_fragment_context'} //=
      _context($controller);
    my $count = $post->{like_count} || 0;
    my $liked = $post->{liked} ? 1 : 0;
    my $key   = 'like:' . $context->{key} . _encoded( $count, $liked );
    my $found = $self->_cached($key);
    return $found->{like} if $found;
    my $html = $controller->render_to_string(
        template   => 'forum/_like_fragment',
        layout     => undef,
        like_count => $count,
        liked      => $liked
    );
    croak 'Could not render like presentation fragment' if !defined $html;
    my $fragments = { like => Mojo::ByteStream->new($html), paths => {} };
    $self->_cache_fragments( $key, $fragments );
    return $fragments->{like};
}

# Standalone reaction partials need no thread header or author presentation.
sub reactions ( $self, $controller, $post ) {
    my $context = $controller->stash->{'gp.post_fragment_context'} //=
      _context($controller);
    my $key =
        'reactions:'
      . $context->{key}
      . _encoded(
        $post->{post_id},
        scalar @{ $post->{reactions} || [] },
        map { ( $_->{reaction}, $_->{count} // 0, $_->{reacted} ? 1 : 0 ) }
          @{ $post->{reactions} || [] }
      );
    my $found = $self->_cached($key);
    if ($found) {
        return $self->_reaction_paths( $controller, $post, $key, $found )
          if $post->{can_react} && !exists $found->{paths}{'post_react:heart'};
        return $found;
    }
    my $fragments = { paths => {} };
    return $self->_reaction_paths( $controller, $post, $key, $fragments )
      if $post->{can_react};
    $self->_render_reactions( $controller, $post, $fragments );
    return $self->_cache_fragments( $key, $fragments );
}

# Assemble cached display with fresh response-only form data. Keeping this
# small join outside the template loop avoids a nested render per post.
sub reaction_html ( $self, $controller, $post, $parts = undef ) {
    my @shown =
      grep { $post->{can_react} || $_->{count} } @{ $post->{reactions} || [] };
    return Mojo::ByteStream->new(q{}) if !@shown;
    if ( !$parts || !exists $parts->{reaction_group} ) {
        $parts = $self->reactions( $controller, $post );
    }
    my @html = ( $parts->{reaction_group} );
    if ( $post->{can_react} ) {
        push @html, $REACTION_PICKER_OPEN, $parts->{reaction_summary},
          $REACTION_CHOICES_OPEN,
          _reaction_form( $controller, $parts, \@shown ),
          '</div></details>';
    }
    else {
        push @html,
          map { $parts->{ 'reaction_static:' . $_->{reaction} } } @shown;
    }
    return Mojo::ByteStream->new( join q{}, @html, '</div>' );
}

sub _reaction_form ( $controller, $parts, $shown ) {
    my $first  = $shown->[0];
    my $route  = $first->{reacted} ? 'post_unreact' : 'post_react';
    my $action = $parts->{paths}{ $route . q{:} . $first->{reaction} };
    return join q{}, '<form method="post" action="', xml_escape($action),
      $REACTION_FORM_ATTRIBUTES, $controller->csrf_field, (
        map {
                $parts->{ 'reaction_open:' . $_->{reaction} }
              . ' name="command_id" value="'
              . xml_escape( $_->{command_id} // q{} ) . '">'
              . $parts->{ 'reaction_body:' . $_->{reaction} }
              . '</button>'
        } @{$shown}
      ),
      '</form>';
}

# Reaction display uses only static paths. Eligibility stays in the caller;
# both choices are safe to reuse across readers with the same display state.
sub _reaction_paths ( $self, $controller, $post, $key, $fragments ) {
    my $expanded = { %{$fragments}, paths => { %{ $fragments->{paths} } } };
    for my $reaction (qw(heart laugh celebrate think)) {
        for my $route (qw(post_react post_unreact)) {
            $expanded->{paths}{"$route:$reaction"} = $controller->ui_path(
                $route,
                post_id  => $post->{post_id},
                reaction => $reaction
            );
        }
    }
    $self->_render_reactions( $controller, $post, $expanded );
    return $self->_cache_fragments( $key, $expanded );
}

# Only display state enters these fragments. Form tags, command identities,
# CSRF masks and the decision to expose an action stay in the caller.
sub _render_reactions ( $self, $controller, $post, $fragments ) {
    my $reactions = $post->{reactions} || [];
    return if !@{$reactions};
    my $rendered = $controller->render_to_string(
        template  => 'forum/_reaction_fragments',
        layout    => undef,
        reactions => [
            map {
                +{
                    reaction => $_->{reaction},
                    count    => $_->{count} // 0,
                    reacted  => $_->{reacted} ? 1 : 0
                }
            } @{$reactions}
        ],
        fragments => $fragments,
        paths     => $fragments->{paths},
    );
    croak 'Could not render reaction presentation fragments'
      if !defined $rendered;
    return;
}

sub _cache_fragments ( $self, $key, $fragments ) {
    my $bytes = 0;
    for my $part ( values %{ $fragments->{paths} },
        map { $fragments->{$_} } grep { $_ ne 'paths' } keys %{$fragments} )
    {
        $bytes += length encode( 'UTF-8', $part );
    }
    if ( $bytes <= $self->max_bytes ) {
        $self->_keep( $key, $fragments );
    }

    return $fragments;
}

# Every cached presentation, by key, for inspection.
sub entries ($self) {
    my ( $current, $older ) = @{ $self->generations };

    return { %{$older}, %{$current} };
}

sub _cached ( $self, $key ) {
    my $generations = $self->generations;
    my $found       = $generations->[0]{$key};
    if ( !$found && ( $found = delete $generations->[1]{$key} ) ) {
        $self->_make_room;
        $generations->[0]{$key} = $found;
    }
    $self->stats->{ $found ? 'hits' : 'misses' } += 1;

    return $found;
}

sub _keep ( $self, $key, $fragments ) {
    return if $self->max_entries < $HALF;

    $self->_make_room;
    $self->generations->[0]{$key} = $fragments;
    $self->stats->{writes} += 1;

    return;
}

# A full current generation becomes the older one, and the older one goes.
sub _make_room ($self) {
    my $generations = $self->generations;
    if ( keys %{ $generations->[0] } >= int( $self->max_entries / $HALF ) ) {
        @{$generations} = ( {}, $generations->[0] );
    }

    return;
}

# What every post shares: locale, mounted base path and configured media limit.
sub _context ($controller) {
    my $url = $controller->req->url;

    my $media_max_mib = $controller->gp_config->media_max_mib;
    return {
        media_max_mib => $media_max_mib,
        key           => _encoded(
            $controller->ui_locale, $url->base->path->to_string,
            $media_max_mib
        ),
    };
}

# Each value as its length, a colon and itself (a dash for none): no two
# contents write the same key. The reply target, when there is one, goes in
# field by field, each with its name.
sub _key ( $context, $post ) {
    my $reply = $post->{reply_to};

    return $context->{key}
      . _encoded(
        @{$post}{@CONTENT},
        ( $reply ? 'reply' : undef ),
        map { ( $_, $reply->{$_} ) } sort keys %{ $reply || {} }
      );
}

sub _encoded (@values) {
    return join q{}, map { defined $_ ? length . q{:} . $_ : q{-} } @values;
}

1;

__END__

=head1 NAME

GPForum::Web::PostFragments - Bounded, content-addressed post presentation fragments.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $parts = $fragments->render($controller, $authorized_post_view_model);

=head1 DESCRIPTION

Keeps escaped, static template fragments in process memory, up to 512
entries of at most 64 KiB each, in two generations: an entry not asked for
while 256 others were stored is dropped. Nothing is sent to a shared cache.
The key is the content: every value the static template reads, the locale
and the application's mounted base path, each written with its length, so
deletions, author changes and reply changes select a new static entry
immediately. Like and reaction display have independent content keys; changing
one does not rebuild header, avatar, controls or the other display. Deploying a new process clears it.

The caller must first load the post through the normal authorization and
visibility checks. This cache cannot find a post by id or grant access.
Forms, permissions, session data, CSRF masks, command identifiers, the edit
form's text, attachment controls and relative timestamps remain outside the
cache. Post bodies still pass through the trusted-HTML policy on every
render; their source renderer already memoizes sanitized markup. Static
templates escape normally.

=head1 SUBROUTINES/METHODS

=head2 render

Takes a controller and its authorized post view model. Returns static author,
reply and control fragments plus post-specific action paths. Like and reaction
state do not enter this key. With C<max_entries> below 2 nothing is kept; entries
exceeding C<max_bytes> are returned without storage.

=head2 like_html

Returns the escaped like button display, independently cached by its count,
pressed state and rendering context. The caller decides eligibility, action
path, form credentials and command identity on every response.

=head2 reactions

Returns only the form-free reaction display and paths for a standalone reaction
partial, keyed by the current counts and pressed states, locale and mount path.
The caller checks eligibility and supplies fresh form credentials on every render.

=head2 reaction_html

Assembles the form-free display fragments with the current post's action
eligibility and fresh response credentials. Command values and the form action
are escaped. The completed markup is returned, never stored in the cache.
An optional third argument supplies the post fragments already loaded by the
post list, avoiding another lookup and nested template render for every post.

=head2 entries

Returns a hash reference of every cached presentation by its key.

=head1 DIAGNOSTICS

Rendering errors propagate to the caller; a render that produces nothing
croaks C<Could not render post presentation fragments> and is not kept.

=head1 CONFIGURATION AND ENVIRONMENT

C<max_entries> bounds the entries, C<max_bytes> each entry; C<stats> counts
hits, misses and writes.

=head1 DEPENDENCIES

L<Carp>, L<Const::Fast>, L<Mojo::Base>, L<Mojo::Util>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The static template may only read the fields declared here and its locale
and base path. Adding request-dependent output requires keeping it outside
the cache or including that dependency in the key.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause.

=cut
