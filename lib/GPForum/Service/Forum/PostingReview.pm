# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::PostingReview;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

our $VERSION = '0.001';

# ADR 0134: the kind of post each holdable command writes.
const my %KIND => ( 'thread.create' => 'thread', 'reply.create' => 'reply' );
const my %VISIBILITY => map { $_ => 1 } qw(public members private);

__PACKAGE__->requires(qw(store));
has logger => undef;    # optional: without it nothing is logged

# Holds a new thread or reply the automod screen marked for review. The
# composer's command is what staff will read: the text as the rules left
# it, rendered as a post is. Answers ok with the held entry (status held),
# or failed.
sub hold ( $self, $type, $screen, $command ) {
    return _failed('not a held command') if !exists $KIND{$type};
    my $kind  = $KIND{$type};
    my $input = $screen->{input};
    my $body  = $command->{body} // {};
    my $held;
    try {
        $held = $self->store->hold(
            {
                author_user_id => $input->{author_user_id},
                command_id     => _trim( $input->{command_id} ),
                command_type   => $type,
                kind           => $kind,
                category_id    => $command->{thread}{category_id},
                thread_id      => $kind eq 'reply'
                ? $command->{post}{thread_id}
                : undef,
                title => $kind eq 'thread' ? $command->{thread}{title} : q{},
                body_source        => $body->{body_source},
                body_rendered_safe => $body->{body_rendered_safe},
                visibility         => _visibility( $input->{visibility} ),
                reply_to_post_id   => $input->{reply_to_post_id},
                reason             => $screen->{hold},
                details            => _details( $screen->{verdict} ),
                draft_id           => $input->{draft_id},
                draft_revision     => $input->{draft_revision},
            }
        );
    }
    catch ($error) {
        $self->_log( error => "review hold failed: $error" );
        return _failed('review hold failed');
    };
    return _failed('review hold failed') if !$held->{ok};

    return {
        ok         => 1,
        status     => 'held',
        idempotent => $held->{replayed},
        held       => {
            review_id     => $held->{review_id},
            review_status => $held->{review_status},
            kind          => $kind,
            reason        => $screen->{hold},
        },
    };
}

# What the rules found in the text, as staff read it in the queue.
sub _details ($verdict) {
    return {} if ref $verdict ne 'HASH';

    return {
        flagged    => $verdict->{flagged}  // [],
        replaced   => $verdict->{replaced} // [],
        links      => $verdict->{links},
        link_limit => $verdict->{link_limit},
        link_over  => $verdict->{link_over},
    };
}

sub _visibility ($value) {
    my $visibility = _trim($value);

    return exists $VISIBILITY{$visibility} ? $visibility : undef;
}

sub _trim ($value) {
    my $text = $value // q{};
    $text =~ s/\A\s+|\s+\z//gmsx;

    return $text;
}

sub _failed ($error) {
    return { ok => 0, status => 'failed', error => $error };
}

sub _log ( $self, $level, $message ) {
    return if !$self->logger;
    $self->logger->$level($message);

    return;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::PostingReview - Holds new members' first posts for staff review.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $review = GPForum::Service::Forum::PostingReview->new(
        store => GPForum::Service::Moderation::ReviewStore->new(
            schema => $schema ) );
    my $held = $review->hold( 'reply.create', $screen, $command );

=head1 DESCRIPTION

The posting side of ADR 0134. A new thread or a reply the automod screen
marks for review (a member below the review rule's number of published
posts, or a flagged post when the rule holds those) is kept in the review
queue instead of being written: the text as the rules left it and as the
composer rendered it, where it goes, why it is held and what the rules
found. The author's command id keys the entry.

=head1 SUBROUTINES/METHODS

=head2 hold

Holds the composed command of a screened write; answers C<held> with the
entry, or C<failed>.

=head1 DIAGNOSTICS

A hold that cannot be stored answers C<failed> (C<review hold failed>)
and is logged.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Moderation::ReviewStore>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
