# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Service::Forum::PostingNative;

use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;
use Const::Fast;
use JSON::MaybeXS;
use GPForum::Infrastructure::AsyncWork;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::PgStorage;
use GPForum::Infrastructure::Text qw(trimmed);
use GPForum::Log;
use Scalar::Util qw(refaddr);
use English      qw(-no_match_vars);

our $VERSION = '0.001';
const my %METHOD => (
    create_thread  => 'thread.create',
    create_reply   => 'reply.create',
    edit_thread    => 'thread.edit',
    move_thread    => 'thread.move',
    delete_thread  => 'thread.delete',
    restore_thread => 'thread.restore',
    edit_post      => 'post.edit',
    delete_post    => 'post.delete',
    restore_post   => 'post.restore',
);
const my %BODY_PREPARATION => map { $_ => 1 }
  qw(thread.create reply.create post.edit);
const my %SCREENED => map { $_ => 1 }
  qw(thread.create reply.create thread.edit post.edit);
__PACKAGE__->requires('workflow');

# The call layer of a transaction the caller holds -- the review store's,
# when staff approve a held post -- which the reads and the write join.
has scope => undef;    # optional: without it the pooled connections serve
my $JSON = JSON::MaybeXS->new( utf8 => 0 );

async sub call_p ( $self, $method, $arguments, $context, $cancelled ) {
    my $workflow = $self->workflow;
    my $type     = exists $METHOD{$method} ? $METHOD{$method} : undef;

    # The in-memory doubles hold no connection: they answer in the worker.
    return $workflow->$method( @{$arguments} )
      if !$type
      || @{$arguments} != 1
      || !$workflow->functions
      || !$self->_same_schema;
    return await $self->_native_p( $method, $type, $arguments->[0], $context,
        $cancelled );
}

# A held post staff approved, published as its author's command: neither
# screened nor held again, its reads and its write on the scope when one is
# given.
async sub publish_p ( $self, $type, $input, $context, $cancelled = undef ) {
    my $workflow    = $self->workflow;
    my $log_context = GPForum::Log->request_context;
    my %answers;
    my $prepare = sub {
        return $self->_plan_data( 'publish_reviewed', [ $type, $input ],
            \%answers );
    };
    return GPForum::Log->in_context( $log_context, $prepare )
      if !_has_command_id($input);
    try { await $self->_context_p( $type, $input, \%answers, $context ); }
    catch ($error) {
        return GPForum::Log->in_context( $log_context,
            sub { return $workflow->_command_log_failure($error); } );
    };
    my $plan = await GPForum::Log->in_context(
        $log_context,
        sub {
            return GPForum::Infrastructure::AsyncWork->shared->cpu_p( $prepare,
                $cancelled, 1 );
        }
    );
    return $plan if !$plan->{native_kind};

    return await $self->written_p( $plan, undef, $context, $log_context );
}

async sub _native_p ( $self, $method, $type, $input, $context, $cancelled ) {
    my $workflow    = $self->workflow;
    my $log_context = GPForum::Log->request_context;
    my %answers;
    my $screen;
    try {
        $screen = await $self->_screen_p( $type, $input, $context );
    }
    catch ($error) {
        return GPForum::Log->in_context( $log_context,
            sub { return $workflow->_command_log_failure($error); } );
    };
    return $screen->{refusal} if $screen && $screen->{refusal};
    my $prepare = sub {
        return $self->_plan_data( $method, [$input], \%answers, $screen );
    };

    # Without a command id the workflow answers before it reads or composes
    # anything: that answer carries the input as given, viewer and all.
    return GPForum::Log->in_context( $log_context, $prepare )
      if !_has_command_id($input);
    try { await $self->_context_p( $type, $input, \%answers, $context ); }
    catch ($error) {
        return GPForum::Log->in_context( $log_context,
            sub { return $workflow->_command_log_failure($error); } );
    };
    my $plan = exists $BODY_PREPARATION{$type}
      ? await GPForum::Log->in_context(
        $log_context,
        sub {
            return GPForum::Infrastructure::AsyncWork->shared->cpu_p( $prepare,
                $cancelled, 1 );
        }
      )
      : GPForum::Log->in_context( $log_context, $prepare );
    return $plan if !$plan->{native_kind};

    # The plan comes back as plain data; the screen it was made with is here.
    if ( $plan->{settle} ) { $plan->{settle} = $screen; }
    $plan->{screen} = $screen;
    return await $self->_hold_p( $plan, $context )
      if $plan->{native_kind} eq 'hold';
    return await $self->_execute_p( $plan, $context, $log_context );
}

