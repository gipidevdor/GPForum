# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Admin::AnnouncementStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Admin::Event;
use GPForum::Service::Clock;
use GPForum::X;

our $VERSION = '0.001';

const my $DEFAULT_LIMIT => 50;
const my $ACTIVE_LIMIT  => 3;
const my $MESSAGE_MAX   => 500;
const my %TONES         => ( notice => 1, warning => 1 );

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };
has recorder   => sub ($self) {
    return GPForum::Infrastructure::EventRecorder->new(
        id_service => $self->id_service,
        schema     => $self->schema,
    );
};
has events => sub { return GPForum::Service::Admin::Event->new; };

__PACKAGE__->requires(qw(schema));

has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

# Publishes a few words from the operators: plain text, trimmed, up to 500
# characters, in a notice or a warning tone. Answers the row, or the errors
# of a message that cannot be published.
sub create_announcement ( $self, $input ) {
    my $message = _trim( $input->{message} );
    my $tone    = _trim( $input->{tone} ) || 'notice';
    my %errors;
    if ( !length $message ) {
        $errors{message} = 'message is required';
    }
    elsif ( length $message > $MESSAGE_MAX ) {
        $errors{message} = 'message is too long';
    }
    if ( !exists $TONES{$tone} ) {
        $errors{tone} = 'tone must be notice or warning';
    }
    return { errors => \%errors, ok => 0 } if %errors;

    my $announcement = {
        announcement_id => $self->id_service->uuid,
        created_at      => $self->clock->now_iso8601,
        created_by      => $input->{actor_user_id},
        message         => $message,
        retired_at      => undef,
        retired_by      => undef,
        tone            => $tone,
    };
    $self->_functions->row( 'admin_insert_announcement',
        { values => $announcement } );
    $self->_record_write(
        'announcement.published', $input->{actor_user_id},
        $announcement,            $announcement->{created_at}
    );
    return $announcement;
}

# Takes an announcement down. One already retired is answered as it is,
# with skipped; one that does not exist is nothing.
sub retire_announcement ( $self, $input ) {
    my $existing = $self->_functions->row( 'admin_announcement_by_id',
        { announcement_id => $input->{announcement_id} } );
    return undef                          if !$existing;
    return { %{$existing}, skipped => 1 } if defined $existing->{retired_at};

    my $retired_at = $self->clock->now_iso8601;
    my $retired    = $self->_functions->row(
        'admin_retire_announcement',
        {
            announcement_id => $input->{announcement_id},
            values          => {
                retired_at => $retired_at,
                retired_by => $input->{actor_user_id},
            },
        }
    );
    return { %{$existing}, skipped => 1 } if !$retired;
    $self->_record_write( 'announcement.retired', $input->{actor_user_id},
        $retired, $retired_at );
    return $retired;
}

sub list_announcements ( $self, $options = undef ) {
    return $self->_functions->rows( 'admin_list_announcements',
        { row_limit => $options->{limit} || $DEFAULT_LIMIT } );
}

sub active_announcements ( $self, $options = undef ) {
    return $self->_functions->rows( 'forum_active_announcements',
        { row_limit => $options->{limit} || $ACTIVE_LIMIT } );
}

sub _record_write ( $self, $action, $actor_user_id, $announcement, $at ) {
    my $payload = {
        action         => $action,
        actor_user_id  => $actor_user_id,
        announcement   => $announcement,
        correlation_id => $self->id_service->uuid,
        created_at     => $at,
    };
    $self->recorder->record_event(
        %{ $self->events->announcement_event($payload) } );
    $self->recorder->record_audit(
        %{ $self->events->announcement_audit($payload) } );
    return;
}

# Announcements exist only as api.* functions (ADR 0126): there is no Perl
# path to fall back to without them.
sub _functions ($self) {
    return $self->functions // GPForum::X::Argument->throw(
        message => 'announcements need the SQL function layer' );
}

sub _trim ($value) {
    return q{} if !defined $value;
    $value =~ s/\A\s+|\s+\z//gmsx;
    return $value;
}

1;

__END__

=head1 NAME

GPForum::Service::Admin::AnnouncementStore - The operators' site announcements.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $announcements = GPForum::Service::Admin::AnnouncementStore->new(
        schema => $schema,
    );
    $announcements->create_announcement(
        { actor_user_id => $admin_id, message => 'Back-ups tonight.', tone => 'notice' } );
    $announcements->active_announcements;

=head1 DESCRIPTION

A site announcement (ADR 0131) is a few words every page shows above its
content until an administrator retires it. Each publication and each
retirement records an event (C<announcement.published>,
C<announcement.retired>) and an audit row. Every statement is an
C<api.admin_*> or C<api.forum_*> function (ADR 0126).

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>). C<schema> is required.

=head2 create_announcement

Takes C<actor_user_id>, C<message> (plain text, 1 to 500 characters once
trimmed) and C<tone> (C<notice>, the default, or C<warning>). Returns the
announcement row, or C<< { ok => 0, errors } >> naming the field at fault.

=head2 retire_announcement

Takes C<actor_user_id> and C<announcement_id>. Returns the retired row;
one retired already comes back as it is with C<skipped>; an unknown id
returns nothing.

=head2 list_announcements

Every announcement, newest first, up to C<limit> (50 by default).

=head2 active_announcements

The announcements not retired, newest first, up to C<limit> (3 by default):
what every page shows.

=head1 DIAGNOSTICS

Throws L<GPForum::X::Argument> when the schema has no SQL function layer.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>, L<GPForum::Infrastructure::EventRecorder>.

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
