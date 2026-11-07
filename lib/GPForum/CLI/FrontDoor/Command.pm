# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::CLI::FrontDoor::Command;

use Mojo::Base 'Mojolicious::Command', -signatures;
use v5.40;

use GPForum::Command::Usage;

our $VERSION = '0.001';

# Adapters keep the command factory and its options explicit. Help and exit
# handling are shared; command names still come from the lowercase modules.
has usage => sub ($self) { return $self->command->usage_text; };

sub run ( $self, @arguments ) {
    return GPForum::Command::Usage->front_door(
        $self->command->run(@arguments) );
}

1;

__END__

=head1 NAME

GPForum::CLI::FrontDoor::Command - Shared help and execution for CLI adapters.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
    use v5.40;
    use GPForum::Command::SearchRebuild;

    has description => 'Rebuild the search index';
    sub command ($self) { return GPForum::Command::SearchRebuild->new; }

=head1 DESCRIPTION

Each adapter declares its description and a C<command> factory returning a
configured command. The shared adapter delegates help and arguments, preserving
the command's exit status through C<Usage::front_door>. Adapters may override
C<usage> when help must not construct application-dependent collaborators.

=head1 SUBROUTINES/METHODS

=head2 run

Constructs the command, forwards the arguments unchanged and handles its exit
status. Command-specific options and application wiring stay in the factory.

=head1 DIAGNOSTICS

Preserves the command's failure and usage-error behavior.

=head1 CONFIGURATION AND ENVIRONMENT

None. Configuration belongs to the underlying command.

=head1 DEPENDENCIES

L<Mojolicious::Command>, L<GPForum::Command::Usage>.

=head1 INCOMPATIBILITIES

None.

=head1 BUGS AND LIMITATIONS

Subclasses must provide C<command> and a description.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause license.

=cut
