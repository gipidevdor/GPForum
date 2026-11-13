# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::ReadState;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::X::Argument;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $INITIAL_POSITION => 0;

__PACKAGE__->requires('schema');
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

has clock => sub { return GPForum::Service::Clock->new; };

# Each read is written once, as its promise method (ADR 0177). The mark is
# api.forum_read_marker_command's (ReadWorkflow), which this store gives
# its refusal and its row.
GPForum::Infrastructure::SqlFunction->blocking_twins('state_for_thread');

# The reader's marker in a thread, position 0 and no time when there is
# none.
async sub state_for_thread_p ( $self, $user_id, $thread_id, $context = undef ) {
    my $row =
         _has_value($user_id)
      && _has_value($thread_id)
      ? GPForum::Infrastructure::ResultRow->from(
        await $self->_functions->row_p(
            @{ $self->state_call( $user_id, $thread_id ) }, $context
        )
      )
      : undef;
    if ( !$row ) {
        return {
            user_id            => $user_id,
            thread_id          => $thread_id,
            last_read_position => $INITIAL_POSITION,
            last_read_at       => undef,
        };
    }

    return { map { $_ => _column( $row, $_ ) }
          qw(user_id thread_id last_read_position last_read_at) };
}

# The call state_for_thread_p makes for a member: a page that reads the
# state with its other reads in one statement
# (Service::Forum::ThreadPageReads) answers it.
sub state_call ( $, $user_id, $thread_id ) {
    return [ 'forum_read_state',
        { user_id => $user_id, thread_id => $thread_id } ];
}

sub summary_for_page ( $self, $user_id, $thread_id, $posts ) {
    my $state = $self->state_for_thread( $user_id, $thread_id );
    if ( !_has_value($user_id) ) {
        return {
            %{$state},
            authenticated         => 0,
            first_unread_anchor   => undef,
            first_unread_position => undef,
            first_unread_post_id  => undef,
            last_visible_position => _last_visible_position($posts),
            unread_in_page        => 0,
        };
    }

    # Count and locate unread posts while finding the furthest visible one.
    # The first unread follows page order, including on an unordered input.
    my $unread = 0;
    my $first_unread_post_id;
    my $first_unread_position = $INITIAL_POSITION;
    my $last_visible_position = $INITIAL_POSITION;
    for my $post ( @{$posts} ) {
        my $position = _post_position($post);
        if ( $position > $last_visible_position ) {
            $last_visible_position = $position;
        }
        next if $position <= $state->{last_read_position};

        if ( !$unread ) {
            $first_unread_post_id  = _column( $post, 'post_id' );
            $first_unread_position = $position;
        }
        $unread += 1;
    }

    return {
        %{$state},
        authenticated       => 1,
        first_unread_anchor => defined $first_unread_post_id
        ? 'post-' . $first_unread_post_id
        : undef,
        first_unread_position => $first_unread_position,
        first_unread_post_id  => $first_unread_post_id,
        last_visible_position => $last_visible_position,
        unread_in_page        => $unread,
    };
}

# What the store refuses a mark request with -- the answer mark_thread_read
# gives and the command log records -- or undef when the request is sound.
# Public: the command that runs the mark in one call
# (api.forum_read_marker_command) records it without the call.
sub invalid_mark ( $, $input ) {
    my %errors =
      map { _has_value( $input->{$_} ) ? () : ( $_ => "$_ is required" ) }
      qw(user_id thread_id);
    my $position = $input->{last_read_position};
    if ( !defined $position || $position !~ /\A [[:digit:]]+ \z/amsx ) {
        $errors{last_read_position} =
          'last_read_position must be a non-negative integer';
    }
    return undef if !%errors;
    return {
        errors => \%errors,
        ok     => 0,
        status => 'invalid',
    };
}

# The row a mark sends to api.forum_read_marker_command: the request and
# the mark's time.
sub mark_row ( $self, $input ) {
    return { %{$input}, last_read_at => $self->clock->now_iso8601 };
}

