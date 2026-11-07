# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::X::RateLimited;

use Mojo::Base 'GPForum::X', -signatures;
use v5.40;
use Const::Fast;
our $VERSION = '0.001';
const my $DEFAULT_RETRY_SECONDS => 60;
has failure_type => 'transport';
has retry_after  => $DEFAULT_RETRY_SECONDS;

1;

__END__

=head1 NAME

GPForum::X::RateLimited - Carry a remote retry delay into the durable outbox.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::X::RateLimited->new;

=head1 DESCRIPTION

Carry a remote retry delay into the durable outbox. Core owns configuration, authorization and presentation.

=head1 SUBROUTINES/METHODS

Methods and attributes are inherited from the documented base class.

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
