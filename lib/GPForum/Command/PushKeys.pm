# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Command::PushKeys;

use Mojo::Base -base, -signatures;
use v5.40;
use Carp         qw(croak);
use Getopt::Long qw(GetOptionsFromArray);
use Mojo::JSON   qw(encode_json);
use GPForum::Command::Usage;
use GPForum::Service::Notification::Push::Keyring;

our $VERSION = '0.001';
has output => sub { return \*STDOUT; };

sub usage_text {
    return "Usage: gpforum push-keys [--directory PATH] [--rotate]\n";
}

sub run ( $self, @arguments ) {
    if ( GPForum::Command::Usage->wants_help(@arguments) ) {
        print { $self->output } usage_text() or croak 'cannot print Push usage';
        return 0;
    }
    my ( $rotate, $directory ) = ( 0, 'var/keys/web-push' );
    return GPForum::Command::Usage->error( undef, usage_text() )
      if !GetOptionsFromArray(
        \@arguments,
        'directory=s' => \$directory,
        'rotate'      => \$rotate
      ) || @arguments;
    try {
        my $result = GPForum::Service::Notification::Push::Keyring->new(
            directory => $directory )->generate($rotate);
        print { $self->output } encode_json($result), "\n"
          or croak 'cannot print Push result';
    }
    catch ($error) { return GPForum::Command::Usage->failure($error); };
    return 0;
}

1;
