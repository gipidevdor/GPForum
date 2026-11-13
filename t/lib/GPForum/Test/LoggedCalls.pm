# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::LoggedCalls;

use Mojo::Base 'GPForum::Test::SettledCalls', -signatures;
use v5.40;

our $VERSION = '0.001';

# The command log of the functions that keep one (ADR 0126, section 5), in
# memory: a command once per idempotency key, its answer recorded, a repeat
# of its request replayed, another request a conflict. A write that dies
# records nothing, as a rolled-back call does. A subclass answers rows and
# calls logged() from them.
has log    => sub { return {}; };
has calls  => sub { return []; };
has schema => sub { return {}; };

sub row ( $self, $name, $values ) {
    return $self->rows( $name, $values )->[0];
}

# The function's row for a command: the answer given before the call when
# there is one, else what $write answers -- the response, and the columns
# the row carries beside it.
sub logged ( $self, $key, $hash, $answer, $write ) {
    if ( my $kept = $self->log->{$key} ) {
        return { outcome => 'conflict' } if $kept->{hash} ne $hash;
        return { outcome => 'replayed', response => $kept->{response} };
    }
    my ( $response, $columns ) = defined $answer ? ($answer) : $write->();
    $self->log->{$key} = { hash => $hash, response => $response };

    return {
        %{ $columns // {} },
        outcome  => 'recorded',
        response => $response
    };
}

1;

__END__

=head1 NAME

GPForum::Test::LoggedCalls - The in-memory command log of a call-layer double.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    package GPForum::Test::CommunityFunctions;
    use Mojo::Base 'GPForum::Test::LoggedCalls', -signatures;

    sub rows ( $self, $name, $values ) {
        my $log = $values->{log};
        return [ $self->logged( $log->{idempotency_key},
            $log->{request_hash}, $values->{answer}, sub { ... } ) ];
    }

=head1 DESCRIPTION

The base of the doubles that stand in for the functions keeping a command
log -- C<api.forum_write_command>, C<api.community_bookmark_command> and
their kin -- so a workflow's own Perl runs as it runs on PostgreSQL. Its
promises are settled (L<GPForum::Test::SettledCalls>).

=head1 SUBROUTINES/METHODS

=head2 log

The command log: by idempotency key, the request's hash and the response.

=head2 calls

Each call made, as C<[ $name, $values ]>, for a subclass that records them.

=head2 schema

A placeholder: the layer has no schema.

=head2 row

The first of the subclass's C<rows>.

=head2 logged

Takes a command's key, its request's hash, the answer given before the
call (or undef) and a code reference writing it, which answers the
response and the row's other columns. Answers the function's row: the
outcome C<recorded>, C<replayed> or C<conflict>, and the response.

=head1 DIAGNOSTICS

None of its own: a write that dies propagates, and records nothing.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Test::SettledCalls>.

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
