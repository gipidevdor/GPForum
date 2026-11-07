# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Admin::AddressBans;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Admin::Base', -async_await;
use v5.40;

use GPForum::Web::ClientAddress;

our $VERSION = '0.001';

const my $HTTP_OK          => 200;
const my $HTTP_CREATED     => 201;
const my $HTTP_BAD_REQUEST => 400;
const my $HTTP_NOT_FOUND   => 404;
const my $HTTP_CONFLICT    => 409;
const my $PAGE             => 'admin_address_bans';

# ADR 0146: what each answer says, and with which status.
const my %STATUS => (
    invalid     => $HTTP_BAD_REQUEST,
    too_broad   => $HTTP_BAD_REQUEST,
    not_found   => $HTTP_NOT_FOUND,
    conflict    => $HTTP_CONFLICT,
    duplicate   => $HTTP_CONFLICT,
    covers_self => $HTTP_CONFLICT,
    ended       => $HTTP_CONFLICT,
);
const my %SUCCESS => map { $_ => 1 } qw(ok replayed unchanged);
const my %FLASH => (
    placed      => 'admin.address_ban_placed',
    edited      => 'admin.address_ban_edited',
    lifted      => 'admin.address_ban_lifted',
    replayed    => 'admin.address_ban_placed',
    unchanged   => 'admin.address_ban_unchanged',
    too_broad   => 'admin.address_ban_too_broad',
    not_found   => 'admin.address_ban_not_found',
    conflict    => 'admin.address_ban_conflict',
    duplicate   => 'admin.address_ban_duplicate',
    covers_self => 'admin.address_ban_covers_self',
    ended       => 'admin.address_ban_ended',
);

# The catalogue's words for each scope, length and state.
const my %SCOPE_LABEL => map { $_ => "admin.address_ban_scope_$_" }
  qw(registration sign_in writes);
const my %DURATION_LABEL => map { $_ => "admin.address_ban_duration_$_" }
  qw(1h 1d 7d 30d 90d 365d);
const my %STATE_LABEL => map { $_ => "admin.address_ban_state_$_" }
  qw(active expired lifted);
const my %INVALID => (
    range    => 'admin.address_ban_invalid_range',
    scope    => 'admin.address_ban_invalid_scope',
    reason   => 'admin.address_ban_invalid_reason',
    duration => 'admin.address_ban_invalid_duration',
);

# The bans, live first, the form that places one, and the answer to "which
# ban covers this address?" when the page is asked it.
async sub show ($self) {
    my $user_id = (
        await $self->await_p(
            $self->authorized_user_id( $self->admin_access->view_action )
        )
    );
    return if !$user_id;

    my %page;
    try {
        %page = ( await $self->await_p( $self->_page ) );
    }
    catch ($error) {
        $self->app->log->error("admin address bans failed: $error");
        return $self->system_failure;
    };
    $self->res->headers->cache_control('private, no-store');
    return $self->render( json => \%page, status => $HTTP_OK )
      if $self->wants_json;

    return $self->render(
        template          => 'admin/address_bans',
        status            => $HTTP_OK,
        create_command_id => $self->gp_id->uuid,
        scopes            => $self->gp_address_bans->scopes,
        durations         => $self->gp_address_bans->durations,
        maximum_reason    => $self->gp_address_bans->maximum_reason,
        scope_labels      => \%SCOPE_LABEL,
        duration_labels   => \%DURATION_LABEL,
        state_labels      => \%STATE_LABEL,
        %page,
    );
}

async sub create ($self) {
    my $user_id = ( await $self->await_p( $self->_writer ) );
    return if !$user_id;

    return (
        await $self->await_p(
            $self->_answer(
                'placed',
                (
                    await $self->await_p(
                        $self->_stored(
                            async sub ($bans) {
                                return (
                                    await $self->call_p(
                                        $bans, 'place',
                                        {
                                            range    => $self->param('range'),
                                            scope    => $self->param('scope'),
                                            duration =>
                                              $self->param('duration'),
                                            reason => $self->param('reason'),
                                            command_id =>
                                              $self->param('command_id'),
                                            actor_user_id => $user_id,
                                            actor_address => $self->_client,
                                        }
                                    )
                                );
                            }
                        )
                    )
                )
            )
        )
    );
}

async sub update ($self) {
    my $user_id = ( await $self->await_p( $self->_writer ) );
    return if !$user_id;

    return (
        await $self->await_p(
            $self->_answer(
                'edited',
                (
                    await $self->await_p(
                        $self->_stored(
                            async sub ($bans) {
                                return (
                                    await $self->call_p(
                                        $bans, 'edit',
                                        {
                                            ban_id   => $self->stash('ban_id'),
                                            scope    => $self->param('scope'),
                                            duration =>
                                              $self->param('duration'),
                                            reason => $self->param('reason'),
                                            actor_user_id => $user_id,
                                            actor_address => $self->_client,
                                        }
                                    )
                                );
                            }
                        )
                    )
                )
            )
        )
    );
}

