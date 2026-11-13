# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::MentionFunctions;

use Mojo::Base 'GPForum::Test::AnsweringFunctions', -signatures;
use v5.40;

our $VERSION = '0.001';

# The functions a mention store calls, over a list of members: their
# usernames resolve, case-insensitively, and every mention is created.
has users => sub { return []; };

has answers => sub ($self) {
    return {
        community_resolve_mention_users => sub ($values) {
            my %asked = map { lc() => 1 } @{ $values->{usernames} };
            return [
                map  { +{ id => $_->{id}, username => $_->{username} } }
                grep { $asked{ lc $_->{username} } } @{ $self->users }
            ];
        },
        community_create_mention =>
          sub ($values) { return [ { result => $values->{row} } ]; },
    };
};

# The mentions created, in order.
sub created ($self) {
    return [ map { $_->{row} } @{ $self->asked('community_create_mention') } ];
}

1;

__END__

=head1 NAME

GPForum::Test::MentionFunctions - The mention store's functions over a list of members.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $functions = GPForum::Test::MentionFunctions->new(
        users => [ { id => 'user-1', username => 'user001' } ] );
    my $store = GPForum::Service::Community::MentionStore->new(
        functions => $functions, schema => {} );

=head1 DESCRIPTION

An L<GPForum::Test::AnsweringFunctions> answering
C<community_resolve_mention_users> from C<users> and creating every mention
C<community_create_mention> is asked for.

=head1 SUBROUTINES/METHODS

=head2 users

The members, each with C<id> and C<username>.

=head2 answers

The two functions' answers.

=head2 created

The rows of the mentions created, in order.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Test::AnsweringFunctions>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