sub _has_command_id ($input) {
    return length( trimmed( $input->{command_id} ) )
      || length( trimmed( $input->{idempotency_key} ) ) ? 1 : 0;
}

sub _same_schema ($self) {
    my $workflow = $self->workflow;
    my $schema   = $workflow->functions->schema;
    my @readers  = (
        $workflow->category_reader,
        $workflow->thread_detail_reader,
        $workflow->thread_store,
    );
    if ( $workflow->automod ) { push @readers, $workflow->automod->store; }
    for my $reader (@readers) {
        return 0 if !$reader->can('functions') || !$reader->functions;
        return 0 if refaddr( $reader->functions->schema ) != refaddr($schema);
    }
    return 1;
}

sub _plan_data ( $self, $method, $arguments, $answers, $screen = undef ) {
    my $workflow = $self->workflow;

    # This scope never yields, in either process. Unexpected SQL fails closed.
    local $GPForum::Infrastructure::PgStorage::HTTP_PID = $PROCESS_ID;
    local $workflow->{native_plan}                      = 1;             ## no critic (Variables::ProhibitLocalVars) -- synchronous data-only preparation scope
    local $workflow->{native_screen}                    = $screen;       ## no critic (Variables::ProhibitLocalVars) -- the screen made on the pooled connections, for this preparation only
    return GPForum::Infrastructure::SqlFunction->answering( $answers,
        sub { return $workflow->$method( @{$arguments} ); } );
}

# The automod screen of a screened command, made on the pooled connections:
# the author's rules, and a refusal audited. undef when nothing screens it.
async sub _screen_p ( $self, $type, $input, $context ) {
    my $automod = $self->workflow->automod;
    return undef if !$automod || !exists $SCREENED{$type};
    return await $automod->screen_p( $type, $input, $context );
}

async sub _context_p ( $self, $type, $input, $answers, $context ) {
    if ( $type =~ /\Apost[.]/msx ) {
        if ( defined $input->{post_id} && length $input->{post_id} ) {
            await $self->_read_p( 'forum_post_context',
                { post_id => $input->{post_id} },
                $answers, $context );
        }
    }
    elsif ( $type ne 'thread.create' ) {
        my $call = $self->workflow->thread_detail_reader->thread_row_call(
            $input->{thread_id} );
        await $self->_read_p( @{$call}, $answers, $context );
    }
    if ( $type eq 'thread.create' || $type eq 'thread.move' ) {
        my $category = trimmed( $input->{category_id} );
        if ( length $category ) {
            await $self->_read_p( 'forum_find_category',
                { category_id => $category },
                $answers, $context );
        }
    }
    return;
}

async sub _read_p ( $self, $name, $values, $answers, $context ) {
    my $functions = $self->scope // $self->workflow->functions;
    my $rows      = await $functions->rows_p( $name, $values, $context );
    my $entry     = $functions->catalogue->function($name);
    my @raw;
    for my $row ( @{$rows} ) {
        my %copy = %{$row};
        for my $column ( keys %{ $entry->{json} } ) {
            if ( defined $copy{$column} ) {
                $copy{$column} = $JSON->encode( $copy{$column} );
            }
        }
        push @raw, \%copy;
    }
    $answers->{ $functions->answer_key( $name, $values ) } = \@raw;
    return $rows->[0];
}

# The prepared command's call; a write the automod settles commits with
# its decisions in one transaction, as PostingAutomod::settle commits them.
async sub _execute_p ( $self, $plan, $context, $log_context ) {
    my $write_p = async sub ( $screened = undef, $functions = undef ) {
        return await $self->written_p( $plan, $functions, $context,
            $log_context );
    };
    return await $write_p->() if !$plan->{settle};
    return await $self->workflow->automod->settle_p( $plan->{type},
        $plan->{settle}, $write_p, $context, $self->scope );
}

