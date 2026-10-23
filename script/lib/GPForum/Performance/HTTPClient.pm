# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Performance::HTTPClient;
use v5.40;
use Carp qw(croak);
use Const::Fast;
use Mojo::Base -base, -signatures;
use Mojo::UserAgent;
use Mojo::Promise;
use GPForum::Infrastructure::Id;
use GPForum::Performance::Support qw(monotonic);
our $VERSION = '0.001';
const my $MILLISECONDS => 1_000;
const my $HTTP_OK      => 200;
const my $TIMEOUT      => 20;
has [qw(base actor username password csrf collect)];
has ua => sub {
    return Mojo::UserAgent->new(
        max_redirects   => 0,
        request_timeout => $TIMEOUT
    );
};
has context => sub { return {}; };

sub timing ($headers) {
    my %time;
    for my $part ( split /,/msx, $headers // q{} ) {
        my ($kind)     = $part =~ /\A\s*(app|db)\b/msx;
        my ($duration) = $part =~
          /(?:\A|;)\s*dur=([[:digit:]]+(?:[.][[:digit:]]+)?)(?:;|\s*\z)/msx;
        if ( defined $kind && defined $duration ) {
            $time{$kind} = 0 + $duration;
        }
    }
    return \%time;
}

sub request_p ( $self, $spec ) {
    my $method = $spec->{method} // 'GET';
    my $path =
      ref $spec->{path} eq 'CODE'
      ? $spec->{path}->( $self->context )
      : $spec->{path};
    croak 'HTTP benchmark only admits relative local paths'
      if $path !~ m{\A/[^/]}msx && $path ne q{/};
    my %headers =
      ( Accept => $spec->{json} ? 'application/json' : 'text/html' );
    my @body;
    if ( $method eq 'POST' ) {
        my $fields =
          ref $spec->{form} eq 'CODE'
          ? $spec->{form}->( $self->context )
          : $spec->{form} // {};
        @body = (
            form => {
                csrf_token => $self->csrf,
                command_id => GPForum::Infrastructure::Id->new->uuid,
                %{$fields}
            }
        );
    }
    my $tx = $self->ua->build_tx(
        $method => $self->base . $path => \%headers => @body );
    my $started = monotonic();
    return $self->ua->start_p($tx)->then(
        sub ($result) {
            my $elapsed = ( monotonic() - $started ) * $MILLISECONDS;
            return $self->_received( $spec, $result->res, $elapsed );
        },
        sub ($error) {
            return $self->_transport_failed( $spec, $started, $error );
        }
    );
}

sub _transport_failed ( $self, $spec, $started, $error ) {
    my $row = {
        operation   => $spec->{name},
        actor       => $self->actor,
        method      => $spec->{method} // 'GET',
        route       => 'unknown',
        status_code => 0,
        valid       => 0,
        failure     => 'transport failure',
        elapsed_ms  => ( monotonic() - $started ) * $MILLISECONDS
    };
    if ( $self->collect ) { $self->collect->($row); }
    croak "$spec->{name}: transport failure: $error";
}

sub _received ( $self, $spec, $res, $elapsed ) {
    my $times = timing( $res->headers->header('Server-Timing') );
    my $row   = {
        operation => $spec->{name},
        actor     => $self->actor,
        method => $spec->{method}                                // 'GET',
        route  => $res->headers->header('X-GPForum-Bench-Route') // 'unknown',
        status_code => $res->code                                // 0,
        elapsed_ms  => $elapsed,
        app_ms      => $times->{app},
        db_ms       => $times->{db},
        bytes       => length( $res->body ),
        cache       => $res->headers->header('X-GPForum-Cache'),
        worker      => $res->headers->header('X-GPForum-Bench-Worker')
    };
    my $failure = _failure( $spec, $res );
    if ( !$failure && $spec->{key} ) {
        $row->{identity_key} = $spec->{key};
        $row->{identity}     = $res->json->{ $spec->{key} };
    }
    $row->{valid}   = $failure ? 0 : 1;
    $row->{failure} = $failure;
    if ( $self->collect ) { $self->collect->($row); }
    croak "$spec->{name}: $failure" if $failure;
    if ( $spec->{save} ) { $spec->{save}->( $self->context, $res ); }
    return $res;
}

sub _failure ( $spec, $res ) {
    return _http_failure( $spec, $res )
      if ( $res->code // 0 ) != ( $spec->{code} // $HTTP_OK );
    my $domain = _domain_failure( $spec, $res );
    return $domain if $domain;
    if ( $spec->{location}
        && ( $res->headers->location // q{} ) ne $spec->{location} )
    {
        return 'unexpected redirect destination';
    }
    return 'empty successful response'
      if !$res->is_redirect && !length $res->body;
    return 'response content did not confirm the operation'
      if $spec->{contains} && index( $res->body, $spec->{contains} ) < 0;
    return undef;
}

sub _domain_failure ( $spec, $res ) {
    if ( $spec->{status} ) {
        my $json = $res->json // {};
        return 'unexpected domain status: ' . ( $json->{status} // 'absent' )
          if ( $json->{status} // q{} ) ne $spec->{status};
    }
    if ( $spec->{ok} && !( ( $res->json // {} )->{ok} ) ) {
        return 'domain command did not succeed';
    }
    if ( $spec->{key}
        && !length( ( $res->json // {} )->{ $spec->{key} } // q{} ) )
    {
        return 'missing response identity';
    }
    return undef;
}

sub _http_failure ( $spec, $res ) {
    my $json = $res->json // {};
    return
        'HTTP '
      . ( $res->code // 0 )
      . '; expected '
      . ( $spec->{code} // $HTTP_OK )
      if ref( $json->{checks} ) ne 'ARRAY';
    return 'HTTP ' . ( $res->code // 0 ) . '; failed readiness: ' . join q{,},
      map { $_->{name} . q{:} . $_->{status} }
      grep { $_->{status} eq 'fail' } @{ $json->{checks} };
}

sub fields ( $res, $selector = 'form' ) {
    my $form = $res->dom->at($selector)
      // croak 'expected HTTP form is missing';
    return { map { ( $_->attr('name') => $_->attr('value') // q{} ) }
          $form->find('input[name]')->each };
}

sub login_p ($self) {
    return $self->request_p( { name => 'login_form', path => '/login' } )
      ->then(
        sub ($res) {
            my $form = fields( $res, 'form[action="/login"]' );
            $self->csrf( $form->{csrf_token} );
            return $self->request_p(
                {
                    name   => 'login_submit',
                    method => 'POST',
                    path   => '/login',
                    code   => 302,
                    form   => {
                        %{$form},
                        identifier => $self->username,
                        password   => $self->password
                    }
                }
            );
        }
      )->then(
        sub {
            return $self->request_p(
                { name => 'login_verify', path => '/settings' } );
        }
      )->then(
        sub ($res) {
            croak 'authenticated HTTP session is missing'
              if !$res->dom->at('form[action="/logout"]');
            $self->csrf(
                fields( $res, 'form[action="/logout"]' )->{csrf_token} );
            return $self;
        }
      );
}

sub steps_p ( $self, $steps ) {
    my $promise = Mojo::Promise->resolve;
    for my $step ( @{$steps} ) {
        $promise = $promise->then( sub { return $self->request_p($step); } );
    }
    return $promise;
}
1;
