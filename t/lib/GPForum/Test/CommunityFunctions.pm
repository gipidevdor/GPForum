# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::CommunityFunctions;

use Carp qw(croak);
use Const::Fast;
use Mojo::Base 'GPForum::Test::LoggedCalls', -signatures;
use v5.40;

use GPForum::Service::Community::Workflow;
use GPForum::Service::WorkflowResult qw(workflow_result);

our $VERSION = '0.001';

# The community commands (ADR 0126, section 5) over in-memory services: the
# command log kept here, and each command's write handed to the sink's
# store method, by the command type its log row names. The answer is the
# store's: not found when it answers nothing or ok => 0, else the fields of
# its kind a command records.
const my %COMMAND => (
    'community.bookmark'        => [ save_bookmark          => 'bookmark' ],
    'community.bookmark_remove' => [ remove_for_user_target => 'bookmark' ],
    'community.like'            => [ like                   => 'like' ],
    'community.unlike'          => [ unlike                 => 'like' ],
    'community.react'           => [ react                  => 'reaction' ],
    'community.unreact'         => [ unreact                => 'reaction' ],
    'community.subscribe'       => [ save_subscription      => 'subscription' ],
    'community.subscription_mute' => [ mute_for_user_target => 'subscription' ],
    'community.unsubscribe' => [ revoke_for_user_target => 'subscription' ],
);
const my %NOT_FOUND => (
    bookmark     => 'bookmark not found',
    like         => 'post not found',
    reaction     => 'post not found',
    subscription => 'subscription not found',
);
const my %PUBLIC_FIELDS => (
    bookmark => [
        qw(bookmark_id created_at deleted_at note ok target_id target_type user_id)
    ],
    like     => [qw(like_count liked ok post_id thread_id user_id)],
    reaction =>
      [qw(ok post_id reacted reaction reaction_count thread_id user_id)],
    subscription => [
        qw(created_at muted_at ok preference revoked_at subscription_id target_id
          target_type user_id)
    ],
);

has sink => undef;    # the store methods each command's write is handed to

# Installs, as an application's gp_community_workflow, the workflow on its
# collaborators with these functions as its call layer.
sub install ( $class, $app, %options ) {
    my $functions = $class->new(%options);
    $app->helper(
        gp_community_workflow => sub ($controller) {
            return GPForum::Service::Community::Workflow->new(
                functions => $functions,
                logger    => $controller->app->log,
                map { $_ => $controller->${ \"gp_$_" } }
                  qw(bookmark_store command_idempotency like_store
                  reaction_store report_store subscription_store)
            );
        }
    );

    return $functions;
}

sub rows ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, $values ];
    my $log = $values->{log} or croak "$name is not a community command";
    my ( $method, $kind ) = @{ $COMMAND{ $log->{command_type} } };

    return [
        $self->logged(
            $log->{idempotency_key},
            $log->{request_hash},
            $values->{answer},
            sub {
                my $value = $self->sink->$method( $values->{row} );
                return _answer( $kind, $value );
            }
        )
    ];
}

sub _answer ( $kind, $value ) {
    my $answer = ref $value eq 'HASH' ? $value : {};
    if ( !$value || ( exists $answer->{ok} && !$answer->{ok} ) ) {
        return workflow_result(
            error  => $answer->{error} || $NOT_FOUND{$kind},
            status => 'not_found',
        );
    }

    return workflow_result(
        status => 'ok',
        stored => { map { $_ => $answer->{$_} } @{ $PUBLIC_FIELDS{$kind} } },
    );
}

1;

__END__

=head1 NAME

GPForum::Test::CommunityFunctions - The community command functions over in-memory services.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $services = GPForum::Test::ForumWebServices->new;
    GPForum::Test::CommunityFunctions->install( $app, sink => $services );

=head1 DESCRIPTION

Stands in for the functions behind L<GPForum::Service::Community::Workflow>
-- C<api.community_bookmark_command>, C<api.community_like_command>,
C<api.community_subscribe_command> and their kin -- so the workflow's own
Perl runs as it runs on PostgreSQL. The command log is kept in memory
(L<GPForum::Test::LoggedCalls>); each command's write is handed to the
C<sink>'s store method -- C<save_bookmark>, C<remove_for_user_target>,
C<like>, C<unlike>, C<react>, C<unreact>, C<save_subscription>,
C<mute_for_user_target>, C<revoke_for_user_target> -- with the row the
workflow sends, and answered as the function answers.

=head1 SUBROUTINES/METHODS

=head2 install

Class method taking an application and the options of L</new>: installs a
C<gp_community_workflow> on the application's collaborators with a new
layer of these functions, and answers that layer.

=head2 sink

The double whose store methods each write is handed to.

=head2 rows

Takes a command function's name and values; answers its row.

=head1 DIAGNOSTICS

A call without a command log row croaks naming the function.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Test::LoggedCalls>, L<GPForum::Service::Community::Workflow>,
L<GPForum::Service::WorkflowResult>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The store's own checks are the sink's to make.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
