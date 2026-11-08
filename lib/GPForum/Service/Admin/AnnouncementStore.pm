# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Admin::AnnouncementStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;
use Mojo::Promise;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Text qw(trimmed);
use GPForum::Service::Admin::Event;
use GPForum::Service::Clock;
use GPForum::X;

our $VERSION = '0.001';

const my $DEFAULT_LIMIT => 50;
const my $ACTIVE_LIMIT  => 3;
const my $MESSAGE_MAX   => 500;
const my %TONES         => ( notice => 1, warning => 1 );

# Every page shows the active announcements, so they are read once per
# cache lifetime, not once per request, under their own tag: the admin
# workflow purges it with the public cache after a write, and the
# announcement events purge it in the shared cache.
const my $DEFAULT_CACHE_TTL_SECONDS => 30;
const my $CACHE_TAG                 => 'announcements';

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };
has recorder   => \&GPForum::Infrastructure::EventRecorder::for_service;
has events     => sub { return GPForum::Service::Admin::Event->new; };

has cache       => undef;    # optional: without it every page reads the list
has cache_epoch => undef;    # optional: missing required epoch bypasses cache
has cache_epoch_required => 0;
has cache_ttl_seconds    => sub { return $DEFAULT_CACHE_TTL_SECONDS; };

__PACKAGE__->requires(qw(schema));

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Publishes a few words from the operators: plain text, trimmed, up to 500
# characters, in a notice or a warning tone. Answers the row, or the errors
# of a message that cannot be published.
sub create_announcement ( $self, $input ) {
    my $announcement = $self->_new_announcement($input);
    return $announcement if !$announcement->{announcement_id};
    $self->_functions->row( 'admin_insert_announcement',
        { values => $announcement } );
    $self->_record_write(
        'announcement.published', $input->{actor_user_id},
        $announcement,            $announcement->{created_at}
    );
    return $announcement;
}

# The two announcement writes on a pooled asynchronous connection, inside
# the caller's transaction ($scope, the call layer transaction_p hands its
# work) or in one of their own, with the blocking writes' answers.
async sub create_announcement_p ( $self, $input, $context = undef,
    $scope = undef )
{
    my $announcement = $self->_new_announcement($input);
    return $announcement if !$announcement->{announcement_id};
    my $work = async sub ($functions) {
        await $functions->row_p( 'admin_insert_announcement',
            { values => $announcement }, $context );
        await $self->_record_write_p(
            $functions,
            [
                'announcement.published', $input->{actor_user_id},
                $announcement,            $announcement->{created_at}
            ],
            $context
        );
        return $announcement;
    };
    return await(
          $scope
        ? $work->($scope)
        : $self->_functions->transaction_p( $work, $context )
    );
}

async sub retire_announcement_p ( $self, $input, $context = undef,
    $scope = undef )
{
    my $work = async sub ($functions) {
        my $existing = await $functions->row_p( 'admin_announcement_by_id',
            { announcement_id => $input->{announcement_id} }, $context );
        return undef if !$existing;
        return { %{$existing}, skipped => 1 }
          if defined $existing->{retired_at};

        my $retired_at = $self->clock->now_iso8601;
        my $retired =
          await $functions->row_p( _retire_call( $input, $retired_at ),
            $context );
        return { %{$existing}, skipped => 1 } if !$retired;
        await $self->_record_write_p(
            $functions,
            [
                'announcement.retired', $input->{actor_user_id},
                $retired,               $retired_at
            ],
            $context
        );
        return $retired;
    };
    return await(
          $scope
        ? $work->($scope)
        : $self->_functions->transaction_p( $work, $context )
    );
}

# The announcement a create writes, or the errors of a message that cannot
# be published.
sub _new_announcement ( $self, $input ) {
    my $message = trimmed( $input->{message} );
    my $tone    = trimmed( $input->{tone} ) || 'notice';
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

    return {
        announcement_id => $self->id_service->uuid,
        created_at      => $self->clock->now_iso8601,
        created_by      => $input->{actor_user_id},
        message         => $message,
        retired_at      => undef,
        retired_by      => undef,
        tone            => $tone,
    };
}

# Takes an announcement down. One already retired is answered as it is,
# with skipped; one that does not exist is nothing.
sub retire_announcement ( $self, $input ) {
    my $existing = $self->_functions->row( 'admin_announcement_by_id',
        { announcement_id => $input->{announcement_id} } );
    return undef                          if !$existing;
    return { %{$existing}, skipped => 1 } if defined $existing->{retired_at};

    my $retired_at = $self->clock->now_iso8601;
    my $retired = $self->_functions->row( _retire_call( $input, $retired_at ) );
    return { %{$existing}, skipped => 1 } if !$retired;
    $self->_record_write( 'announcement.retired', $input->{actor_user_id},
        $retired, $retired_at );
    return $retired;
}

sub list_announcements ( $self, $options = undef ) {
    return $self->_functions->rows( 'admin_list_announcements',
        { row_limit => $options->{limit} || $DEFAULT_LIMIT } );
}

# The announcements page's list on the worker's pooled asynchronous
# connections, not a forked child with a connection of its own.
async sub list_announcements_p ( $self, $options = undef, $context = undef ) {
    return await $self->_functions->rows_p( 'admin_list_announcements',
        { row_limit => $options->{limit} || $DEFAULT_LIMIT }, $context );
}

