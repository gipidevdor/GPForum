# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::ViewerResolver;

use Const::Fast;
use JSON::MaybeXS qw(decode_json);
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Forum::Viewer;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

# Only an active account is a member. A pending one has not confirmed its
# e-mail: it cannot sign in (Identity::AuthStore), and confirming makes it
# active, so a session for it is an anomaly and reads what an anonymous
# visitor reads. It used to count as a member, on the premise -- true once,
# no longer -- that verification never moved an account to active.
const my %MEMBER_STATUS => ( active => 1 );

__PACKAGE__->requires('schema');
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

has logger => undef;    # optional: without it nothing is logged

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins('resolve');

# Fails closed: without a readable account -- none, suspended, deleted, or a
# resolution that errors -- the viewer reads what an anonymous reader does,
# keeping only the user id so an author still reaches their own threads.
# Without the function layer it raises: that is a wiring fault, not a
# visitor.
async sub resolve_p ( $self, $user_id, $context = undef ) {

    # No account row can match an id that is not a uuid, so none is read: the
    # viewer is a non-member keeping the id, which reads public content only.
    return GPForum::Service::Forum::Viewer->from($user_id)
      if !GPForum::Infrastructure::Id->is_uuid($user_id);

    my $functions = $self->_functions;
    my $row;
    try {
        $row = await $functions->row_p( 'forum_resolve_viewer',
            { user_id => $user_id }, $context );
    }
    catch ($error) {
        $self->_warn("viewer resolution degraded: $error");
    };
    return $self->viewer_from_row( $user_id, $row );
}

# The viewer an account's row describes -- status, suspended, listed,
# trust_level, moderates and grants, as _viewer_row reads them -- or a
# non-member keeping the id without a row. No statement: a fan-out builds its
# recipients' viewers from the rows it read with them.
sub viewer_from_row ( $self, $user_id, $row ) {
    my $viewer_class = 'GPForum::Service::Forum::Viewer';
    return $viewer_class->new( user_id => $user_id ) if !$row;

    my $member = exists $MEMBER_STATUS{ $row->{status} // q{} }
      && !$row->{suspended} ? 1 : 0;
    my $listed = ref $row->{listed} eq 'ARRAY' ? $row->{listed} : [];
    return $viewer_class->new( listed => $listed, user_id => $user_id )
      if !$member;

    return $viewer_class->new(
        listed      => $listed,
        member      => 1,
        trust_level => $row->{trust_level} // 0,
        moderates   => $row->{moderates} ? 1 : 0,
        user_id     => $user_id,
        %{ $self->grant_scopes( $row->{grants} ) },
    );
}

# The scopes a list of role bindings grants (decoded or as JSON). Public so
# the mapping is tested on its own, without an account in a database.
sub grant_scopes ( $class, $json ) {
    my $grants = ref $json ? $json : decode_json( $json // '[]' );
    my %scopes = ( category_ids => [], global_read => 0, space_ids => [] );

    # Exactly three shapes grant, and every other grants nothing: a global
    # binding (no resource, no space), a space binding (the space), and a
    # category binding (the category). The review of stage 1 found that
    # reading anything with a space as a space-wide grant widened, say, a
    # thread-scoped binding to its whole space.
    for my $grant ( @{$grants} ) {
        my $type = $grant->{resource_type} // q{};
        if (   $type eq 'global'
            && !defined $grant->{resource_id}
            && !defined $grant->{space_id} )
        {
            $scopes{global_read} = 1;
        }
        elsif ( $type eq 'category' && defined $grant->{resource_id} ) {
            push @{ $scopes{category_ids} }, $grant->{resource_id};
        }
        elsif ( $type eq 'space'
            && defined( my $space = $grant->{resource_id}
                  // $grant->{space_id} ) )
        {
            push @{ $scopes{space_ids} }, $space;
        }
    }

    return \%scopes;
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'viewer resolution needs the PostgreSQL function layer' );
}

sub _warn ( $self, $message ) {
    if ( $self->logger ) {
        $self->logger->warn($message);
    }

    return;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::ViewerResolver - Resolve the reader of a request.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $viewer = $resolver->resolve( $session_user_id );

=head1 DESCRIPTION

Turns a session user id into a L<GPForum::Service::Forum::Viewer> with one
query: the account's status, an active suspension, the scopes of its
C<category.read> grants (ADR 0102), and whether it holds the global
C<thread.moderate> binding (the thread page's staff actions), and the
members on its ignore and block list (ADR 0130). The same statement resolves
the account's trust level for rate limits, without a second account lookup.
Only active accounts count as members; pending, suspended and deleted ones do not.

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>). C<schema>, the L<DBIx::Class> schema, is
required: without it C<new> throws L<GPForum::X::Argument>. C<logger> is
optional; without it a degraded resolution is not logged.

=head2 resolve_p

Answers the viewer, read with one call to C<api.forum_resolve_viewer>:
anonymous for no user, and anonymous-equivalent (the user id kept for
authorship) when the account cannot read or the call fails. A promise, with
an optional query context last.

=head2 resolve

The blocking twin: L</resolve_p> run on the blocking call layer (ADR 0177),
answering the viewer instead of a promise.

=head2 viewer_from_row

Takes a user id and the account's row as C<resolve> reads it (C<status>,
C<suspended>, C<listed>, C<trust_level>, C<moderates>, C<grants>), or undef
for an account that is not there. Returns the viewer C<resolve> would, making
no statement.

=head2 grant_scopes

Returns C<global_read>, C<space_ids> and C<category_ids> for a list of
C<category.read> role bindings: a global binding with no resource and no
space, a space binding, and a category binding grant; any other shape grants
nothing.

=head1 DIAGNOSTICS

Logs a warning when resolution fails. Without the PostgreSQL function layer
it raises L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Forum::Viewer>, L<JSON::MaybeXS>, L<GPForum::Base>.

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
