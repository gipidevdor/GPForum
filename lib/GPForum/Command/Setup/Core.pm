# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Command::Setup::Core;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use Mojo::Util qw(decode encode trim);
use GPForum::Command::Support::ServiceEnvironment;
use GPForum::X::Io;

our $VERSION = '0.001';

const my $STAT_UID => 4;
const my $STAT_GID => 5;
const my %PLACEHOLDER => map { $_ => 1 }
  qw(GPFORUM_PUBLIC_BASE_URL GPFORUM_MAIL_FROM);

sub said_text ( $self, $key, $parameters = {} ) {
    return $self->catalog->text( $key, $parameters );
}

sub say_text ( $self, $text ) {
    print { $self->output } encode( 'UTF-8', $self->_as_read($text) . "\n" )
      or GPForum::X::Io->throw( message => 'failed to write the setup report' );

    return;
}

sub complain ( $self, $text ) {
    print {*STDERR} encode( 'UTF-8', "$text\n" )
      or GPForum::X::Io->throw( message => 'failed to write the setup report' );

    return;
}

sub ask_line ( $self, $line ) {
    print { $self->prompt } encode( 'UTF-8', "$line\n" )
      or GPForum::X::Io->throw( message => 'failed to write the question' );

    return;
}

# A gpforum command offered reads the file this run wrote, when it is not
# the host's own.
sub _as_read ( $self, $text ) {
    return GPForum::Command::Support::ServiceEnvironment->as_read($text);
}

sub is_root ($self) {
    return $self->effective_uid == 0 ? 1 : 0;
}

sub sudo_command ($self) {
    return $self->is_root ? 'sudo ' : q{};
}

# Text as setup keeps it: characters, from the UTF-8 the file, the command
# line and standard input carry, written back as UTF-8, which the service
# reads it as. Bytes typed at the terminal and written unchanged left a
# latin-1 byte in the file the service then could not read.
sub decode_text ( $, $bytes ) {
    return decode( 'UTF-8', $bytes ) // $bytes;
}

# A value the operator gave the file: set, and not one of the template's
# placeholder addresses left as copied, which the service would refuse.
sub stated ( $self, $state, $name ) {
    return undef if !$state->{exists};
    my $value = $state->{values}{$name};
    return undef if !defined $value || !length $value;
    return undef
      if exists $PLACEHOLDER{$name}
      && $value eq ( $state->{template}{$name} // q{} );

    return $value;
}

# Who the next steps run as, each reading the file setup wrote: on a
# deployed host the services' account, once it exists and the file is its
# group's to read; otherwise whoever ran setup, whose file it is -- through
# sudo when that was root. sudo -u gpforum, said to an operator with no
# such account or with a file only they may read, was a command that failed
# as printed.
sub runner ( $self, $state ) {
    return q{} if !$state->{deployed};

    my ( $uid, $gid ) = $self->account->ids;
    my @stat = stat $state->{file};
    if (   defined $uid
        && @stat
        && ( $stat[$STAT_UID] == $uid || $stat[$STAT_GID] == $gid ) )
    {
        return 'sudo -u ' . $self->account->name . q{ };
    }

    return $self->sudo_command;
}

1;

__END__

=head1 NAME

GPForum::Command::Setup::Core - What every part of setup uses to talk and to ask the host.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Part of GPForum::Command::Setup; callers use that class.

=head1 DESCRIPTION

Saying a catalogue sentence, writing a line to the operator, asking a question, reading text, and asking whether the process is root or must use sudo.

GPForum::Command::Setup inherits it, so the object a caller builds has every method; this
file holds one part of that class so each part can be read by itself.

=head1 SUBROUTINES/METHODS

=head2 said_text

A step the parts of GPForum::Command::Setup share.

=head2 say_text

A step the parts of GPForum::Command::Setup share.

=head2 complain

A step the parts of GPForum::Command::Setup share.

=head2 ask_line

A step the parts of GPForum::Command::Setup share.

=head2 is_root

A step the parts of GPForum::Command::Setup share.

=head2 sudo_command

A step the parts of GPForum::Command::Setup share.

=head2 decode_text

A step the parts of GPForum::Command::Setup share.

=head2 stated

A step the parts of GPForum::Command::Setup share.

=head2 runner

A step the parts of GPForum::Command::Setup share.

=head1 DIAGNOSTICS

As GPForum::Command::Setup.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

As GPForum::Command::Setup.

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
