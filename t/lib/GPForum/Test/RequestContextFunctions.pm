# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::RequestContextFunctions;
use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::Promise;
our $VERSION = '0.001';
has calls => sub { return []; };

sub row_p ( $self, $name, $values, $context = undef ) {
    my $promise = Mojo::Promise->new;
    push @{ $self->calls },
      { name => $name, values => $values, promise => $promise };
    return $promise;
}
1;
