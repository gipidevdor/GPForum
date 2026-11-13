# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::ServiceManager;
use Mojo::Base 'GPForum::OS::ServiceManager', -signatures;
use v5.40;
use English qw(-no_match_vars);
our $VERSION = '0.001';
has runs             => 0;
has work             => undef;
has environment_file => undef;
has inherited_umask  => undef;

sub run ($self) {
    $self->runs( $self->runs + 1 );
    $self->inherited_umask(umask);
    $self->environment_file( $ENV{GPFORUM_ENV_FILE} );
    if ( my $work = $self->work ) { $work->(); }
    return;
}
1;