sub active_announcements_p ( $self, $options = undef, $context = undef ) {
    $options //= {};
    my $limit = $options->{limit} || $ACTIVE_LIMIT;
    my $cache = $self->cache;
    my $usable =
      $cache && ( !$self->cache_epoch_required || defined $self->cache_epoch );
    my $key = "announcements:active:$limit";
    if ( defined $self->cache_epoch ) {
        $key .= q{:privacy:} . $self->cache_epoch;
    }
    my $ticket;
    if ($usable) {
        my $cached = $cache->get($key);
        return Mojo::Promise->resolve($cached) if defined $cached;
        if ( $cache->can('ticket') ) {
            $ticket = $cache->ticket( [$CACHE_TAG], { mint => 1 } );
        }
    }
    return $self->_functions->rows_p( 'forum_active_announcements',
        { row_limit => $limit }, $context )->then(
        sub ($rows) {
            if ($usable) {
                $cache->put(
                    $key, $rows,
                    {
                        tags        => [$CACHE_TAG],
                        ttl_seconds => $self->cache_ttl_seconds,
                        ticket      => $ticket
                    }
                );
            }
            return $rows;
        }
        );
}

sub active_announcements ( $self, $options = undef ) {
    my $limit = $options->{limit} || $ACTIVE_LIMIT;
    my $cache = $self->cache;
    return $self->_active_rows($limit)
      if !$cache
      || ( $self->cache_epoch_required && !defined $self->cache_epoch );

    my $key = "announcements:active:$limit";
    if ( defined $self->cache_epoch ) {
        $key .= q{:privacy:} . $self->cache_epoch;
    }

    return $cache->get_or_set(
        $key,
        sub { return $self->_active_rows($limit); },
        { tags => [$CACHE_TAG], ttl_seconds => $self->cache_ttl_seconds },
    );
}

sub _active_rows ( $self, $limit ) {
    return $self->_functions->rows( 'forum_active_announcements',
        { row_limit => $limit } );
}

sub _retire_call ( $input, $retired_at ) {
    return (
        'admin_retire_announcement',
        {
            announcement_id => $input->{announcement_id},
            values          => {
                retired_at => $retired_at,
                retired_by => $input->{actor_user_id},
            },
        }
    );
}

sub _record_write ( $self, $action, $actor_user_id, $announcement, $at ) {
    my $payload =
      $self->_write_payload( $action, $actor_user_id, $announcement, $at );
    $self->recorder->record_event(
        %{ $self->events->announcement_event($payload) } );
    $self->recorder->record_audit(
        %{ $self->events->announcement_audit($payload) } );
    return;
}

async sub _record_write_p ( $self, $functions, $write, $context ) {
    my $payload = $self->_write_payload( @{$write} );
    await $functions->row_p(
        'ops_record_event',
        $self->recorder->event_call(
            %{ $self->events->announcement_event($payload) }
        ),
        $context
    );
    await $functions->row_p(
        'ops_record_audit',
        $self->recorder->audit_call(
            %{ $self->events->announcement_audit($payload) }
        ),
        $context
    );
    return;
}

sub _write_payload ( $self, $action, $actor_user_id, $announcement, $at ) {
    return {
        action         => $action,
        actor_user_id  => $actor_user_id,
        announcement   => $announcement,
        correlation_id => $self->id_service->uuid,
        created_at     => $at,
    };
}

# Announcements exist only as api.* functions (ADR 0126): there is no Perl
# path to fall back to without them.
sub _functions ($self) {
    return $self->functions // GPForum::X::Argument->throw(
        message => 'announcements need the SQL function layer' );
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

=head2 create_announcement_p

Publishes as L</create_announcement> does, on a pooled asynchronous
connection: inside the transaction of the call layer given as its last
argument, or in one of its own.

=head2 retire_announcement

Takes C<actor_user_id> and C<announcement_id>. Returns the retired row;
one retired already comes back as it is with C<skipped>; an unknown id
returns nothing.

=head2 retire_announcement_p

Retires as L</retire_announcement> does, on a pooled asynchronous
connection: inside the transaction of the call layer given as its last
argument, or in one of its own.

=head2 list_announcements

Every announcement, newest first, up to C<limit> (50 by default).

=head2 list_announcements_p

L</list_announcements> as a promise, with an optional query context last,
read on the worker's pooled asynchronous connections.

=head2 active_announcements

The announcements not retired, newest first, up to C<limit> (3 by default):
what every page shows. With a C<cache>, the list is read once per
C<cache_ttl_seconds> and dropped by a purge of the C<announcements> tag,
which every announcement write causes.

=head2 active_announcements_p

Reads active announcements without blocking. Cache lookup and insertion stay in the web process, with a ticket preventing an invalidated in-flight read from refilling stale data.

=head1 DIAGNOSTICS

Throws L<GPForum::X::Argument> when the schema has no SQL function layer.

=head1 CONFIGURATION AND ENVIRONMENT

C<cache_epoch> namespaces cached source data by the request's committed
public-content revocation epoch. C<cache_epoch_required> bypasses caching
when that epoch is unavailable; production enables this guard.

C<cache> (optional) is the application cache the active list is kept in,
for C<cache_ttl_seconds> (30 by default).

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>, L<GPForum::Infrastructure::EventRecorder>.

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
