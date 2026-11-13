# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::DirectProxy;

use Mojo::Base 'Mojo::UserAgent::Proxy', -signatures;
use v5.40;
our $VERSION = '0.001';
sub prepare ( $self, $transaction ) { return; }

1;

__END__

=head1 NAME

GPForum::Service::Integration::DirectProxy - Keep pinned external requests independent of process proxy settings.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Integration::DirectProxy->new;

=head1 DESCRIPTION

Keep pinned external requests independent of process proxy settings. Core owns configuration, authorization and presentation.

=head1 SUBROUTINES/METHODS

=head2 prepare

Leaves the transaction on its validated direct HTTPS route; no proxy detection or credentials are applied.

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
