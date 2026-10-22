# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::ThreadTags;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Unicode::Normalize qw(NFKD);

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::ResultRow::Thread;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Forum::Viewer;
use GPForum::X;

our $VERSION = '0.001';

# A thread carries up to five tags, each up to thirty characters (ADR
# 0135). The slug is the tag's identity: the name lower-cased, its marks
# dropped (Café and cafe are one), anything but letters and digits a dash.
const my $MAX_TAGS      => 5;
const my $MAX_LENGTH    => 30;
const my $DEFAULT_LIMIT => 50;
const my $INDEX_LIMIT   => 100;

# A slug is words of lower-case ASCII letters and digits, joined by dashes.
const my $SLUG_WORD => qr/[\p{PosixLower}\p{PosixDigit}]+/msx;

__PACKAGE__->requires(qw(schema));

has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

# The tags a text names, as the author typed them, comma-separated: each
# trimmed, its spaces folded, the first five kept, a name repeated (by its
# slug) once, one that is empty, too long or without a letter or digit
# left out. Each is { name, slug }.
sub normalise ( $, $text ) {
    my ( @tags, %seen );
    for my $part ( split /,/msx, $text // q{} ) {
        my $name = $part;
        $name =~ s/\s+/ /gmsx;
        $name =~ s/\A\s|\s\z//gmsx;
        next if !length $name || length $name > $MAX_LENGTH;
        my $slug = _slug($name);
        next if !length $slug || $seen{$slug}++;
        push @tags, { name => $name, slug => $slug };
        last if @tags == $MAX_TAGS;
    }

    return \@tags;
}

sub _slug ($name) {
    my $slug = lc NFKD($name);
    $slug =~ s/\p{Mark}//gmsx;
    $slug =~ s/[^\p{PosixLower}\p{PosixDigit}]+/-/gmsx;
    $slug =~ s/\A-|-\z//gmsx;

    return $slug;
}

# Replaces a thread's tags with those the text names; answers the tags the
# thread has now, in order. A thread id that is not a uuid sets nothing.
sub set_thread_tags ( $self, $thread_id, $text ) {
    return [] if !GPForum::Infrastructure::Id->is_uuid($thread_id);
    my $tags = $self->normalise($text);
    my $rows = $self->_functions->rows(
        'forum_set_thread_tags',
        {
            names     => [ map { $_->{name} } @{$tags} ],
            slugs     => [ map { $_->{slug} } @{$tags} ],
            thread_id => $thread_id,
        }
    );

    return [ map { _tag($_) } @{$rows} ];
}

# For the threads of a page, by thread id: the tags of each, in order. A
# thread without tags is absent.
sub tags_for_threads ( $self, $thread_ids ) {
    my $call = $self->tags_call($thread_ids) // return {};
    my $rows = $self->_functions->rows( @{$call} );
    my %tags;
    for my $row ( @{$rows} ) {
        push @{ $tags{ $row->{thread_id} } }, _tag($row);
    }

    return \%tags;
}

# The call tags_for_threads makes, or undef when it makes none: a page that
# reads the tags with its other reads in one statement
# (Service::Forum::ThreadPageReads) answers it.
sub tags_call ( $, $thread_ids ) {
    my @ids = grep { GPForum::Infrastructure::Id->is_uuid($_) } @{$thread_ids};
    return undef if !@ids;

    return [ 'forum_thread_tags', { thread_ids => \@ids } ];
}

# The threads under one tag the viewer may read, newest activity first, in
# every category or in the one given, as rows the thread view model reads.
sub list_tagged_threads ( $self, $request ) {
    my $viewer = GPForum::Service::Forum::Viewer->from( $request->{viewer} );
    my $category_id = $request->{category_id};
    if ( defined $category_id
        && !GPForum::Infrastructure::Id->is_uuid($category_id) )
    {
        $category_id = undef;
    }
    my $rows = $self->_functions->rows(
        'forum_list_tagged_threads',
        {
            category_id   => $category_id,
            category_ids  => $viewer->category_ids,
            global_read   => $viewer->global_read,
            member        => $viewer->member,
            row_limit     => $request->{limit} || $DEFAULT_LIMIT,
            scope_user_id => $viewer->user_id,
            space_ids     => $viewer->space_ids,
            tag_slug      => $request->{slug} // q{},
        }
    );

    return [ map { GPForum::Infrastructure::ResultRow::Thread->from($_) }
          @{$rows} ];
}

