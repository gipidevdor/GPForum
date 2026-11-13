# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Worker::Handler::IntegrationNetwork;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use GPForum::X::Argument;
our $VERSION = '0.001';
__PACKAGE__->requires(qw(announcements feeds));

sub supports ( $self, $event ) {
    return ( $event->{event_type} // q{} ) =~
      /\A integration[.](?:discord|feed)[.]requested \z/msx ? 1 : 0;
}

sub handle ( $self, $event ) {
    if ( ( $event->{schema_version} // 1 ) != 1 ) {
        GPForum::X::Argument->throw(
            message => 'unsupported integration event schema' );
    }
    my $input = $event->{domain_payload} // $event->{payload} // {};
    return $self->announcements->deliver( $input->{announcement_id} )
      if $event->{event_type} eq 'integration.discord.requested';
    return $self->feeds->poll( $input->{source_url} );
}

1;

__END__

=head1 NAME

GPForum::Worker::Handler::IntegrationNetwork - Execute integration network requests only in outbox workers.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Worker::Handler::IntegrationNetwork->new;

=head1 DESCRIPTION

Execute integration network requests only in outbox workers. Core owns configuration, authorization and presentation.

=head1 SUBROUTINES/METHODS

=head2 supports

Selects only the explicit versioned network-request events.

=head2 handle

Dispatches the requested delivery or authorized syndication poll.

=head1 DIAGNOSTICS

Invalid configuration and transport failures raise typed exceptions.

=head1 CONFIGURATION AND ENVIRONMENT

The composition layer supplies validated settings and dependencies.

=head1 DEPENDENCIES

The Good Phorum runtime and the modules named above.

=head1 INCOMPATIBILITIES

Network capabilities are independent of the frozen local Plugin API v1.

=head1 BUGS AND LIMITATIONS

External operations depend on the configured provider and its availability.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