async sub lift ($self) {
    my $user_id = ( await $self->await_p( $self->_writer ) );
    return if !$user_id;

    return (
        await $self->await_p(
            $self->_answer(
                'lifted',
                (
                    await $self->await_p(
                        $self->_stored(
                            async sub ($bans) {
                                return (
                                    await $self->call_p(
                                        $bans, 'lift',
                                        {
                                            ban_id => $self->stash('ban_id'),
                                            actor_user_id => $user_id,
                                        }
                                    )
                                );
                            }
                        )
                    )
                )
            )
        )
    );
}

async sub _page ($self) {
    my $bans = $self->gp_address_bans;
    my $rows = ( await $self->call_p( $bans, 'list' ) );
    my %page = (
        bans           => [ map { _shown( $bans, $_ ) } @{$rows} ],
        live_total     => @{$rows} ? 0 + $rows->[0]{live_total} : 0,
        client_address =>
          ( await $self->call_p( $bans, 'address', $self->_client ) ),
        check => undef,
    );

    my $asked = $self->param('check');
    if ( defined $asked && length $asked ) {
        my $address = (
            await $self->call_p(
                $bans, 'address', $asked =~ s/\A \s+ | \s+ \z//grmsx
            )
        );
        my $ban =
          defined $address
          ? ( await $self->call_p( $bans, 'covering', $address ) )
          : undef;
        $page{check} = {
            asked   => $asked,
            address => $address,
            ban     => $ban ? _shown( $bans, $ban ) : undef,
        };
    }

    return %page;
}

# A ban as the page shows it: a single address without its prefix length.
sub _shown ( $bans, $row ) {
    my %ban = %{$row};
    delete $ban{live_total};
    $ban{address_range} = $bans->shown_range( $ban{address_range} );

    return \%ban;
}

# The staff member writing, or undef once the request is answered: a bad
# CSRF token, nobody signed in, no admin_console.manage binding, over the
# admin write limit, or suspended.
async sub _writer ($self) {
    return ( await $self->await_p( $self->authorized_write_user_id ) );
}

sub _client ($self) {
    return GPForum::Web::ClientAddress->of( $self->tx );
}

# The store's answer, or undef when it failed (logged).
async sub _stored ( $self, $call ) {
    my $result;
    try {
        $result = await $self->await_p( $call->( $self->gp_address_bans ) );
    }
    catch ($error) {
        $self->app->log->error("admin address ban write failed: $error");
        return undef;
    };

    return $result;
}

# The store's answer as JSON, or as a flash and the console again.
sub _answer ( $self, $done, $result ) {
    return $self->system_failure if !$result;

    my $status    = _status($result);
    my $succeeded = exists $SUCCESS{$status};
    my $outcome   = $status eq 'ok' ? $done : $status;
    return $self->render(
        json => {
            ok     => $succeeded ? 1 : 0,
            status => $outcome,
            ban_id => $result->{ban_id},
            field  => $result->{field},
        },
        status => _code( $status, $outcome )
    ) if $self->wants_json;

    $self->flash(
        $succeeded
        ? ( success => $self->t( $FLASH{$outcome} ) )
        : ( error => $self->t( _refusal( $status, $result->{field} ) ) )
    );

    return $self->redirect_to($PAGE);
}

# A status the console knows; anything else is invalid.
sub _status ($result) {
    my $status = $result->{status} // 'invalid';

    return exists $SUCCESS{$status} || exists $STATUS{$status}
      ? $status
      : 'invalid';
}

sub _code ( $status, $outcome ) {
    return $STATUS{$status} if exists $STATUS{$status};

    return $outcome eq 'placed' ? $HTTP_CREATED : $HTTP_OK;
}

# What a refusal says: its reason, or for an invalid form the field's.
sub _refusal ( $status, $field ) {
    return $FLASH{$status} if $status ne 'invalid';

    my $name = $field // q{};
    return
      exists $INVALID{$name} ? $INVALID{$name} : 'admin.address_ban_invalid';
}

1;

__END__

=head1 NAME

GPForum::Controller::Admin::AddressBans - Address and range bans in the
admin console.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/admin/address-bans')->to('Admin::AddressBans#show');

=head1 DESCRIPTION

ADR 0146. Staff holding C<admin_console> see the bans, live first, and ask
which ban covers an address; with C<admin_console.manage> they place a ban
on an address or a CIDR range for registration, sign-in or every write,
with a reason and a length, and edit or lift it. Every write takes the CSRF
token, the admin write permission and its rate limit, is refused to a
suspended staff member, and is audited.

=head1 SUBROUTINES/METHODS

=head2 show

Renders the bans; JSON gives C<bans>, C<live_total>, C<client_address> and
C<check> (for C<?check=address>).

=head2 create

Places a ban from C<range>, C<scope>, C<duration>, C<reason> and
C<command_id>.

=head2 update

Changes the ban named in the path: C<scope>, C<reason>, and C<duration>
when one is given.

=head2 lift

Lifts the ban named in the path.

=head1 DIAGNOSTICS

A refusal flashes its reason; JSON clients get C<400> for C<invalid> and
C<too_broad>, C<404> for C<not_found> and C<409> for C<conflict>,
C<duplicate>, C<covers_self> and C<ended>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Controller::Admin::Base>, L<GPForum::Service::Admin::AddressBans>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A refused form comes back empty.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
