# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::MessageCalls;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# ADR 0139: one stand-in for the collaborators of direct messages -- the
# function layer (row, rows), the automod store (rules_for,
# record_decisions, in_transaction), the notification dispatcher
# (create_notification) and the preference store (delivery_plan). Every
# call is recorded with its arguments; each answers what `answers` holds
# under its name (a code reference is called with the arguments).
has answers      => sub { return {}; };
has calls        => sub { return []; };
has transactions => 0;

sub row ( $self, @arguments ) { return $self->_called( row => @arguments ); }

sub rows ( $self, @arguments ) {
    return $self->_called( rows => @arguments ) // [];
}

sub rules_for ( $self, @arguments ) {
    return $self->_called( rules_for => @arguments );
}

sub record_decisions ( $self, @arguments ) {
    return $self->_called( record_decisions => @arguments );
}

sub create_notification ( $self, @arguments ) {
    return $self->_called( create_notification => @arguments );
}

sub delivery_plan ( $self, @arguments ) {
    return $self->_called( delivery_plan => @arguments );
}

sub in_transaction ( $self, $code ) {
    $self->transactions( $self->transactions + 1 );

    return $code->();
}

# The calls made of one kind, each its arguments.
sub made ( $self, $kind ) {
    return [
        map  { [ @{$_}[ 1 .. $#{$_} ] ] }
        grep { $_->[0] eq $kind } @{ $self->calls }
    ];
}

sub _called ( $self, $kind, @arguments ) {
    push @{ $self->calls }, [ $kind, @arguments ];
    my $answer = $self->answers->{$kind};

    # The function layer answers by the function's name.
    if ( $kind eq 'row' || $kind eq 'rows' ) {
        $answer = ref $answer eq 'HASH' ? $answer->{ $arguments[0] } : undef;
    }

    return ref $answer eq 'CODE' ? $answer->(@arguments) : $answer;
}

1;
