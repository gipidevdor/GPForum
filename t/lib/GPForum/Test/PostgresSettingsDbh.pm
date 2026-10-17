# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::PostgresSettingsDbh;
use Mojo::Base -base, -signatures;
use v5.40;
our $VERSION = '0.001';
has rows => sub { return {}; };

sub selectall_arrayref ( $self, $sql, $attributes, @names ) {
    return [
        map  { +{ name => $_, %{ $self->rows->{$_} } } }
        grep { exists $self->rows->{$_} } @names
    ];
}
1;
