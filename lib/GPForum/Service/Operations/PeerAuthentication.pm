# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Operations::PeerAuthentication;

use Const::Fast;
use English    qw(-no_match_vars);
use List::Util qw(uniq);
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::OS;

our $VERSION = '0.001';

# What PostgreSQL needs to let GPForum in over its socket with peer
# authentication (ADR 0127, ADR 0137). Peer reads the connecting process's
# operating-system account from the kernel and, with no map, admits it only
# as the role of the same name: Debian's `local all all peer` let the
# service's gpforum in as gpforum and nothing else, so the web service as
# gpforum_runtime and the operator's migrate as gpforum were both refused.
# One pg_hba.conf line, above the distribution's own local lines, sends the
# forum's roles on the forum's database through the gpforum map, and the
# map says which account may be which role.

# The map's name, the service's account and the forum's two roles, as setup
# and the runtime role guide name them.
const my $MAP          => 'gpforum';
const my $ACCOUNT      => 'gpforum';
const my $OWNER        => 'gpforum';
const my $RUNTIME_ROLE => 'gpforum_runtime';

# An identifier pg_hba.conf and pg_ident.conf read as it is; any other is
# double-quoted, as both files take it.
const my $PLAIN => qr/\A [[:alpha:]_] [[:alnum:]_.-]* \z/msx;

has os       => sub { return GPForum::OS->detect; };
has database => 'gpforum';
has account  => $ACCOUNT;
has owner    => $OWNER;
has runtime  => $RUNTIME_ROLE;

# The operator's own login, which runs migrate, api-role and the backups
# with the operator environment file: who typed sudo, or who runs this. Root
# and the service's account have no line of their own.
has operator => sub {
    my $login = $ENV{SUDO_USER} // getpwuid $REAL_USER_ID;
    return undef if !defined $login || $login eq 'root';

    return $login;
};

# The pg_hba.conf line: local connections to the forum's database, as the
# forum's roles, by peer through the map.
sub hba_lines ($self) {
    my $roles = join q{,}, map { _quoted($_) } $self->_roles;

    return [
        _fields( 'local', _quoted( $self->database ), $roles, "peer map=$MAP" )
    ];
}

# The pg_ident.conf lines: the service's account as both roles, the
# operator's login as the owner that migrates.
sub ident_lines ($self) {
    my @pairs    = map { [ $self->account, $_ ] } $self->_roles;
    my $operator = $self->operator;
    if ( defined $operator && $operator ne $self->account ) {
        push @pairs, [ $operator, $self->owner ];
    }

    return [
        map {
            _fields( $MAP, map { _quoted($_) } @{$_} )
        } @pairs
    ];
}

# The owner and the runtime role, once each.
sub _roles ($self) {
    return uniq $self->owner, $self->runtime;
}

# A line of either file: its fields, three spaces apart.
sub _fields (@fields) {
    return join q{   }, @fields;
}

# The command that makes PostgreSQL read the two files again.
sub reload_command ($self) {
    return $self->os->postgresql_psql . q{ -c 'SELECT pg_reload_conf()'};
}

# Every line, as setup prints them and doctor's note repeats them: what to
# add to each file and the reload, as [ file, lines ] pairs then the
# command.
sub plan ($self) {
    return {
        hba    => $self->hba_lines,
        ident  => $self->ident_lines,
        reload => $self->reload_command,
    };
}

# Whether an error is PostgreSQL refusing a role to this account's peer
# identity.
sub is_refusal ( $class, $text ) {
    return ( $text // q{} ) =~
      /(?: Peer [ ] authentication [ ] failed | autenticazione [ ] peer )/msxi
      ? 1
      : 0;
}

sub _quoted ($name) {
    return $name =~ $PLAIN ? $name : q{"} . ( $name =~ s/"/""/grmsx ) . q{"};
}

1;

__END__

=head1 NAME

GPForum::Service::Operations::PeerAuthentication - The pg_hba.conf and
pg_ident.conf lines that let the forum's accounts in over the socket.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $peer = GPForum::Service::Operations::PeerAuthentication->new(
        database => 'gpforum' );
    say for @{ $peer->hba_lines };      # local gpforum gpforum,gpforum_runtime peer map=gpforum
    say for @{ $peer->ident_lines };    # gpforum gpforum gpforum ...

=head1 DESCRIPTION

PostgreSQL's peer authentication admits an operating-system account only as
the role of its own name unless a map says otherwise. The web service runs
as C<gpforum> and connects as C<gpforum_runtime> (ADR 0127); the operator
migrates as the C<gpforum> owner from their own login. This module writes
the C<gpforum> map that allows exactly that, and the C<pg_hba.conf> line
that sends the forum's roles on its database through it, for C<gpforum
setup> to print and C<gpforum doctor> to repeat when a connection is
refused (ADR 0137).

=head1 SUBROUTINES/METHODS

=head2 hba_lines

The C<pg_hba.conf> line, in an array reference: C<local>, the database, the
owner and runtime roles, C<peer map=gpforum>. It goes above the
distribution's own C<local> lines, which PostgreSQL would match first.

=head2 ident_lines

The C<pg_ident.conf> lines, in an array reference: the service's account as
the owner and as the runtime role, and the operator's login as the owner.

=head2 reload_command

The command that makes PostgreSQL read both files again.

=head2 plan

C<< { hba, ident, reload } >>: the three above.

=head2 is_refusal

Class method. Whether an error's text is PostgreSQL refusing peer
authentication, in English or Italian.

=head2 os

The L<GPForum::OS> profile whose C<psql> the reload runs; this host's.

=head2 database

The forum's database; C<gpforum>.

=head2 account

The service's operating-system account; C<gpforum>.

=head2 owner

The role that owns the schema and runs the migrations; C<gpforum>.

=head2 runtime

The application's role (ADR 0127); C<gpforum_runtime>.

=head2 operator

The operator's login: C<SUDO_USER>, else the real user's; undef for root.

=head1 DIAGNOSTICS

None: it only writes text.

=head1 CONFIGURATION AND ENVIRONMENT

Reads C<SUDO_USER>.

=head1 DEPENDENCIES

L<GPForum::OS>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

It does not read or change the server's files: an operator adds the lines,
which PostgreSQL's files are theirs to keep.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
