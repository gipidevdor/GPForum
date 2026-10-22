# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::ReactionStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::X;

our $VERSION = '0.001';

# The reactions a post may get (ADR 0145), in the order a page shows them.
const my @REACTIONS => qw(heart laugh celebrate think);
const my %REACTION  => map { $_ => 1 } @REACTIONS;

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };

__PACKAGE__->requires(qw(schema));

has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

sub reactions ($class) {
    return [@REACTIONS];
}

sub is_reaction ( $class, $reaction ) {
    return defined $reaction && exists $REACTION{$reaction} ? 1 : 0;
}

# The row a reaction given or taken back is written from: the post, the
# member, the reaction, the time, and the ids of the event the write
# records, drawn here so the command function records what the Perl path
# would.
sub new_reaction_row ( $self, $input ) {
    return {
        correlation_id => $self->id_service->uuid,
        created_at     => $self->clock->now_iso8601,
        event_id       => $self->id_service->uuid,
        outbox_id      => $self->id_service->uuid,
        post_id        => $input->{post_id},
        reaction       => $input->{reaction},
        user_id        => $input->{user_id},
    };
}

sub react ( $self, $input ) {
    return $self->_written( 'community_react_post', $input );
}

sub unreact ( $self, $input ) {
    return $self->_written( 'community_unreact_post', $input );
}

# The reactions on these posts, by post id, then by reaction: how many, and
# whether the viewer gave it. A reaction nobody gave is absent.
sub reactions_for_posts ( $self, $post_ids, $viewer_user_id = undef ) {
    return {} if !@{$post_ids};
    my $rows = $self->_functions->rows(
        @{ $self->reactions_call( $post_ids, $viewer_user_id ) } );
    my %by_post;
    for my $row ( @{$rows} ) {
        $by_post{ $row->{post_id} }{ $row->{reaction} } = {
            count   => $row->{reaction_count},
            reacted => $row->{reacted} ? 1 : 0,
        };
    }

    return \%by_post;
}

# The call reactions_for_posts makes, its function's name and its values:
# the thread page's one read (GPForum::Service::Forum::ThreadPageReads)
# answers this call with its other parts.
sub reactions_call ( $class, $post_ids, $viewer_user_id = undef ) {
    return [
        'community_post_reactions',
        {
            post_ids       => $post_ids,
            viewer_user_id => _nullable($viewer_user_id),
        }
    ];
}

sub _written ( $self, $name, $input ) {
    my $row = $self->_functions->row( $name,
        { row => $self->new_reaction_row($input) } );
    return $row ? $row->{result} : undef;
}

# Reactions exist only as api.* functions (ADR 0126).
sub _functions ($self) {
    return $self->functions // GPForum::X::Argument->throw(
        message => 'reactions need the SQL function layer' );
}

sub _nullable ($value) {
    return defined $value && length $value ? $value : undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Community::ReactionStore - A member's reactions on posts.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Community::ReactionStore->new( schema => $schema );
    $store->react( { post_id => $post_id, reaction => 'heart', user_id => $user_id } );
    $store->reactions_for_posts( \@post_ids, $viewer_user_id );

=head1 DESCRIPTION

ADR 0145: beside the like (ADR 0129), a member may give a visible post one
of four reactions (heart, laugh, celebrate, think), each once, never on
their own post, and take it back. Each is one row in C<post_reactions>,
counted when a page is read (C<api.community_post_reactions_v1>); giving
and taking back go through C<api.community_react_post_v1> and
C<api.community_unreact_post_v1>, or the commands around them from
L<GPForum::Service::Community::Workflow>.

=head1 SUBROUTINES/METHODS

=head2 reactions

The four reactions, in the order a page shows them.

=head2 is_reaction

True for one of the four.

=head2 new_reaction_row

The row a reaction write is made from, with the event ids drawn.

=head2 react

Gives a reaction; answers the function's result.

=head2 unreact

Takes a reaction back; answers the function's result.

=head2 reactions_for_posts

The reactions on the given posts, by post id then reaction:
C<{ count, reacted }>.

=head2 reactions_call

The call C<reactions_for_posts> makes: the function's name and values.

=head1 DIAGNOSTICS

Without the SQL function layer every call throws L<GPForum::X::Argument>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>, L<GPForum::Service::Clock>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The reaction set is fixed in the schema and here; adding one is a new
migration and a new decision.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
