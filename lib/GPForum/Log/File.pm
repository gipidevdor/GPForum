# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Log::File;
use Mojo::Base 'Mojo::Log', -signatures;
use v5.40;
use Carp    qw(carp);
use English qw(-no_match_vars);
use Mojo::File;
our $VERSION = '0.001';
has reopen_requested => 0;
has owner_pid        => sub { return $PROCESS_ID; };

sub new ( $class, @arguments ) {
    my $self = $class->SUPER::new(@arguments);
    $self->owner_pid($PROCESS_ID);
    return $self;
}

# A signal only sets the flag. Reopen before the next append, outside the
# logger's write lock; replace the handle only once opening succeeded.
sub append ( $self, $message ) {
    if ( $self->reopen_requested || $self->owner_pid != $PROCESS_ID ) {
        $self->reopen_requested(0);
        $self->owner_pid($PROCESS_ID);
        try { $self->handle( Mojo::File->new( $self->path )->open('>>') ); }
        catch ($error) { carp "cannot reopen application log: $error"; };
    }
    return $self->SUPER::append($message);
}

1;
