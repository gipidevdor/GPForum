# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::HomePageReader;

use Const::Fast;
use Mojo::Base -base, -signatures, -async_await;
use v5.40;
use Scalar::Util qw(blessed);

use GPForum::Infrastructure::Row;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Text qw(plain_excerpt);
use GPForum::Service::Forum::CategoryReader;
use GPForum::Service::Forum::ThreadReader;

our $VERSION = '0.001';

const my $DEFAULT_CATEGORY_LIMIT => 12;
const my $DEFAULT_THREAD_LIMIT   => 20;
const my $EXCERPT_LENGTH         => 200;
const my $MAX_CATEGORY_LIMIT     => 50;
const my $MAX_THREAD_LIMIT       => 50;

const my @CATEGORY_COLUMNS =>
  qw(category_id description position slug title visibility);
const my @THREAD_COLUMNS => qw(
  author_display_name author_username author_user_id category_id created_at
  deleted_at last_activity_at moderation_state pinned reply_count slug thread_id
  title visibility
);

# Each reader is built on the schema when it is not given, so the schema is
# needed only when one of them is missing.
has schema          => undef;          # optional: when both readers are given
has category_reader => sub ($self) {
    return GPForum::Service::Forum::CategoryReader->new(
        schema => $self->schema );
};
has thread_reader => sub ($self) {
    return GPForum::Service::Forum::ThreadReader->new(
        schema => $self->schema );
};

# The readers' call layer: blocking_copy makes the readers block only when
# the reader has one.
has functions => sub ($self) {
    my $reader = $self->category_reader;
    return blessed $reader && $reader->can('functions')
      ? $reader->functions
      : undef;
};

# The page is read once, as its promise method (ADR 0177); home_page is its
# blocking twin, the two readers blocking with it.
GPForum::Infrastructure::SqlFunction->blocking_twins('home_page');
GPForum::Infrastructure::SqlFunction->blocking_parts(
    qw(category_reader thread_reader));

# The categories and the latest threads, read at once.
async sub home_page_p ( $self, $request, $context = undef ) {
    my $category_limit =
      _bounded_limit( $request ? $request->{category_limit} : undef,
        $DEFAULT_CATEGORY_LIMIT, $MAX_CATEGORY_LIMIT );
    my $thread_limit =
      _bounded_limit( $request ? $request->{thread_limit} : undef,
        $DEFAULT_THREAD_LIMIT, $MAX_THREAD_LIMIT );
    my $viewer = $request ? $request->{viewer} : undef;

    # Both reads start before either is awaited, so they run at once on the
    # pooled connections. Mojo::Promise->all would settle a tick later, which
    # a blocking caller cannot wait for.
    my $categories = $self->category_reader->list_categories_p(
        { limit => $category_limit, viewer => $viewer }, $context );
    my $threads = $self->thread_reader->list_public_threads_p(
        {
            after  => $request ? $request->{after} : undef,
            limit  => $thread_limit,
            viewer => $viewer,
        },
        $context
    );

    # Observed now, so a failure of the categories does not leave it an
    # unhandled rejection; awaiting it below still raises its own failure.
    $threads->catch( sub { return; } );
    my $rows = await $categories;
    my $page = await $threads;

    return {
        categories     => [ map { _category($_) } @{$rows} ],
        latest_threads => {
            items       => [ map { _thread($_) } @{ $page->{items} } ],
            next_cursor => $page->{next_cursor},
        },
    };
}

sub _category ($row) {
    my $data = GPForum::Infrastructure::Row->columns( $row, @CATEGORY_COLUMNS );
    return {
        category_id      => $data->{category_id},
        description      => $data->{description},
        last_activity_at => GPForum::Infrastructure::Row->loaded_column(
            $row, 'last_activity_at'
        ),
        thread_count =>
          GPForum::Infrastructure::Row->loaded_column( $row, 'thread_count' ),
        position   => $data->{position},
        slug       => $data->{slug},
        title      => $data->{title},
        visibility => $data->{visibility},
    };
}

