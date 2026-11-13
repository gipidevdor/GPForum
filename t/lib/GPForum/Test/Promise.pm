# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::Promise;
use v5.40;
use Exporter     qw(import);
use Scalar::Util qw(blessed);
our @EXPORT_OK = qw(await_result);
our $VERSION   = '0.001';

sub await_result ($operation) {
    return $operation
      if !blessed($operation) || !$operation->isa('Mojo::Promise');
    my ( @values, $error );
    $operation->then( sub (@result) { @values = @result; return; } )
      ->catch( sub ($caught) { $error = $caught; return; } )
      ->wait;
    die $error if defined $error;    ## no critic (ErrorHandling::RequireCarping) -- retain the original promise rejection, including typed exceptions
    return wantarray ? @values : $values[0];
}
1;
