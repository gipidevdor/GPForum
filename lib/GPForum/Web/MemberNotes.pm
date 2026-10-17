# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::MemberNotes;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# ADR 0138: reading the notes needs the global member_note.view binding,
# writing them member_note.write.
const my $RESOURCE => 'member_note';
const my $VIEW     => 'view';
const my $WRITE    => 'write';

sub resource ($self) { return $RESOURCE; }

sub view_action ($self) { return $VIEW; }

sub write_action ($self) { return $WRITE; }

# Whether the signed-in member holds the global member_note binding for
# the action.
sub may ( $self, $controller, $user_id, $action ) {
    return 0 if !$user_id;

    return $controller->gp_permission_gate->allowed(
        { user_id => $user_id },
        {
            action        => $action,
            resource_type => $RESOURCE,
            resource_id   => undef,
            space_id      => undef,
        }
    ) ? 1 : 0;
}

# The notes block of a member's admin page, or undef for a reader who may
# not read notes. Notes that cannot be read leave the block saying so
# ({ unavailable => 1 }) rather than failing the page.
sub for_member ( $self, $controller, $user_id, $subject_user_id ) {
    return undef if !$self->may( $controller, $user_id, $VIEW );

    my $store = $controller->gp_member_note_store;
    my $rows =
      _read( $controller, sub { $store->for_member($subject_user_id) } );
    return { unavailable => 1 } if !$rows;

    return $controller->gp_moderation_view_model->member_notes(
        add_command_id  => $controller->gp_id->uuid,
        can_write       => $self->may( $controller, $user_id, $WRITE ),
        maximum         => $store->maximum_body,
        note_total      => @{$rows} ? $rows->[0]{note_total} : 0,
        notes           => $rows,
        scope           => 'member',
        subject_user_id => $subject_user_id,
    );
}

# The notes blocks beside the reports, by report id: empty for a reader
# who may not read notes. The second value is true when the notes could not
# be read, so the queue says so and still lists the reports.
sub for_reports ( $self, $controller, $user_id, $reports ) {
    return ( {}, 0 ) if !@{ $reports || [] };
    return ( {}, 0 ) if !$self->may( $controller, $user_id, $VIEW );

    my $store     = $controller->gp_member_note_store;
    my $can_write = $self->may( $controller, $user_id, $WRITE );
    my @ids       = map { $_->{report_id} } @{$reports};
    my $found     = _read( $controller, sub { $store->for_reports( \@ids ) } );
    return ( {}, 1 ) if !$found;

    my %blocks;
    for my $report_id ( keys %{$found} ) {
        my $entry = $found->{$report_id};
        $blocks{$report_id} =
          $controller->gp_moderation_view_model->member_notes(
            %{$entry},
            add_command_id => $can_write ? $controller->gp_id->uuid : undef,
            can_write      => $can_write,
            maximum        => $store->maximum_body,
            scope          => "report-$report_id",
          );
    }

    return ( \%blocks, 0 );
}

sub _read ( $controller, $code ) {
    my $found;
    try {
        $found = $code->();
    }
    catch ($error) {
        $controller->app->log->warn("member notes unavailable: $error");
        return undef;
    };

    return $found;
}

1;

__END__

=head1 NAME

GPForum::Web::MemberNotes - The staff notes blocks of the admin and report pages.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $notes = GPForum::Web::MemberNotes->new;
    my $block = $notes->for_member( $c, $staff_id, $member_id );
    my $by_report = $notes->for_reports( $c, $staff_id, $reports );

=head1 DESCRIPTION

ADR 0138: reads the notes about a member for the member's admin page, and
the notes about the member each report is about for the report queue, only
for a reader holding the global C<member_note.view> binding; the add, edit
and delete forms are offered only with C<member_note.write>.

=head1 SUBROUTINES/METHODS

=head2 resource

C<member_note>.

=head2 view_action

C<view>.

=head2 write_action

C<write>.

=head2 may

Whether a member holds the global binding for the action.

=head2 for_member

The block of a member's admin page, or undef; C<< { unavailable => 1 } >>
when the notes cannot be read.

=head2 for_reports

The blocks beside the reports, by report id, and whether the notes could
not be read.

=head1 DIAGNOSTICS

A failure to read the notes is logged as a warning and answered as
unavailable, so the page it is part of still renders.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

The controller's C<gp_permission_gate>, C<gp_member_note_store>,
C<gp_moderation_view_model> and C<gp_id> helpers.

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
