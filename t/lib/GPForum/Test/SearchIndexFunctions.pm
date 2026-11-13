# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::SearchIndexFunctions;

use Mojo::Base 'GPForum::Test::AnsweringFunctions', -signatures;
use v5.40;

our $VERSION = '0.001';

# The search index functions the indexer calls, over a forum kept in
# memory: threads and posts with their state, and the documents indexed
# from them. A source is live as the document builder has it -- a thread
# visible or locked, a post visible in a live thread -- and indexing it
# writes its document, skips it when it is already there, or removes it
# when the source died. Every call is recorded (asked).
has threads   => sub { return {}; };    # id => moderation state
has posts     => sub { return {}; };    # id => { thread_id, position, state }
has documents => sub { return {}; };    # "type:id" => 1

my %ANSWER = (
    search_index_entity      => \&_index,
    search_live_ids          => \&_live_ids,
    search_prune_candidates  => \&_prune_candidates,
    search_remove_post_batch => \&_remove_post_batch,
    search_thread_post_batch => \&_thread_post_batch,
);

sub rows ( $self, $name, $values ) {
    my $answer = $ANSWER{$name};
    return $self->SUPER::rows( $name, $values ) if !$answer;

    push @{ $self->calls }, [ $name, $values ];
    return $answer->( $self, $values );
}

sub thread_is_live ( $self, $thread_id ) {
    my $state = $self->threads->{$thread_id} // q{};
    return $state eq 'visible' || $state eq 'locked' ? 1 : 0;
}

sub post_is_live ( $self, $post_id ) {
    my $post = $self->posts->{$post_id} or return 0;
    return $post->{state} eq 'visible'
      && $self->thread_is_live( $post->{thread_id} ) ? 1 : 0;
}

# The documents held of one type, sorted.
sub documents_of ( $self, $type ) {
    return [
        sort map { /\A\Q$type\E:(.+)\z/msx ? $1 : () }
          keys %{ $self->documents }
    ];
}

sub _live ( $self, $type, $id ) {
    return $type eq 'thread'
      ? $self->thread_is_live($id)
      : $self->post_is_live($id);
}

sub _index ( $self, $values ) {
    my ( $type, $id ) = @{$values}{qw(entity_type entity_id)};
    my $key    = "$type:$id";
    my %entity = ( entity_type => $type, entity_id => $id );
    if ( !$self->_live( $type, $id ) ) {
        my $deleted = delete $self->documents->{$key} ? 1 : 0;
        return [
            {
                result =>
                  { %entity, ok => 1, removed => 1, deleted => $deleted }
            }
        ];
    }
    return [ { result => { %entity, skipped => 1 } } ]
      if $self->documents->{$key};

    $self->documents->{$key} = 1;
    return [ { result => \%entity } ];
}

sub _live_ids ( $self, $values ) {
    my ( $type, $after, $limit ) =
      @{$values}{qw(entity_type after_id row_limit)};
    my $sources = $type eq 'thread' ? $self->threads : $self->posts;
    my @ids     = grep { !defined $after || $_ gt $after }
      sort grep { $self->_live( $type, $_ ) } keys %{$sources};
    if ( @ids > $limit ) { splice @ids, $limit; }

    return [ map { { entity_id => $_ } } @ids ];
}

sub _prune_candidates ( $self, $values ) {
    my $type = $values->{entity_type};
    return [
        map  { { entity_id => $_ } }
        grep { !$self->_live( $type, $_ ) } @{ $self->documents_of($type) }
    ];
}

sub _thread_post_batch ( $self, $values ) {
    my ( $thread_id, $after, $limit ) =
      @{$values}{qw(thread_id after_position row_limit)};
    my $posts = $self->posts;
    my @batch =
      sort { $a->{position} <=> $b->{position} }
      map  { { post_id => $_, position => $posts->{$_}{position} } }
      grep {
        $posts->{$_}{thread_id} eq $thread_id
          && ( !defined $after || $posts->{$_}{position} > $after )
      } keys %{$posts};
    if ( @batch > $limit ) { splice @batch, $limit; }

    return \@batch;
}

# Nothing goes while the thread is live: its restore came first.
sub _remove_post_batch ( $self, $values ) {
    return [ { removed => undef } ]
      if $self->thread_is_live( $values->{thread_id} );

    my $removed =
      grep { delete $self->documents->{"post:$_"} } @{ $values->{post_ids} };
    return [ { removed => $removed } ];
}

1;

__END__

=head1 NAME

GPForum::Test::SearchIndexFunctions - The search index functions over a forum kept in memory.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $functions = GPForum::Test::SearchIndexFunctions->new(
        threads => { 'thread-1' => 'visible' },
        posts   => {
            'post-1' => {
                thread_id => 'thread-1', position => 1, state => 'visible' },
        },
    );
    my $indexer = GPForum::Service::Search::Indexer->new(
        functions => $functions, schema => {} );

=head1 DESCRIPTION

Answers C<search_index_entity>, C<search_live_ids>,
C<search_prune_candidates>, C<search_thread_post_batch> and
C<search_remove_post_batch> as the C<api> functions do, over C<threads>,
C<posts> and C<documents>; any other function as
L<GPForum::Test::AnsweringFunctions> does.

=head1 SUBROUTINES/METHODS

=head2 threads, posts, documents

The forum and the index the functions read and write.

=head2 rows

The answer of a search index function, or of the given answers.

=head2 thread_is_live, post_is_live

Whether the document builder indexes the source.

=head2 documents_of

The ids of the documents held of a type, sorted.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Test::AnsweringFunctions>.

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
