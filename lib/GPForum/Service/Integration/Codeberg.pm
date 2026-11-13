# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::Codeberg;

use Mojo::Base 'GPForum::Service::Integration::Forge', -signatures;
use v5.40;
our $VERSION = '0.001';
has provider_version => sub { return $VERSION; };
has provider_id      => 'codeberg';
has provider_name    => 'Codeberg';
has host             => 'codeberg.org';
has gitlab           => 0;

1;

__END__

=head1 NAME

GPForum::Service::Integration::Codeberg - Recognize Codeberg resources through the reviewed forge adapter.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $provider = GPForum::Service::Integration::Codeberg->new;

=head1 DESCRIPTION

Recognize Codeberg resources through the reviewed forge adapter. No remote requests or untrusted HTML cross the plugin boundary.

=head1 SUBROUTINES/METHODS

Methods and attributes are inherited from the documented base class.

=head1 DIAGNOSTICS

Unsupported URLs return undef.

=head1 CONFIGURATION AND ENVIRONMENT

Core supplies reviewed exact hostnames and plugin activation.

=head1 DEPENDENCIES

Mojo::Base and Mojo::URL.

=head1 INCOMPATIBILITIES

Only the documented URL forms and API v1 are supported.

=head1 BUGS AND LIMITATIONS

URL recognition does not establish remote existence, rights or visibility.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
