# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::CookieSessionController;

use Mojo::Base -base;
use v5.40;

our $VERSION = '0.001';

has data => sub { return {}; };

# The cookie's expiry, kept in the session as Mojolicious keeps it: a key
# of the hash, which Mojolicious::Sessions::store reads back as the expiry
# of the cookie it writes.
sub expired {
    my ($self) = @_;

    return $self->data->{expires};
}

sub session {
    my ( $self, @args ) = @_;

    if ( @args <= 1 ) {
        return $self->_session_read( $args[0] );
    }

    return $self->_session_write(@args);
}

sub _session_read {
    my ( $self, $name ) = @_;

    if ( !defined $name ) {
        return $self->data;
    }

    return $self->data->{$name};
}

sub _session_write {
    my ( $self, @args ) = @_;

    return $self->_merge_session(@args);
}

sub _merge_session {
    my ( $self, %values ) = @_;

    for my $key ( keys %values ) {
        $self->data->{$key} = $values{$key};
    }

    return;
}

1;

__END__

=head1 NAME

GPForum::Test::CookieSessionController - Cookie-session fake.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $controller = GPForum::Test::CookieSessionController->new(
        data => { user_id => 'user-1', session_id => 'sess-1' },
    );

=head1 DESCRIPTION

Test double for Mojolicious C<session> get/set/expire used by
C<Web::CookieSession>.

=head1 SUBROUTINES/METHODS

=head2 session

Reads a key, returns the session hash, merges values, or records expiry.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

None.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Does not emulate signed cookie serialization.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
