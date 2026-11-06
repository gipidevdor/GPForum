# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::PushTransport;
use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;
use Mojo::Promise;
use Mojo::IOLoop;
use Mojo::Message::Response;
const my $ACCEPTED => 201;
our $VERSION = '0.001';
has sent   => sub { return []; };
has active => 0;
has peak   => 0;
has fail   => 0;
sub prepare_p ( $self, $url ) { return Mojo::Promise->resolve($url); }

sub send_prepared_p ( $self, $url, $headers, $body, $deadline ) {
    return $self->send_p( $url, $headers, $body );
}

sub send_p ( $self, $url, $headers, $body ) {
    push @{ $self->sent }, { url => $url, headers => $headers, body => $body };
    $self->active( $self->active + 1 );
    if ( $self->active > $self->peak ) { $self->peak( $self->active ); }
    my $promise = Mojo::Promise->new;
    Mojo::IOLoop->next_tick(
        sub {
            $self->active( $self->active - 1 );
            if ( $self->fail ) { $promise->reject('transport failed'); }
            else {
                $promise->resolve(
                    Mojo::Message::Response->new( code => $ACCEPTED ) );
            }
        }
    );
    return $promise;
}

1;
