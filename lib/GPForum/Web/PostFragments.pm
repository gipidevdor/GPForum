# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::PostFragments;

use Const::Fast;
use Digest::SHA qw(sha256_hex);
use JSON::MaybeXS;
use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::Util qw(encode);

use GPForum::Service::Operations::LocalCache;

our $VERSION = '0.001';

const my $MAX_ENTRIES => 512;
const my $TTL_SECONDS => 3600;
const my $MAX_BYTES   => 64 * 1024;
const my @CONTENT => qw(
  post_id thread_id position author_username author_display_name author_profile_label
  author_initial author_tint body_source deleted_at reply_to liked like_count
);

has cache => sub {
    return GPForum::Service::Operations::LocalCache->new(
        namespace   => 'post-fragments-v1',
        max_entries => $MAX_ENTRIES,
        ttl_seconds => $TTL_SECONDS,
    );
};
has max_bytes => $MAX_BYTES;
has encoder => sub { return JSON::MaybeXS->new( canonical => 1, utf8 => 1 ); };

# Only the already-authorized presentation data enters the cache. Forms,
# capabilities, command ids, CSRF and relative timestamps are never stored.
# Changed edit text, authors, reply targets and counters change the key immediately,
# independently of asynchronous invalidation or the cache's retention time.
sub render ( $self, $controller, $post ) {
    my $url     = $controller->req->url;
    my $context = $controller->stash->{'gp.post_fragment_context'} //=
      [ $controller->ui_locale, $url->base->path->to_string, ];
    my $key =
      'post-fragments:v1:'
      . sha256_hex(
        $self->encoder->encode( [ $context, @{$post}{@CONTENT} ] ) );
    if ( $self->cache ) {
        my $cached = $self->cache->get($key);
        return $cached if $cached;
    }

    my $content   = { map { $_ => $post->{$_} } @CONTENT };
    my $fragments = {};
    $controller->render_to_string(
        template  => 'forum/_post_fragments',
        layout    => undef,
        post      => $content,
        fragments => $fragments,
    );
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
    if ( $self->cache && $bytes <= $self->max_bytes ) {
        $self->cache->put( $key, $fragments );
    }
    return $fragments;
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

Keeps escaped, static template fragments in a process-local LRU for one hour,
up to 512 entries of at most 64 KiB each. Nothing is sent to a shared cache.
The key includes all values the static template reads, the locale and the
application's mounted base path. Edit text, deletions, author changes and
reply changes select a new entry immediately. Deploying a new process clears it.

The caller must first load the post through the normal authorization and
visibility checks. This cache cannot find a post by id or grant access.
Forms, permissions, session data, CSRF masks, command identifiers, attachment
controls and relative timestamps remain outside the cache. Post bodies still
pass through the trusted-HTML policy on every render; their source renderer
already memoizes sanitized markup. Static templates escape normally.

=head1 SUBROUTINES/METHODS

=head2 render

Takes a controller and its authorized post view model. Returns a hash of
rendered static fragments and named action paths. A disabled cache (C<undef>)
renders normally. Entries exceeding C<max_bytes> are returned without storage.

=head1 DIAGNOSTICS

Rendering and cache errors propagate to the caller.

=head1 CONFIGURATION AND ENVIRONMENT

C<cache> is a LocalCache by default; C<max_bytes> limits each entry.

=head1 DEPENDENCIES

L<Const::Fast>, L<Digest::SHA>, L<JSON::MaybeXS>, L<Mojo::Base>,
L<Mojo::Util>, L<GPForum::Service::Operations::LocalCache>.

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
