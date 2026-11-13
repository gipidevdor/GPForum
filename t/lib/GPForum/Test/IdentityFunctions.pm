# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::IdentityFunctions;

use Carp qw(croak);
use Mojo::Base 'GPForum::Test::LoggedCalls', -signatures;
use v5.40;

use GPForum::Service::Identity::Workflow;

our $VERSION = '0.001';

has sink => undef;    # the store double the registration is written on

# Installs, as an application's gp_identity_workflow, the workflow on its
# collaborators with these functions as its call layer, each registration
# written on the application's identity store.
sub install ( $class, $app ) {
    my $functions = $class->new;
    $app->helper(
        gp_identity_workflow => sub ($controller) {
            my $store = $controller->gp_identity_store;
            $functions->sink($store);
            return GPForum::Service::Identity::Workflow->new(
                command_idempotency => $controller->gp_command_idempotency,
                functions           => $functions,
                logger              => $controller->app->log,
                registration        => $controller->gp_registration,
                store               => $store,
            );
        }
    );

    return $functions;
}

# api.identity_register_command: the command log kept here, and the
# account written on the sink as the function writes it -- refused when
# the sink holds the username or the address, else stored and sent its
# verification mail.
sub rows ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, $values ];
    croak "$name is not the registration command"
      if $name ne 'identity_register_command';
    my $log = $values->{log};

    return [
        $self->logged(
            $log->{idempotency_key}, $log->{request_hash},
            $values->{answer},       sub { return $self->_register($values) }
        )
    ];
}

sub _register ( $self, $values ) {
    my $user    = $values->{user};
    my $created = $self->sink->create_registration(
        { user => $user, credential => $values->{credential} } );
    return $values->{refused} if !$created->{ok};
    $self->sink->request_email_verification( { user_id => $user->{id} } );

    return ( $values->{accepted}, { stored_user => $user } );
}

1;

__END__

=head1 NAME

GPForum::Test::IdentityFunctions - The registration command function over an in-memory store.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Test::IdentityStore->new;
    my $workflow = GPForum::Service::Identity::Workflow->new(
        command_idempotency => GPForum::Test::CommandIdempotency->new,
        functions    => GPForum::Test::IdentityFunctions->new( sink => $store ),
        registration => $store,
        store        => $store,
    );

    GPForum::Test::IdentityFunctions->install($app);

=head1 DESCRIPTION

Stands in for C<api.identity_register_command>, the one call a
registration is (ADR 0126), so L<GPForum::Service::Identity::Workflow>'s
own Perl runs as it runs on PostgreSQL. The command log is kept in memory
(L<GPForum::Test::LoggedCalls>): a command id seen before is replayed, and
one sent with another request is a conflict. The account is handed to the
C<sink>'s C<create_registration>, and on success to its
C<request_email_verification>, as the function writes both.

=head1 SUBROUTINES/METHODS

=head2 install

Class method taking an application: installs a C<gp_identity_workflow> on
the application's collaborators with a new layer of these functions,
writing on its C<gp_identity_store>, and answers that layer.

=head2 sink

The store double each registration is written on.

=head2 rows

Takes a function's name and values; answers the registration command's
row: its C<outcome>, its C<response> and, when it stored one, the
C<stored_user>.

=head1 DIAGNOSTICS

Any other function croaks naming it.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Test::LoggedCalls>, L<GPForum::Service::Identity::Workflow>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The duplicate checks are the sink's to make.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