# The command's call on the transaction it is given -- the automod's
# settling one, the caller's scope -- or else alone. A body that may mention
# someone has its call and its mentions in one transaction (a savepoint of
# a given one). The workflow's blocking methods run it settled on the
# blocking layer (PostingWorkflow::_planned): one executor for both.
async sub written_p ( $self, $plan, $functions, $context, $log_context ) {
    my $workflow = $self->workflow;
    my $reply    = $plan->{native_kind} eq 'reply';
    my $function = $reply ? 'forum_create_reply' : 'forum_write_command';
    my $mentioning =
      $workflow->mentioning( $plan->{type}, $plan->{call}, $plan->{prepared} );
    $functions //= $self->scope // $workflow->functions;
    my $write = async sub ($layer) {
        my $row    = await $layer->row_p( $function, $plan->{call}, $context );
        my $result = GPForum::Log->in_context(
            $log_context,
            sub {
                return $reply
                  ? $workflow->reply_result( $row, $plan->{prepared} )
                  : $workflow->write_result( $plan->{type}, $plan->{call},
                    $plan->{prepared}, $row );
            }
        );
        if ($mentioning) {
            await $workflow->record_mentions_p( $result, $mentioning,
                $context, $layer );
        }
        return $result;
    };
    my $result;
    try {
        $result =
          $mentioning
          ? await $functions->transaction_p( $write, $context )
          : await $write->($functions);
    }
    catch ($error) {
        return GPForum::Log->in_context(
            $log_context,
            sub {
                return $workflow->failure_result( $plan->{type}, $error );
            }
        );
    };
    return $result;
}

# A post the automod holds for review, kept for staff on the pooled
# connections.
async sub _hold_p ( $self, $plan, $context ) {
    return await $self->workflow->review->hold_p( $plan->{type},
        $plan->{screen}, $plan->{command}, $context );
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::PostingNative - Separate posting preparation from native atomic SQL commands.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $writer = GPForum::Service::Forum::PostingNative->new(workflow => $workflow);

=head1 DESCRIPTION

Screens the command against the automod rules and resolves the existing
versioned read calls asynchronously, runs the existing pure
validation/composition/signing preparation in an isolated process
(C<cpu_p>), then executes the original atomic stored command on a pooled
native connection. Preparation cannot open a PostgreSQL connection. A
refusal is audited, a held post is kept for review, and a settled write
commits with its automod decisions, all on the pooled connections.

=head1 SUBROUTINES/METHODS

=head2 call_p

Execute a supported posting method as a promise without reconnecting PostgreSQL
for each command. The in-memory doubles answer in the worker.

=head2 written_p

Takes a plan the workflow prepared (C<native_kind>, C<type>, C<call>,
C<prepared>), the call layer to run it on (undef for the writer's scope or
the workflow's own), the query context and the log context. Runs
C<api.forum_create_reply> or C<api.forum_write_command> with the plan's
parameters -- in one transaction with the mentions of a body that may
mention someone -- and answers the workflow's result, a failure as the
workflow words it. The workflow's blocking methods call it on the blocking
layer and read it settled (ADR 0177).

=head2 publish_p

Publish a post staff approved (C<thread.create> or C<reply.create>) as its
author's command, neither screened nor held again: the reads, the
preparation and the write as L</call_p> runs them, on the C<scope> the
writer was built with when there is one, so the post commits with the
review's decision.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the configured workflow, SQL catalogue and existing process limits.

=head1 DIAGNOSTICS

Failures preserve failed command responses. Ambiguous writes are never retried.

=head1 DEPENDENCIES

Mojolicious, Future::AsyncAwait and the existing posting and SQL services.

=head1 INCOMPATIBILITIES

No transaction or database handle crosses subprocess boundaries.

=head1 BUGS AND LIMITATIONS

None known. A body that may mention someone (it holds C<@>) has its call
and its mentions, notifications and badges in one transaction on the pooled
connections, as the blocking path has them.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