sub _last_visible_position ($posts) {
    my $last_position = $INITIAL_POSITION;
    for my $post ( @{$posts} ) {
        my $position = _post_position($post);
        if ( $position > $last_position ) {
            $last_position = $position;
        }
    }

    return $last_position;
}

sub _post_position ($post) {
    return $INITIAL_POSITION if !$post;

    return _column( $post, 'position' ) || $INITIAL_POSITION;
}

sub _column ( $row, $name ) {
    return $row->{$name}           if ref $row eq 'HASH';
    return $row->get_column($name) if $row && $row->can('get_column');

    GPForum::X::Argument->throw(
        message => 'read state row does not expose columns' );
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'read state needs the PostgreSQL function layer' );
}

sub _has_value ($value) {
    return defined $value && length $value ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::ReadState - How far a member has read a thread, and the unread posts on a page.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $read_state =
      GPForum::Service::Forum::ReadState->new( schema => $schema );

    my $summary = $read_state->summary_for_page( $user_id, $thread_id, $posts );
    # first_unread_anchor => 'post-<post_id>', unread_in_page => 3, ...

    my $refusal = $read_state->invalid_mark($request);
    my $row     = $refusal ? undef : $read_state->mark_row($request);

=head1 DESCRIPTION

C<invalid_mark> and C<mark_row> are the halves of a mark the read-marker
command (L<GPForum::Service::Forum::ReadWorkflow>) sends in one call: the
refusal the store would answer, and the row the function takes.

A member's read marker is the highest post position they have seen in a
thread, kept in C<thread_read_state> with a copy in
C<user_read_marker_deltas>. It only moves forward; the function keeps it
so. This store reads it (C<api.forum_read_state>) and says, for a page,
which posts are past it. Each read is written once, as its promise method;
the blocking method is its twin (ADR 0177).

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>). C<schema>, the L<DBIx::Class> schema, is
required: without it C<new> throws L<GPForum::X::Argument>. C<clock>
defaults to L<GPForum::Service::Clock>.

=head2 state_for_thread_p

Takes a user id and a thread id, and an optional query context. Answers
C<< { user_id, thread_id, last_read_position, last_read_at } >> from the
stored marker, or with position 0 and C<last_read_at> undef when there is
none or either id is empty.

=head2 state_for_thread

The blocking twin: L</state_for_thread_p> run on the blocking call layer
(ADR 0177), answering the state instead of a promise.

=head2 state_call

Takes a user id and a thread id; answers the call L</state_for_thread_p>
makes, the function's catalogue name and its values. The
class answers it too.

=head2 summary_for_page

Takes a user id, a thread id and the page's posts (an array reference of
hashes or rows with C<post_id> and C<position>). Returns the read state
plus C<authenticated>, C<last_visible_position> (the highest position on the
page), C<first_unread_post_id>, C<first_unread_position> and
C<first_unread_anchor> (C<post-POST_ID>) of the first post past the marker,
and C<unread_in_page>, the number of posts past it. For an anonymous viewer
(an empty user id) C<authenticated> is 0, the first-unread fields are undef
and C<unread_in_page> is 0.

=head2 invalid_mark

Takes a mark request (C<user_id>, C<thread_id>, C<last_read_position>).
Returns undef when the request is sound, or the answer a mark is refused
with: C<< { errors, ok => 0, status => 'invalid' } >>, one
error per missing id and one for a position that is not a non-negative
integer. C<api.forum_read_marker_command>, which marks in one call with its
command log (L<GPForum::Service::Forum::ReadWorkflow>), records it without
the mark.

=head2 mark_row

Takes a mark request and returns the row the read-marker command marks
with: the request and C<last_read_at>, the clock's time.

=head1 DIAGNOSTICS

L</invalid_mark> answers the errors C<user_id is required>,
C<thread_id is required> and
C<last_read_position must be a non-negative integer>. Database errors
propagate; without the PostgreSQL function layer a read raises
L<GPForum::X::Unavailable>. Throws L<GPForum::X::Argument>
C<read state row does not expose columns> for a post or row that is neither
a hash nor has C<get_column>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Base>, L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Service::Clock>, L<GPForum::X::Argument>,
L<GPForum::X::Unavailable>.

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
