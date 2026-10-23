# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::ThreadTransfers;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use Mojo::URL;

our $VERSION = '0.001';

__PACKAGE__->requires('schema');
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

sub history ( $self, $actor ) {
    my $row = $self->functions->row( 'moderation_thread_transfers',
        { actor => $actor } );
    return $row ? $row->{result} : { status => 'forbidden' };
}

sub change ( $self, $input ) {
    return { status => 'invalid' }
      if !GPForum::Infrastructure::Id->is_uuid( $input->{command} );
    my $source  = _thread_id( $input->{source} );
    my $target  = _thread_id( $input->{target} );
    my @numbers = split /[\s,]+/msx, $input->{post_numbers} // q{};
    my @invalid = grep { !/\A[1-9][[:digit:]]{0,8}\z/msx } @numbers;
    return { status => 'invalid' } if !$source || @invalid;
    return { status => 'invalid' }
      if ( $input->{operation} // q{} ) ne 'split' && !$target;
    my $row = $self->functions->row(
        'moderation_thread_transfer',
        {
            actor        => $input->{actor},
            command      => $input->{command},
            source_id    => $source,
            target_id    => $target,
            operation    => $input->{operation},
            post_numbers => \@numbers,
            title        => $input->{title},
            reason       => $input->{reason},
        }
    );
    return $row ? $row->{result} : { status => 'invalid' };
}

sub undo ( $self, $input ) {
    return { status => 'invalid' }
      if !GPForum::Infrastructure::Id->is_uuid( $input->{command} );
    my $row =
      $self->functions->row( 'moderation_thread_transfer_undo', $input );
    return $row ? $row->{result} : { status => 'invalid' };
}

sub redirect ( $self, $actor, $thread_id ) {
    return undef if !$self->functions;
    my $row = $self->functions->row( 'forum_thread_redirect',
        { actor => $actor, thread_id => $thread_id } );
    return $row ? $row->{target_id} : undef;
}

sub _thread_id ($value) {
    return undef  if !defined $value;
    return $value if GPForum::Infrastructure::Id->is_uuid($value);
    my $path = Mojo::URL->new($value)->path->to_string;
    my ($id) = $path =~ m{\A/t/([^/]+)(?:/[^/]+)?\z}msx;
    return GPForum::Infrastructure::Id->is_uuid($id) ? $id : undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Moderation::ThreadTransfers - Bounded, reversible thread organization.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $transfers->history($staff_id);

=head1 DESCRIPTION

PostgreSQL functions perform transfers, recounts, audit and outbox writes in
one transaction. Source and target must share category and visibility. Private
threads/posts and polls are refused. One command moves at most 1000 posts.

=head1 SUBROUTINES/METHODS

=head2 history

The hundred most recent transfers for authorized staff.

=head2 change

Move numbered posts, split them into a thread, or merge an entire thread.

=head2 undo

Restores original placement when subsequent work permits safe reversal.

=head2 redirect

A merged thread's readable destination, otherwise undef.

=head1 DIAGNOSTICS

A conflict leaves all content untouched; database failures propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>, L<Mojo::URL>.

=head1 INCOMPATIBILITIES

Requires migration 1028.

=head1 BUGS AND LIMITATIONS

Unrelated categories and private discussions require a separate audience-change workflow.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. BSD-3-Clause.

=cut
