# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::AutomodStore;

use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Service::Moderation::Automod;

our $VERSION = '0.001';

# ADR 0133: the automod store's stand-in. It answers the rules and words it
# is given, records the decisions and the staff changes, and runs a
# transaction by calling the code; a failing one dies when it records.
has automod      => sub { return GPForum::Service::Moderation::Automod->new; };
has rules        => undef;
has words        => sub { return []; };
has calls        => sub { return []; };
has recorded     => sub { return []; };
has transactions => 0;
has fail         => 0;
has answer       => undef;

sub rules_for ( $self, $user_id ) { return $self->rules; }

sub record_decisions ( $self, $input ) {
    die "record failed\n" if $self->fail;
    push @{ $self->recorded }, $input;

    return { flagged => $input->{report} ? 1 : 0 };
}

sub in_transaction ( $self, $code ) {
    $self->transactions( $self->transactions + 1 );

    return $code->();
}

sub add_word ( $self, $input ) { return $self->_called( add_word => $input ); }

sub remove_word ( $self, $input ) {
    return $self->_called( remove_word => $input );
}

sub set_link_rule ( $self, $input ) {
    return $self->_called( set_link_rule => $input );
}

sub _called ( $self, $name, $input ) {
    push @{ $self->calls }, [ $name, $input ];

    return $self->answer // { ok => 1, status => 'ok' };
}

1;
