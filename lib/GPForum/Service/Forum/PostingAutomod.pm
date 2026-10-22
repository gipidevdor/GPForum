# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::PostingAutomod;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::Row;
use GPForum::Service::Moderation::Automod;

our $VERSION = '0.001';

# ADR 0133: the fields each screened command writes, and what a flag of
# the command reports: the thread (its title is the thread's), the post or
# the direct message.
const my %FIELDS => (
    'thread.create' => [qw(title body_source)],
    'thread.edit'   => ['title'],
    'reply.create'  => ['body_source'],
    'post.edit'     => ['body_source'],

    # ADR 0139: a direct message is screened as a reply is.
    'message.send' => ['body'],
);
const my %TARGET => (
    'thread.create' => [ thread  => 'thread_id' ],
    'thread.edit'   => [ thread  => 'thread_id' ],
    'reply.create'  => [ post    => 'post_id' ],
    'post.edit'     => [ post    => 'post_id' ],
    'message.send'  => [ message => 'message_id' ],
);

# ADR 0134: the commands whose post can be held for review instead.
const my %HOLDABLE => ( 'thread.create' => 1, 'reply.create' => 1 );
const my $BLOCKED  => 'automod.blocked';
const my $FLAGGED  => 'automod.flagged';
const my $REPLACED => 'automod.replaced';
const my $SCHEMA   => 1;

__PACKAGE__->requires(qw(store));
has automod => sub { return GPForum::Service::Moderation::Automod->new; };
has logger  => undef;    # optional: without it nothing is logged

# Screens a write before it runs. Answers the input to write (a replace
# rule's rewrite), a refusal when a rule blocks it (its decision already
# audited), and whether the write has decisions to record with it.
sub screen ( $self, $type, $input ) {
    my $fields = exists $FIELDS{$type} ? $FIELDS{$type} : undef;
    return { input => $input } if !$fields || _moderates( $input->{viewer} );

    my $rules = $self->store->rules_for( $input->{author_user_id} );
    return { input => $input } if !$rules || _idle($rules);

    my %text =
      map { $_ => $input->{$_} } grep { defined $input->{$_} } @{$fields};
    my $verdict = $self->automod->screen( $rules, \%text );
    if ( $self->automod->refuses($verdict) ) {
        return { refusal => $self->_refuse( $type, $input, $verdict ) };
    }

    my $flags  = $self->automod->flags($verdict);
    my $settle = $flags || @{ $verdict->{replaced} };
    return {
        input   => { %{$input}, %{ $verdict->{fields} } },
        verdict => $verdict,
        settle  => $settle ? 1 : 0,
        hold    => _hold( $type, $rules, $flags ),
    };
}

