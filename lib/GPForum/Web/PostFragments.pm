# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::PostFragments;

use Carp qw(croak);
use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::Util qw(encode);

our $VERSION = '0.001';

const my $MAX_ENTRIES => 512;
const my $MAX_BYTES   => 64 * 1024;
const my $HALF        => 2;
const my @CONTENT => qw(
  post_id thread_id position author_username author_display_name author_profile_label
  author_initial author_tint deleted_at liked like_count
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
# targets, deletion and counters select another entry immediately, with no
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
        template  => 'forum/_post_fragments',
        layout    => undef,
        post      => $content,
        fragments => $fragments,
    );
    croak 'Could not render post presentation fragments' if !defined $rendered;
    my $id = $post->{post_id};
    $fragments->{paths} = {
        map { $_ => $controller->ui_path( $_, post_id => $id ) }
          qw(post_edit post_delete post_restore post_like post_unlike
          post_report post_attachment_upload)
    };
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

# What every post of a response shares: its locale and mounted base path.
sub _context ($controller) {
    my $url = $controller->req->url;

    return [ $controller->ui_locale, $url->base->path->to_string ];
}

# Each value as its length, a colon and itself (a dash for none): no two
# contents write the same key. The reply target, when there is one, goes in
# field by field, each with its name.
sub _key ( $context, $post ) {
    my $reply = $post->{reply_to};

    return join q{},
      map { defined $_ ? length . q{:} . $_ : q{-} } @{$context},
      @{$post}{@CONTENT}, ( $reply ? 'reply' : undef ),
      map { ( $_, $reply->{$_} ) } sort keys %{ $reply || {} };
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
deletions, author changes, reply changes and like counts select a new entry
immediately. Deploying a new process clears it.

The caller must first load the post through the normal authorization and
visibility checks. This cache cannot find a post by id or grant access.
Forms, permissions, session data, CSRF masks, command identifiers, the edit
form's text, attachment controls and relative timestamps remain outside the
cache. Post bodies still pass through the trusted-HTML policy on every
render; their source renderer already memoizes sanitized markup. Static
templates escape normally.

=head1 SUBROUTINES/METHODS

=head2 render

Takes a controller and its authorized post view model. Returns a hash of
rendered static fragments and named action paths. With C<max_entries> below
2 nothing is kept; entries exceeding C<max_bytes> are returned without
storage.

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

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause.

=cut
