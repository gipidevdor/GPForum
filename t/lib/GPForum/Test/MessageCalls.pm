# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::MessageCalls;

use Mojo::Base 'GPForum::Test::SettledCalls', -signatures;
use v5.40;

use Mojo::Promise;

our $VERSION = '0.001';

# ADR 0139: one stand-in for the collaborators of direct messages -- the
# function layer (row, rows, transaction_p), the automod store (rules_for,
# record_decisions, in_transaction and their promise methods, and its
# functions: the double itself), the notification dispatcher
# (create_notification) and the preference store (delivery_plan). Every
# call is recorded with its arguments; each answers what `answers` holds
# under its name (a code reference is called with the arguments). The
# promise methods answer settled promises (ADR 0177).
has answers => sub { return {}; };
has calls   => sub { return []; };

# The call log is made with the double, so a copy shares it.
sub new ( $class, @arguments ) {
    my $self = $class->SUPER::new(@arguments);
    $self->calls;

    return $self;
}

sub functions ($self) { return $self; }

sub rules_for_p ( $self, $user_id, $context = undef ) {
    return Mojo::Promise->resolve( $self->rules_for($user_id) );
}

sub record_decisions_p ( $self, $input, $context = undef, $scope = undef ) {
    return Mojo::Promise->resolve( $self->record_decisions($input) );
}

# The work with the double as its transaction's call layer.
sub transaction_p ( $self, $work, $context = undef, $readonly = 0 ) {
    push @{ $self->calls }, ['transaction'];

    return $work->($self);
}

# How many transactions ran: counted in the call log, which a copy of the
# double -- the blocking layer's -- shares.
sub transactions ($self) { return scalar @{ $self->made('transaction') }; }

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
    push @{ $self->calls }, ['transaction'];

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