# Every tag with how many threads the viewer may read under it, the most
# used first. Each is { name, slug, thread_count }.
sub list_tags ( $self, $request = undef ) {
    my $viewer = GPForum::Service::Forum::Viewer->from( $request->{viewer} );
    my $rows   = $self->_functions->rows(
        'forum_list_tags',
        {
            category_ids  => $viewer->category_ids,
            global_read   => $viewer->global_read,
            member        => $viewer->member,
            row_limit     => $request->{limit} || $INDEX_LIMIT,
            scope_user_id => $viewer->user_id,
            space_ids     => $viewer->space_ids,
        }
    );

    return [ map { +{ %{ _tag($_) }, thread_count => $_->{thread_count} } }
          @{$rows} ];
}

# Whether a slug has the form a tag's has: a tag page asked for anything
# else is not a tag that could exist.
sub is_slug ( $, $slug ) {
    return 0 if !defined $slug || length $slug > $MAX_LENGTH;

    return $slug =~ /\A$SLUG_WORD(?:-$SLUG_WORD)*\z/msx ? 1 : 0;
}

sub _tag ($row) {
    return { name => $row->{name}, slug => $row->{slug} };
}

# Tags exist only as api.* functions (ADR 0126).
sub _functions ($self) {
    return $self->functions // GPForum::X::Argument->throw(
        message => 'thread tags need the SQL function layer' );
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::ThreadTags - The tags a thread carries, and the threads under a tag.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $tags = GPForum::Service::Forum::ThreadTags->new( schema => $schema );
    $tags->set_thread_tags( $thread_id, 'Perl, PostgreSQL' );
    $tags->tags_for_threads( \@thread_ids );
    $tags->list_tagged_threads( { slug => 'perl', viewer => $viewer } );
    $tags->list_tags( { viewer => $viewer } );

=head1 DESCRIPTION

ADR 0135: a thread carries up to five tags its author names, shared across
categories. The thread command is untouched; the tags are set after it,
through C<api.forum_set_thread_tags_v1>, and read per page through
C<api.forum_thread_tags_v1>. A tag page lists the threads a reader may read
under one tag (C<api.forum_list_tagged_threads_v1>, ADR 0102's visibility
for the thread, its category and its space); the tag index counts them
(C<api.forum_list_tags_v1>).

=head1 SUBROUTINES/METHODS

=head2 normalise

The tags a comma-separated text names: each C<{ name, slug }>, trimmed, up
to five, each up to thirty characters, one per slug.

=head2 set_thread_tags

Replaces a thread's tags with those a text names; answers the thread's tags
now, in order.

=head2 tags_for_threads

The tags of the given threads, by thread id, each list in order.

=head2 tags_call

Takes thread ids; answers the call L</tags_for_threads> makes, the
function's catalogue name and its values, or undef when no id is a uuid
and no call is made. The class answers it too.

=head2 list_tagged_threads

The threads under a tag (C<slug>) the C<viewer> may read, optionally in
one C<category_id>, up to C<limit> (50), as thread rows.

=head2 list_tags

Every tag with the count of threads the C<viewer> may read under it, the
most used first, up to C<limit> (100).

=head2 is_slug

True when a string has the form of a slug.

=head1 DIAGNOSTICS

Without the SQL function layer every call throws
L<GPForum::X::Argument>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>, L<Unicode::Normalize>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A name without a letter or digit of the Latin alphabet (after its marks
are dropped) has no slug and is left out.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
