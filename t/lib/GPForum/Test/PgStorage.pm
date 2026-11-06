# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::PgStorage;
use Mojo::Base 'GPForum::Infrastructure::PgStorage', -signatures;
use v5.40;
use Scalar::Util qw(weaken);
our $VERSION = '0.001';

sub bind_fixture ( $self, $storage ) {
    $self->{fixture_storage} = $storage;
    weaken( $self->{fixture_storage} );
    if ( $self->debugobj ) { $storage->debugobj( $self->debugobj ); }
    if ( $self->debugcb )  { $storage->debugcb( $self->debugcb ); }
    $storage->debug( $self->debug );
    return;
}
sub debug   ( $self, @value ) { return $self->_observer( 'debug',   @value ); }
sub debugcb ( $self, @value ) { return $self->_observer( 'debugcb', @value ); }

sub debugobj ( $self, @value ) {
    return $self->_observer( 'debugobj', @value );
}

sub _observer ( $self, $name, @value ) {
    return $self->{$name} // ( $name eq 'debug' ? 0 : undef ) if !@value;
    $self->{$name} = $value[0];
    if ( $self->{fixture_storage} ) {
        $self->{fixture_storage}->$name( $value[0] );
    }
    return $self;
}
1;
