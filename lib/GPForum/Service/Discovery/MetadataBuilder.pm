# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Discovery::MetadataBuilder;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Service::Discovery::VisibilityPolicy;
use JSON::MaybeXS;
use Mojo::Util qw(html_unescape);

our $VERSION = '0.001';

const my $MAX_DESCRIPTION_LENGTH => 160;

__PACKAGE__->requires(qw(canonical_url));
has visibility_policy =>
  sub { return GPForum::Service::Discovery::VisibilityPolicy->new; };

sub thread_metadata ( $self, $thread, $body, $posts = [] ) {
    return { robots => 'noindex,nofollow' }
      if !$self->visibility_policy->is_public($thread);

    my $description =
      _excerpt( $body->{safe_text} || $body->{body_text} || q{} );

    my $canonical = $self->canonical_url->thread_url($thread);

    return {
        title       => $thread->{title},
        description => $description,
        canonical   => $canonical,
        open_graph  => {
            title       => $thread->{title},
            description => $description,
            type        => 'article',
            url         => $canonical,
        },
        robots          => 'index,follow',
        structured_data => $self->structured_data( $thread, $posts ),
    };
}

# Only the first page contains the original posting. Never label a reply
# as its thread's original, or describe content hidden from anonymous users.
sub structured_data ( $self, $thread, $posts ) {
    return undef if !@{$posts} || ( $posts->[0]{position} // 0 ) != 1;
    my @public = grep {
             ( $_->{visibility} // q{} ) eq 'public'
          && ( $_->{moderation_state} // q{} ) eq 'visible'
          && !$_->{deleted_at}
          && length( $_->{body} // q{} )
    } @{$posts};
    return undef if !@public || $public[0] != $posts->[0];
    my $url   = $self->canonical_url->thread_url($thread);
    my @nodes = map { _comment_node( $_, $url ) } @public;
    my $root  = shift @nodes;
    $root->{'@type'}    = 'DiscussionForumPosting';
    $root->{'@context'} = 'https://schema.org';
    $root->{headline}   = $thread->{title};
    $root->{url}        = $url;
    if (@nodes) { $root->{comment} = \@nodes; }
    my $json = JSON::MaybeXS->new( canonical => 1, utf8 => 0 )->encode($root);
    $json =~ s/</\\u003c/gmsx;
    $json =~ s/>/\\u003e/gmsx;
    $json =~ s/&/\\u0026/gmsx;
    return $json;
}

sub _comment_node ( $post, $url ) {
    my $date = "$post->{created_at}";
    $date =~ s/[ ]/T/msx;
    $date =~ s/([+-][[:digit:]]{2})\z/$1:00/amsx;
    return {
        '@type' => 'Comment',
        author  => {
            '@type' => 'Person',
            name    => $post->{author_display_name}
              || $post->{author_username}
              || 'Anonymous'
        },
        datePublished => $date,
        text          => _body_text( $post->{body} ),
        url           => "$url#post-$post->{post_id}"
    };
}

# The text of a body as GPForum::Service::Forum::BodyRenderer wrote it:
# every tag is the renderer's own, no attribute holds a raw angle bracket,
# and the text between the tags is escaped. Taking the tags out and
# unescaping what is left is what parsing it gave, and a page has twenty-five
# bodies: parsing each with Mojo::DOM was a tenth of its render.
sub _body_text ($html) {
    my $text = $html;
    $text =~ s/<[^>]*>//gmsx;

    return html_unescape($text);
}

sub _excerpt ($text) {
    $text =~ s/<[^>]+>/ /gmsx;
    $text =~ s/\s+/ /gmsx;
    $text =~ s/\A \s+ | \s+ \z//gmsx;

    return substr $text, 0, $MAX_DESCRIPTION_LENGTH;
}

1;

__END__

=head1 NAME

GPForum::Service::Discovery::MetadataBuilder - Title, description, canonical URL and robots directive for a thread page.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $builder = GPForum::Service::Discovery::MetadataBuilder->new(
        canonical_url => $canonical_url,
    );
    my $meta = $builder->thread_metadata( $thread, $first_post_body );
    # $meta->{robots} is 'noindex,nofollow' for a thread that is not public

=head1 DESCRIPTION

Builds the head metadata of a thread page. A thread that
L<GPForum::Service::Discovery::VisibilityPolicy> does not consider public
gets only C<noindex,nofollow>, so nothing about it leaks into search
engines or link previews. A public thread gets its title, a description cut
from the body, the canonical URL and the matching Open Graph fields.

=head1 SUBROUTINES/METHODS

=head2 new

Mojo::Base constructor. C<canonical_url> (a
L<GPForum::Service::Discovery::CanonicalUrl>) is required for public
threads; C<visibility_policy> defaults to a new
L<GPForum::Service::Discovery::VisibilityPolicy>.

=head2 thread_metadata

Takes the thread hash reference and the body hash reference. When the
thread is not public, returns C<< { robots => 'noindex,nofollow' } >>.
Otherwise returns C<title>, C<description>, C<canonical>, C<open_graph>
(C<title>, C<description>, C<< type => 'article' >>, C<url>) and
C<< robots => 'index,follow' >>. The description is the body's
C<safe_text>, else its C<body_text>, else empty, with tags replaced by
spaces, whitespace collapsed and trimmed, and cut to 160 characters.

=head2 structured_data

Takes a public thread and its visible posts; returns script-safe JSON-LD for the original posting and public comments present on its first page, or undef.

=head1 DIAGNOSTICS

None of its own. Dies if a public thread is passed and no
C<canonical_url> was given.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Discovery::VisibilityPolicy>,
L<GPForum::Service::Discovery::CanonicalUrl>.

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
