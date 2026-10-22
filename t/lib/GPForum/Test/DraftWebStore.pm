# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::DraftWebStore;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

has entries => sub { return {}; };
has saves   => sub { return []; };
has refusal => undef;

sub save ( $self, $input ) {
    push @{ $self->saves }, { %{$input} };
    return { ok => 0, status => $self->refusal } if $self->refusal;
    my $draft = { %{$input}, draft_revision => 1 };
    $self->entries->{ $draft->{draft_id} } = $draft;
    return { ok => 1, status => 'ok', draft => $draft };
}

sub find ( $self, $owner, $id ) {
    my $draft = $self->entries->{$id};
    return undef if !$draft || $draft->{owner_user_id} ne $owner;
    return { %{$draft} };
}

sub list_for_user ( $self, $owner ) {
    my @owned;
    for my $draft ( values %{ $self->entries } ) {
        if ( $draft->{owner_user_id} eq $owner ) {
            push @owned, { %{$draft} };
        }
    }
    return \@owned;
}

sub remove ( $self, $input ) {
    return { ok => 0, status => $self->refusal } if $self->refusal;
    my $draft = $self->find( $input->{owner_user_id}, $input->{draft_id} );
    return { ok => 0, status => 'not_found' } if !$draft;
    delete $self->entries->{ $input->{draft_id} };
    return { ok => 1, status => 'ok' };
}

1;

__END__

=head1 NAME

GPForum::Test::DraftWebStore - Controlled draft responses for HTTP boundary tests.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

Used by the forum composer routes and their tests.

=head1 DESCRIPTION

Captures controller input and returns owner-private rows or an explicit
refusal. PostgreSQL integration tests cover revision and publication semantics.

=head1 SUBROUTINES/METHODS

C<save>, C<find>, C<list_for_user> and C<remove> implement the draft store
interface for route tests. C<refusal> sets the returned failure status.

=head1 DIAGNOSTICS

Returns explicit draft statuses for the caller.

=head1 CONFIGURATION AND ENVIRONMENT

No environment variables are read directly.

=head1 DEPENDENCIES

L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Draft retention and authorization are enforced by the production store.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
