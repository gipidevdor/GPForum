# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::MemberNotesController;

use Mojo::Base -base, -signatures;
use v5.40;

use Mojolicious;

use GPForum::Infrastructure::Id;
use GPForum::ViewModel::Moderation::Presenter;

our $VERSION = '0.001';

# What GPForum::Web::MemberNotes asks of a controller, in one object: it is
# its own permission gate (answering through the code it is
# given as "answer") and its own note store (answering the "rows" it is given, or
# failing when they are not an array).
has answer => sub {
    return sub { return 0; };
};
has rows => sub { return []; };
has app  => sub { return Mojolicious->new; };

sub gp_permission_gate ($self) { return $self; }

sub gp_member_note_store ($self) { return $self; }

sub gp_moderation_view_model ($self) {
    return GPForum::ViewModel::Moderation::Presenter->new;
}

sub gp_id ($self) { return GPForum::Infrastructure::Id->new; }

sub for_member ( $self, $subject_user_id ) { return $self->_rows; }

sub for_reports ( $self, $report_ids ) { return $self->_rows; }

sub maximum_body ($self) { return 2000; }

sub _rows ($self) {
    die "unreadable\n"
      if ref $self->rows ne 'ARRAY' && ref $self->rows ne 'HASH';

    return $self->rows;
}

# The permission gate's question, answered by the code given.
sub allowed ( $self, $actor, $permission ) {
    return $self->answer->($permission);
}

1;

__END__

=head1 NAME

GPForum::Test::MemberNotesController - A controller, gate and note store for the staff notes blocks.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $controller = GPForum::Test::MemberNotesController->new(
        answer => sub ($permission) { return 1; },
        rows    => [ { note_id => $id, body => 'text' } ],
    );

=head1 DESCRIPTION

A double for L<GPForum::Web::MemberNotes> tests.

=head1 SUBROUTINES/METHODS

=head2 gp_permission_gate

=head2 gp_member_note_store

=head2 gp_moderation_view_model

=head2 gp_id

=head2 allowed

=head2 for_member

=head2 for_reports

=head2 maximum_body

=head1 DIAGNOSTICS

Reading rows that are not an array or a hash dies.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojolicious>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
