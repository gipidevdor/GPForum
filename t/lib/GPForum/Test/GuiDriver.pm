# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::GuiDriver;
use Mojo::Base -base, -signatures;
use v5.40;
use Carp qw(croak);
use Const::Fast;
const my $HTTP_OK    => 200;
const my $HTTP_FOUND => 302;
use GPForum::Test::GuiForm;
our $VERSION = '0.001';
has test => undef;

sub install_session ($self) {
    my $routes = $self->test->app->routes;
    $routes->get('/__features/session/:id')->to(
        cb => sub($c) {
            %{ $c->session } = ();
            $c->session( user_id => $c->param('id') );
            return $c->render( text => 'ready' );
        }
    );
    return;
}

sub actor ( $self, $id ) {
    $self->test->get_ok( '/__features/session/' . $id )->status_is($HTTP_OK);
    return $self;
}

sub visit ( $self, $url, $status = $HTTP_OK ) {
    $self->test->get_ok($url)->status_is($status);
    return $self;
}

sub submit (
    $self, $selector,
    $values = {},
    $status = $HTTP_FOUND,
    $button = undef
  )
{
    my $response = $self->test->tx->res;
    my $dom      = $response->dom;
    my $form     = $dom->at($selector) or croak "Missing GUI form $selector";
    my $submitter =
      defined $button ? $form->at($button) : $self->_submitter( $dom, $form );
    croak "Missing GUI submitter $button" if defined $button && !$submitter;
    my $request = GPForum::Test::GuiForm->request( $form, $values, $submitter );
    my $method  = $request->{method};
    croak "Unexpected GUI method $method" if $method ne 'post';
    $self->test->post_ok( $request->{action} => form => $request->{fields} )
      ->status_is($status);
    return $self;
}

sub _submitter ( $self, $dom, $form ) {
    my $form_id = $form->attr('id') // q{};
    my @buttons = grep {
             ( !exists $_->attr->{disabled} )
          && ( lc( $_->attr('type') // 'submit' ) eq 'submit' )
          && ( !defined $_->attr('form') || $_->attr('form') eq $form_id )
    } $form->find('button, input[type="submit"]')->each;
    if ( !@buttons && length $form_id ) {
        @buttons = grep {
            ( $_->attr('form') // q{} ) eq $form_id
              && !exists $_->attr->{disabled}
        } $dom->find('button[type="submit"][form]')->each;
    }
    croak 'The GUI form has no available submit control' if !@buttons;
    croak 'Choose the GUI submit control explicitly'     if @buttons > 1;
    return $buttons[0];
}
1;
