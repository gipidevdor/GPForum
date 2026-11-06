# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Admin::Integrations;

use Mojo::Base 'GPForum::Controller::Admin::Base', -signatures;
use v5.40;
use Const::Fast;
use GPForum::Infrastructure::SqlFunction;
use GPForum::ViewModel::Admin::IntegrationOverview;
use GPForum::Infrastructure::Id;
use GPForum::Service::Integration::Announcements;
use GPForum::Service::Integration::Syndication;
our $VERSION = '0.001';
const my $PAGE_LENGTH  => 50;
const my $HTTP_OK      => 200;
const my $HTTP_INVALID => 400;
const my $HTTP_FAILED  => 503;

sub show ($self) {
    return if !$self->authorized_user_id( $self->admin_access->view_action );
    return $self->_page;
}

sub announce ($self) {
    my $actor = $self->authorized_write_user_id or return;
    return $self->_page( 'invalid', $HTTP_INVALID )
      if !GPForum::Infrastructure::Id->is_uuid( $self->param('thread_id') );
    my $answer;
    try {
        $answer =
          $self->_announcements->request( $actor, $self->param('thread_id') );
    }
    catch ($error) { return $self->_page( 'failed', $HTTP_FAILED ); };
    return $self->_respond($answer);
}

sub retry_announcement ($self) {
    my $actor = $self->authorized_write_user_id or return;
    my $id    = $self->stash('announcement_id');
    return $self->_page( 'invalid', $HTTP_INVALID )
      if !GPForum::Infrastructure::Id->is_uuid($id);
    my $answer;
    try {
        $answer = $self->_announcements->retry_checked(
            {
                actor_user_id   => $actor,
                announcement_id => $id,
                checked         => $self->param('checked'),
                reason          => $self->param('reason')
            }
        );
    }
    catch ($error) { return $self->_page( 'failed', $HTTP_FAILED ); };
    return $self->_respond($answer);
}

sub fetch_feed ($self) {
    my $actor = $self->authorized_write_user_id or return;
    try { $self->_feeds->request( $actor, $self->param('source_url') ); }
    catch ($error) { return $self->_page( 'invalid', $HTTP_INVALID ); };
    return $self->_respond( { status => 'queued' } );
}

sub decide_feed ($self) {
    my $actor    = $self->authorized_write_user_id or return;
    my $item     = $self->stash('item_id');
    my $decision = $self->param('decision') // q{};
    return $self->_page( 'invalid', $HTTP_INVALID )
      if !GPForum::Infrastructure::Id->is_uuid($item)
      || ( $decision ne 'published' && $decision ne 'rejected' )
      || ( $decision eq 'published'
        && !GPForum::Infrastructure::Id->is_uuid( $self->param('category_id') )
      );
    my $answer;
    try {
        $answer = $self->_feeds->decide(
            {
                actor_user_id => $actor,
                item_id       => $item,
                decision      => $decision,
                category_id   => $self->param('category_id')
            },
            sub ($input) {
                return $self->gp_posting_workflow->create_thread(
                    { %{$input}, viewer => $self->gp_forum_viewer } );
            }
        );
    }
    catch ($error) { return $self->_page( 'failed', $HTTP_FAILED ); };
    return $self->_respond($answer);
}

sub _respond ( $self, $answer ) {
    return $self->render( json => $answer, status => $HTTP_OK )
      if $self->wants_json;
    return $self->_page( $answer->{status} // 'failed' );
}

sub _announcements ($self) {
    return GPForum::Service::Integration::Announcements->new(
        schema           => $self->gp_schema,
        policy_available => $self->gp_configuration->state->{available} ? 1 : 0,
        config           => $self->gp_config
    );
}

sub _feeds ($self) {
    return GPForum::Service::Integration::Syndication->new(
        schema           => $self->gp_schema,
        policy_available => $self->gp_configuration->state->{available} ? 1 : 0,
        config           => $self->gp_config
    );
}

sub _page ( $self, $notice = q{}, $status = $HTTP_OK ) {
    return $self->system_failure
      if !$self->gp_configuration->state->{available};
    $self->res->headers->cache_control('private, no-store');
    my $functions =
      GPForum::Infrastructure::SqlFunction->for_schema( $self->gp_schema );
    my %data;
    try {
        for my $pair (
            [ topics     => 'integration_public_topics' ],
            [ categories => 'integration_public_categories' ],
            [ deliveries => 'integration_announcement_list' ]
          )
        {
            $data{ $pair->[0] } =
              [ map { $_->{result} } @{ $functions->rows( $pair->[1], {} ) } ];
        }
        my $after = $self->param('after');
        if ( !defined $after || !GPForum::Infrastructure::Id->is_uuid($after) )
        {
            $after = undef;
        }

        $data{items} = [
            map { $_->{result} } @{
                $functions->rows( 'integration_feed_queue',
                    { after => $after } )
            }
        ];
    }
    catch ($error) { return $self->system_failure; };
    for my $delivery ( @{ $data{deliveries} } ) {
        $delivery->{status_label} =
          $self->t( 'admin.integrations_state_' . $delivery->{status} );
    }
    my %known = map { $_ => 1 }
      qw(queued sent uncertain cancelled failed unchanged invalid refused ok not_found held);
    if ( length($notice) && !$known{$notice} ) { $notice = 'failed'; }
    my $more = @{ $data{items} } > $PAGE_LENGTH ? pop @{ $data{items} } : undef;
    my $next =
        $more
      ? $self->url_for('admin_integrations')
      ->query( after => $data{items}[-1]{item_id} )
      : undef;
    return $self->render(
        template => 'admin/integrations',
        overview => GPForum::ViewModel::Admin::IntegrationOverview->new->page(
            $self->gp_config, $self->ui_integration_plugins, 1
        ),
        status => $status,
        %data,
        sources         => $self->gp_config->syndication_sources,
        discord_enabled => $self->_announcements->enabled,
        notice          => length($notice)
        ? $self->t( 'admin.integrations_state_' . $notice )
        : q{},
        next => $next
    );
}

1;

__END__

=head1 NAME

GPForum::Controller::Admin::Integrations - Manage selected announcements and moderated feed imports.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Controller::Admin::Integrations->new;

=head1 DESCRIPTION

Manage selected announcements and moderated feed imports. Core owns configuration, authorization and presentation.

=head1 SUBROUTINES/METHODS

=head2 show

Shows only globally authorized administrators the current integrations and bounded review queues.

=head2 announce

Checks authority, participation, CSRF and rate budgets before queueing a selected public topic.

=head2 retry_announcement

Requires an explicit remote-outcome check and a reason before queueing recovery of an uncertain or failed announcement.

=head2 fetch_feed

Queues an authorized source poll without fetching inside the web request.

=head2 decide_feed

Approves a candidate through normal forum posting or records rejection.

=head1 DIAGNOSTICS

Invalid configuration and transport failures raise typed exceptions.

=head1 CONFIGURATION AND ENVIRONMENT

The composition layer supplies validated settings and dependencies.

=head1 DEPENDENCIES

The Good Phorum runtime and the modules named above.

=head1 INCOMPATIBILITIES

Network capabilities are independent of the frozen local Plugin API v1.

=head1 BUGS AND LIMITATIONS

External operations depend on the configured provider and its availability.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
