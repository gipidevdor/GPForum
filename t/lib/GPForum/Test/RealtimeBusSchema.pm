# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RealtimeBusSchema;

use Mojo::Base -base;
use v5.40;

use GPForum::Test::RealtimeBusStorage;

our $VERSION = '0.001';

has dbh => undef;

sub storage {
    my ($self) = @_;

    return GPForum::Test::RealtimeBusStorage->new( dbh => $self->dbh );
}

1;
