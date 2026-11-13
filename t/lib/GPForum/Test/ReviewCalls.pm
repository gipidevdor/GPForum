# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::ReviewCalls;

use Mojo::Base -base, -signatures;
use v5.40;

use Mojo::Promise;

use GPForum::Service::Forum::Viewer;

our $VERSION = '0.001';

# ADR 0134: one stand-in for each collaborator of the review queue -- the
# review store, the posting workflow, the viewer resolver, the notification
# dispatcher, the reply links, the thread tags and the automod store.
# Every call is recorded; each answers what `answers` holds under its name (a code
# reference is called with the arguments), or a plain ok.
has answers      => sub { return {}; };
has calls        => sub { return []; };
has transactions => 0;

sub hold ( $self, @arguments ) { return $self->_called( hold => @arguments ); }
sub take ( $self, @arguments ) { return $self->_called( take => @arguments ); }

sub decide ( $self, @arguments ) {
    return $self->_called( decide => @arguments );
}

sub rules_for ( $self, @arguments ) {
    return $self->_called( rules_for => @arguments );
}

sub publish_reviewed ( $self, @arguments ) {
    return $self->_called( publish_reviewed => @arguments );
}

# The viewer the author reads as: a member, unless `answers` says otherwise.
sub resolve ( $self, @arguments ) {
    $self->answers->{resolve} //= GPForum::Service::Forum::Viewer->new(
        user_id => $arguments[0],
        member  => 1
    );

    return $self->_called( resolve => @arguments );
}

sub create_notification ( $self, @arguments ) {
    return $self->_called( create_notification => @arguments );
}

sub link_reply ( $self, @arguments ) {
    return $self->_called( link_reply => @arguments );
}

sub set_thread_tags ( $self, @arguments ) {
    return $self->_called( set_thread_tags => @arguments );
}

sub maximum_reason ($self) { return 500; }

# The promise half the review workflow awaits: each call recorded with the
# arguments its blocking twin takes, its answer settled when it is made.
sub take_p ( $self, $id, $context = undef ) {
    return _settled( scalar $self->take($id) );
}

sub decide_p ( $self, $input, $context = undef ) {
    return _settled( scalar $self->decide($input) );
}

sub publish_reviewed_p (
    $self, $type, $input,
    $context = undef,
    $scope = undef
  )
{
    return _settled( scalar $self->publish_reviewed( $type, $input ) );
}

sub resolve_p ( $self, $user_id, $context = undef ) {
    return _settled( scalar $self->resolve($user_id) );
}

sub create_notification_p ( $self, $input, $context = undef ) {
    return _settled( scalar $self->create_notification($input) );
}

sub link_reply_p ( $self, $post_id, $target, $context = undef ) {
    return _settled( scalar $self->link_reply( $post_id, $target ) );
}

sub set_thread_tags_p ( $self, $thread_id, $text, $context = undef ) {
    return _settled( scalar $self->set_thread_tags( $thread_id, $text ) );
}

# The store's transaction: the work runs on the double as its own joined
# store, with no call layer.
sub in_transaction_p ( $self, $work, $context = undef ) {
    $self->transactions( $self->transactions + 1 );

    return $work->( $self, undef );
}

# The calls made to one method, each as its arguments.
sub made ( $self, $name ) {
    return [ map { $_->[1] } grep { $_->[0] eq $name } @{ $self->calls } ];
}

sub _settled ($answer) {
    return Mojo::Promise->resolve($answer);
}

sub _called ( $self, $name, @arguments ) {
    push @{ $self->calls }, [ $name, \@arguments ];
    my $answer = $self->answers->{$name};

    return
        ref $answer eq 'CODE' ? $answer->(@arguments)
      : defined $answer       ? $answer
      :                         { ok => 1, status => 'ok' };
}

1;