sub _thread ($row) {
    my $data = GPForum::Infrastructure::Row->columns( $row, @THREAD_COLUMNS );
    my $excerpt =
      GPForum::Infrastructure::Row->loaded_column( $row, 'excerpt' );

    return {
        author_display_name => $data->{author_display_name},
        author_username     => $data->{author_username},
        author_user_id      => $data->{author_user_id},
        category_id         => $data->{category_id},
        created_at          => $data->{created_at},
        deleted_at          => $data->{deleted_at},
        excerpt             => plain_excerpt( $excerpt, $EXCERPT_LENGTH ),
        last_activity_at    => $data->{last_activity_at},
        moderation_state    => $data->{moderation_state},
        pinned              => $data->{pinned},
        reply_count         => $data->{reply_count},
        slug                => $data->{slug},
        thread_id           => $data->{thread_id},
        title               => $data->{title},
        visibility          => $data->{visibility},
    };
}

sub _bounded_limit ( $requested, $default, $max ) {
    return $default
      if !defined $requested
      || $requested !~ /\A [[:digit:]]+ \z/amsx
      || $requested < 1;
    return $max if $requested > $max;
    return int $requested;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::HomePageReader - The categories and latest public threads the home page shows.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $reader = GPForum::Service::Forum::HomePageReader->new(
        category_reader => $category_reader,
        thread_reader   => $thread_reader,
    );
    my $home = $reader->home_page(
        {
            after          => $cursor,
            category_limit => 12,
            thread_limit   => 20,
            viewer         => $viewer,
        }
    );
    # { categories => [...], latest_threads => { items => [...], next_cursor => ... } }

=head1 DESCRIPTION

Puts the home page's data together from two readers: the categories the
viewer can read, from L<GPForum::Service::Forum::CategoryReader>, and a
keyset page of the latest public threads, from
L<GPForum::Service::Forum::ThreadReader/list_public_threads>. Each row is
turned into a plain hash of the columns the page uses, so the controller
and the template see the same shape whether the readers return resultset
rows or hashes.

When C<category_reader> or C<thread_reader> is not set, it is built on
C<schema> once.

The page is read once, as its promise method (ADR 0177): C<home_page> is
its blocking twin, the two readers blocking with it.

=head1 SUBROUTINES/METHODS

=head2 home_page_p

Takes an optional hash reference with C<category_limit> (default 12, at
most 50), C<thread_limit> (default 20, at most 50), C<after> (the latest
threads' cursor string) and C<viewer>. Limits must be positive ASCII integers;
invalid values use the home defaults before either reader is called. An
optional query context comes last. Reads both lists at once and resolves
with a hash reference with:

=over 4

=item C<categories>

An array reference of hashes with C<category_id>, C<description>,
C<position>, C<slug>, C<title> and C<visibility>.

=item C<latest_threads>

A hash reference with C<items>, an array reference of hashes with
C<author_user_id>, C<category_id>, C<created_at>, C<deleted_at>,
C<excerpt>, C<last_activity_at>, C<moderation_state>, C<pinned>,
C<reply_count>, C<slug>, C<thread_id>, C<title> and C<visibility>, and
C<next_cursor>, the cursor of the next page or undef. C<excerpt> is the
text of the opening post's excerpt the list gives, at most 200 characters
(L<GPForum::Infrastructure::Text/plain_excerpt>), and empty when the row has
none.

=back

The readers bound the limits again on their side.

=head1 DIAGNOSTICS

Nothing of its own; errors from the readers and the database propagate.
The home page controller catches them and renders the page as unavailable.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::Row>, L<GPForum::Infrastructure::Text>,
L<GPForum::Service::Forum::CategoryReader>,
L<GPForum::Service::Forum::ThreadReader>.

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
