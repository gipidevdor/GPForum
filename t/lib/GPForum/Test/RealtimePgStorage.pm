# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RealtimePgStorage;

use v5.40;

our $VERSION = '0.001';

sub new {
    my ( $class, %input ) = @_;

    return bless { dbh => $input{dbh} }, $class;
}

sub dbh {
    my ($self) = @_;

    return $self->{dbh};
}

1;