# Rules that can change nothing: no word, no link rule, no review rule.
sub _idle ($rules) {
    return
         !@{ $rules->{words} // [] }
      && !defined $rules->{link_limit}
      && !$rules->{review_first_posts} ? 1 : 0;
}

# ADR 0134: why a new thread or reply is held for review, or undef. A
# member with fewer published posts than the rule's number is held; so is
# a flagged post when the rule holds flagged posts.
sub _hold ( $type, $rules, $flags ) {
    return undef if !exists $HOLDABLE{$type};
    my $first = $rules->{review_first_posts} // 0;
    return 'first_posts'
      if $first > 0 && ( $rules->{published_posts} // 0 ) < $first;
    return 'flagged' if $flags && $rules->{review_flagged};

    return undef;
}

# Runs the write and records its decisions in one transaction: a write
# replayed from the command log records nothing again, and a failure to
# record undoes the write.
sub settle ( $self, $type, $screen, $write ) {
    my $result;
    try {
        $result = $self->store->in_transaction(
            sub {
                my $written = $write->( $screen->{input} );
                if ( $written->{ok} && !$written->{idempotent} ) {
                    $self->_record( $type, $screen, $written );
                }
                return $written;
            }
        );
    }
    catch ($error) {
        $self->_log( error => "automod record failed: $error" );
        return _failed();
    };

    return $result;
}

sub _refuse ( $self, $type, $input, $verdict ) {
    my %blocked = %{ $verdict->{blocked} };
    my $field   = ( sort keys %blocked )[0] // 'body_source';
    my @phrases = map { @{$_} } @blocked{ sort keys %blocked };
    my $links   = !%blocked;
    try {
        $self->store->record_decisions(
            {
                audits => [
                    $self->_decision(
                        $BLOCKED,                 $type,
                        $input,                   'user',
                        $input->{author_user_id}, $verdict,
                    )
                ]
            }
        );
    }
    catch ($error) {
        $self->_log( error => "automod record failed: $error" );
        return _failed();
    };

    my $message =
      $links
      ? "more than $verdict->{link_limit} links"
      : 'contains a watched word';
    return {
        ok      => 0,
        status  => 'invalid',
        error   => 'automod',
        automod => {
            field   => $field,
            reason  => $links ? 'link_limit' : 'watched_word',
            phrases => \@phrases,
            limit   => $verdict->{link_limit},
            links   => $verdict->{links},
        },
        prepared => {
            ok     => 0,
            errors => { $field => $message },
            values => {
                map  { $_ => $input->{$_} }
                grep { defined $input->{$_} }
                  qw(body_source category_id command_id post_id thread_id
                  title visibility)
            },
        },
    };
}

sub _record ( $self, $type, $screen, $written ) {
    my $verdict = $screen->{verdict};
    my ( $kind, $column ) = @{ $TARGET{$type} };
    my $target_id =
      GPForum::Infrastructure::Row->column( $written->{stored}{$kind},
        $column );
    my $input = $screen->{input};
    my @audits;
    if ( @{ $verdict->{replaced} } ) {
        push @audits,
          $self->_decision( $REPLACED, $type, $input, $kind, $target_id,
            $verdict );
    }

    my $report;
    if ( $self->automod->flags($verdict) ) {
        push @audits,
          $self->_decision( $FLAGGED, $type, $input, $kind, $target_id,
            $verdict );
        my @details;
        if ( @{ $verdict->{flagged} } ) {
            push @details, join q{, },
              map { qq{"$_"} } @{ $verdict->{flagged} };
        }
        if ( $verdict->{link_over} ) {
            push @details, "links $verdict->{links}/$verdict->{link_limit}";
        }
        $report = {
            target_type => $kind,
            target_id   => $target_id,
            reason      => @{ $verdict->{flagged} }
            ? 'automod.watched_word'
            : 'automod.link_limit',
            details => join q{; },
            @details,
        };
    }

    return $self->store->record_decisions(
        { report => $report, audits => \@audits } );
}

# The audit of one decision: the system decides (no actor); the author,
# the command and what matched are its metadata.
sub _decision ( $self, $action, $type, $input, $kind, $target_id, $verdict ) {
    return {
        action   => $action,
        actor_id => undef,
        metadata => {
            author_user_id => $input->{author_user_id},
            command_type   => $type,
            blocked        => $verdict->{blocked},
            flagged        => $verdict->{flagged},
            replaced       => $verdict->{replaced},
            links          => $verdict->{links},
            link_limit     => $verdict->{link_limit},
            link_over      => $verdict->{link_over},
        },
        schema_version => $SCHEMA,
        target_id      => $target_id,
        target_type    => $kind,
    };
}

# Staff who moderate every thread are not screened: they quote what they
# act on, and they write the rules.
sub _moderates ($viewer) {
    return
         blessed $viewer
      && $viewer->can('moderates')
      && $viewer->moderates
      ? 1
      : 0;
}

sub _failed {
    return {
        ok     => 0,
        status => 'failed',
        error  => 'automod record failed',
    };
}

sub _log ( $self, $level, $message ) {
    return if !$self->logger;
    $self->logger->$level($message);

    return;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::PostingAutomod - Screens new threads, replies and edits against the automod rules.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $screen = $automod->screen( 'reply.create', $input );
    return $screen->{refusal} if $screen->{refusal};
    return $automod->settle( 'reply.create', $screen, $write )
      if $screen->{settle};
    return $write->( $screen->{input} );

=head1 DESCRIPTION

The posting side of ADR 0133. Before a new thread, a reply, a post edit or
a thread title edit runs, its text is screened against the watched words
and the link rule. A new thread or reply the review rule of ADR 0134
holds is answered with C<hold> (why) instead of being written. A block refuses the write as invalid (naming the field
and what matched) and audits the decision; a replace rewrites the text
before it is stored; a flag stores the write and puts it in the
moderation queue as a system report, in the write's own transaction, with
the audit of each decision. Staff holding the global moderation binding
are not screened.

=head1 SUBROUTINES/METHODS

=head2 screen

Screens a command's input: answers the input to write, or a refusal, and
whether decisions are to be recorded with the write.

=head2 settle

Runs the write and records its decisions in one transaction.

=head1 DIAGNOSTICS

A failure to record a decision answers C<failed> (C<automod record
failed>) and is logged; the write it belongs to is undone.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Moderation::Automod>,
L<GPForum::Service::Moderation::AutomodStore>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Flooding is left to the posting rate limiter.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
