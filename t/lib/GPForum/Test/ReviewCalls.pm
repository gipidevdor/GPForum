# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::ReviewCalls;

use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Service::Forum::Viewer;

our $VERSION = '0.001';

# ADR 0134: one stand-in for each collaborator of the review queue -- the
# review store, the posting workflow, the viewer resolver, the notification
# dispatcher, the reply links and the automod store. Every call is
# recorded; each answers what `answers` holds under its name (a code
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

sub maximum_reason ($self) { return 500; }

sub in_transaction ( $self, $code ) {
    $self->transactions( $self->transactions + 1 );

    return $code->();
}

# The calls made to one method, each as its arguments.
sub made ( $self, $name ) {
    return [ map { $_->[1] } grep { $_->[0] eq $name } @{ $self->calls } ];
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
