# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Forum::Drafts;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Forum::ComposerBase', -async_await;
use v5.40;

use GPForum::Infrastructure::Text qw(trimmed);
use GPForum::Service::Forum::BodyLength;
use GPForum::Service::Forum::BodyRenderer;

our $VERSION = '0.001';

const my $HTTP_OK       => 200;
const my $HTTP_CONFLICT => 409;

async sub list ($self) {
    $self->private_draft_response;
    my $owner = ( await $self->await_p( $self->read_draft_owner ) );
    return if !$owner;
    my $drafts =
      ( await $self->call_p( $self->gp_draft_store, 'list_for_user', $owner ) );
    for my $draft ( @{$drafts} ) {
        $draft->{resume_url} = $self->_resume_url($draft);
        $draft->{delete_url} =
          $self->url_for( 'draft_delete', draft_id => $draft->{draft_id} )
          ->to_string;
    }
    return $self->render( json => { drafts => $drafts } ) if $self->wants_json;
    return $self->render( template => 'forum/drafts', drafts => $drafts );
}

async sub resume ($self) {
    $self->private_draft_response;
    my $owner = ( await $self->await_p( $self->read_draft_owner ) );
    return if !$owner;
    my $draft = (
        await $self->call_p(
            $self->gp_draft_store, 'find', $owner, $self->param('draft_id')
        )
    );
    return $self->not_found('draft not found')          if !$draft;
    return $self->render( json => { draft => $draft } ) if $self->wants_json;
    return ( await $self->await_p( $self->compose( $draft, $HTTP_OK ) ) );
}

async sub save ($self) {
    $self->private_draft_response;
    my $owner = ( await $self->await_p( $self->write_user_id('draft.save') ) );
    return if !$owner;
    my $input = $self->draft_input($owner);
    my $result =
      ( await $self->call_p( $self->gp_draft_store, 'save', $input ) );
    return ( await $self->await_p( $self->save_response( $input, $result ) ) );
}

async sub remove ($self) {
    $self->private_draft_response;
    my $owner =
      ( await $self->await_p( $self->write_user_id('draft.delete') ) );
    return if !$owner;
    my $result = (
        await $self->call_p(
            $self->gp_draft_store,
            'remove',
            {
                owner_user_id  => $owner,
                draft_id       => $self->param('draft_id'),
                draft_revision => $self->param('draft_revision'),
            }
        )
    );
    return $self->render(
        json   => $result,
        status => $self->draft_status($result)
    ) if $self->wants_json;
    return $self->_conflict( $self->i18n('forum.draft_conflict') )
      if !$result->{ok} && $self->draft_status($result) == $HTTP_CONFLICT;
    return $self->not_found('draft not found') if !$result->{ok};
    return $self->redirect_to('drafts');
}

async sub preview ($self) {
    $self->private_draft_response;
    my $owner =
      ( await $self->await_p( $self->write_user_id('draft.preview') ) );
    return if !$owner;
    my $input = $self->draft_input($owner);
    return (
        await $self->await_p(
            $self->save_response(
                $input,
                {
                    errors => {
                        body_source =>
                          GPForum::Service::Forum::BodyLength->too_long_error
                    },
                    ok     => 0,
                    status => 'invalid',
                }
            )
        )
      )
      if GPForum::Service::Forum::BodyLength->too_long( $input->{body_source} );
    return if !( await $self->await_p( $self->_target_allowed($input) ) );
    my $source   = trimmed( $input->{body_source} );
    my $renderer = GPForum::Service::Forum::BodyRenderer->new(
        math_plugins => $self->ui_integration_plugins );

    # Up to 50,000 characters of Markdown and math render off the event loop,
    # on the rendering lane, as the thread page's posts do.
    my $rendered = await $self->await_p(
        $renderer->render_many_p(
            [$source], $self->stash('gp_db_query_stats_token')
        )
    );
    my $html = GPForum::Service::Forum::BodyRenderer->with_rendered( $rendered,
        sub { return $renderer->render_safe($source); } );
    my $integrations = $self->ui_integration_plugins->for_source($source);

    if ( @{$integrations} ) {
        $html .= $self->render_to_string(
            template     => 'forum/_integrations',
            layout       => undef,
            integrations => $integrations,
        );
    }
    $html = $self->ui_render_policy->trusted_html(
        context => 'forum.post.body',
        html    => $html
    );
    return $self->render( json => { ok => 1, html => $html } )
      if $self->wants_json;
    $self->stash( composer_preview_html => $html );
    return ( await $self->await_p( $self->compose( $input, $HTTP_OK ) ) );
}

1;

__END__

=head1 NAME

GPForum::Controller::Forum::Drafts - Private draft and canonical preview routes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

Used by the forum composer routes and their tests.

=head1 DESCRIPTION

Lists, resumes, saves and removes only the signed-in author's drafts. Every
response prohibits shared caching. Writes require CSRF and rate-limit checks;
the draft store calls versioned PostgreSQL routines for all persistence.

=head1 SUBROUTINES/METHODS

=head2 list

Lists the authenticated owner's draft metadata as JSON or a native page with
resume and delete URLs. Draft bodies are omitted from this list.

=head2 resume

Loads a complete draft belonging to the authenticated owner and returns JSON
or restores its composer after checking target access.

=head2 save

Saves the submitted snapshot after CSRF and rate-limit checks, acknowledging
its optimistic revision or preserving submitted text on a conflict.

=head2 remove

Deletes the owner's expected draft revision after CSRF and rate-limit checks,
then returns JSON or redirects to the draft list.

=head2 preview

Checks the submitted body size and target access, then renders trimmed source
through the post renderer and trusted HTML policy. Returns JSON or a composer
preview without saving or publishing the text.

=head1 DIAGNOSTICS

Returns explicit draft statuses for the caller.

=head1 CONFIGURATION AND ENVIRONMENT

No environment variables are read directly.

=head1 DEPENDENCIES

L<GPForum::Controller::Forum::ComposerBase> and L<GPForum::Service::Forum::BodyRenderer>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Draft retention and authorization are enforced by the production store.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause license.

=cut
