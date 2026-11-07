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
use GPForum::Infrastructure::Id;
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
__PACKAGE__->requires('workflow');
my $JSON = JSON::MaybeXS->new( utf8 => 0 );

async sub call_p ( $self, $method, $arguments, $context, $cancelled ) {
    my $workflow = $self->workflow;
    my $type     = exists $METHOD{$method} ? $METHOD{$method} : undef;
    return await $self->_fallback_p( $method, $arguments, $context, $cancelled )
      if !$type
      || @{$arguments} != 1
      || !$workflow->functions
      || !$self->_same_schema;
    my $input = $arguments->[0];
    return await $self->_fallback_p( $method, $arguments, $context, $cancelled )
      if !length( trimmed( $input->{command_id} ) )
      || index( $input->{body_source} // q{}, q{@} ) >= 0;
    my $log_context = GPForum::Log->request_context;
    my %answers;
    my $idle = await $self->_idle_rules_p( $type, $input, \%answers, $context );
    return await $self->_fallback_p( $method, $arguments, $context, $cancelled )
      if !$idle;
    try { await $self->_context_p( $type, $input, \%answers, $context ); }
    catch ($error) {
        return GPForum::Log->in_context( $log_context,
            sub { return $workflow->_command_log_failure($error); } );
    };
    my $plan;

    if ( exists $BODY_PREPARATION{$type} ) {
        $plan = await GPForum::Log->in_context(
            $log_context,
            sub {
                return GPForum::Infrastructure::AsyncWork->shared->run_p(
                    sub {
                        return $self->_plan_data( $method, $input, \%answers );
                    },
                    $cancelled,
                    1
                );
            }
        );
    }
    else {
        $plan = GPForum::Log->in_context( $log_context,
            sub { return $self->_plan_data( $method, $input, \%answers ); } );
    }
    return $plan if !$plan->{native_kind};
    return await $self->_execute_p( $plan, $context, $log_context );
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

sub _plan_data ( $self, $method, $input, $answers ) {
    my $workflow = $self->workflow;

    # This scope never yields, in either process. Unexpected SQL fails closed.
    local $GPForum::Infrastructure::PgStorage::HTTP_PID = $PROCESS_ID;
    local $workflow->{native_plan} = 1;                                  ## no critic (Variables::ProhibitLocalVars) -- synchronous data-only preparation scope
    return GPForum::Infrastructure::SqlFunction->answering( $answers,
        sub { return $workflow->$method($input); } );
}

sub _fallback_p ( $self, $method, $arguments, $context, $cancelled ) {
    return GPForum::Infrastructure::AsyncWork->shared->service_result_p(
        $self->workflow, $method, $arguments, $context, $cancelled );
}

async sub _idle_rules_p ( $self, $type, $input, $answers, $context ) {
    my $screened =
         $type eq 'thread.create'
      || $type eq 'reply.create'
      || $type eq 'thread.edit'
      || $type eq 'post.edit';
    return 1 if !$screened || !$self->workflow->automod;
    my $viewer = $input->{viewer};
    return 1 if $viewer && $viewer->can('moderates') && $viewer->moderates;
    my $user = $input->{author_user_id};
    my $row  = await $self->_read_p(
        'moderation_automod_rules',
        {
            user_id => GPForum::Infrastructure::Id->is_uuid($user)
            ? $user
            : undef
        },
        $answers, $context
    );
    my $rules = $row ? $row->{document} : undef;
    return 1 if !$rules;
    return _idle($rules);
}

sub _idle ($rules) {
    return
         !@{ $rules->{words} // [] }
      && !defined $rules->{link_limit}
      && !$rules->{review_first_posts} ? 1 : 0;
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
    my $functions = $self->workflow->functions;
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

async sub _execute_p ( $self, $plan, $context, $log_context ) {
    my $workflow = $self->workflow;
    my $function =
      $plan->{native_kind} eq 'reply'
      ? 'forum_create_reply'
      : 'forum_write_command';
    my $result;
    try {
        my $row = await $workflow->functions->row_p( $function, $plan->{call},
            $context );
        $result =
            $plan->{native_kind} eq 'reply'
          ? $workflow->_reply_result( $row, $plan->{prepared} )
          : $workflow->_write_result( $plan->{type}, $plan->{call},
            $plan->{prepared}, $row );
    }
    catch ($error) {
        return GPForum::Log->in_context(
            $log_context,
            sub {
                return $workflow->_function_failure( $plan->{type}, $error );
            }
        );
    };
    return $result;
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

Resolves existing versioned read calls asynchronously, runs the existing pure
validation/composition/signing preparation in an isolated process, then executes
the original atomic stored command on a retained native connection. Preparation
cannot open a PostgreSQL connection. Active moderation rules and mentions retain
the original isolated transactional workflow.

=head1 SUBROUTINES/METHODS

=head2 call_p

Execute a supported posting method as a promise without reconnecting PostgreSQL
for each command. Unsupported workflows retain their original executor.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the configured workflow, SQL catalogue and existing process limits.

=head1 DIAGNOSTICS

Failures preserve failed command responses. Ambiguous writes are never retried.

=head1 DEPENDENCIES

Mojolicious, Future::AsyncAwait and the existing posting and SQL services.

=head1 INCOMPATIBILITIES

No transaction or database handle crosses subprocess boundaries.

=head1 BUGS AND LIMITATIONS

Moderation decisions and mentions requiring an extended transaction retain the
original complete workflow executor.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
