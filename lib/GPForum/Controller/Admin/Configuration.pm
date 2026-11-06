# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Admin::Configuration;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Admin::Base', -signatures;
use v5.40;

our $VERSION = '0.001';
const my $OK          => 200;
const my $INVALID     => 422;
const my $CONFLICT    => 409;
const my $FORBIDDEN   => 403;
const my $UNAVAILABLE => 503;

sub show ($self) {
    return if !$self->authorized_user_id( $self->admin_access->view_action );
    return $self->_page;
}

sub change ($self) {
    my $actor = $self->authorized_write_user_id;
    return if !$actor;
    my $service = $self->gp_configuration;
    my %values;
    for my $field ( @{ $service->fields } ) {
        my $value = $self->param( $field->{env} );
        if ( defined $value ) { $values{ $field->{env} } = $value; }
    }
    my $input = {
        actor    => $actor,
        command  => $self->command_id_param,
        expected => $self->param('revision'),
        values   => \%values
    };
    my $result = $service->save_general($input);
    return $self->_result( $result, \%values );
}

sub restore ($self) {
    my $actor = $self->authorized_write_user_id;
    return if !$actor;
    my $result = $self->gp_configuration->reset_general(
        {
            actor    => $actor,
            command  => $self->command_id_param,
            expected => $self->param('revision'),
            key      => $self->param('setting')
        }
    );
    return $self->_result( $result, {} );
}

sub _result ( $self, $result, $values ) {
    my $status =
        $result->{status} eq 'ok'          ? $OK
      : $result->{status} eq 'conflict'    ? $CONFLICT
      : $result->{status} eq 'forbidden'   ? $FORBIDDEN
      : $result->{status} eq 'unavailable' ? $UNAVAILABLE
      :                                      $INVALID;
    $self->res->headers->cache_control('no-store');
    return $self->render( json => $result, status => $status )
      if $self->wants_json;
    if ( $result->{status} eq 'ok' ) {
        $self->flash( success => $self->t('admin.configuration_saved') );
        return $self->redirect_to('admin_configuration');
    }
    $self->gp_configuration->state( $self->gp_configuration->load );
    $self->stash( configuration_error_fields => $result->{error_fields} // [] );
    return $self->_page( $status, $result->{status}, $values );
}

sub _page ( $self, $status = $OK, $notice = q{}, $values = undef ) {
    my $page = $self->gp_configuration->general_page;
    my %invalid =
      map { $_ => 1 } @{ $self->stash('configuration_error_fields') // [] };
    for my $group ( @{ $page->{groups} } ) {
        for my $field ( @{ $group->{fields} } ) {
            $field->{choices} = $self->_choices($field);
            $field->{invalid} = $invalid{ $field->{env} } ? 1 : 0;
            if (   $values
                && exists $values->{ $field->{env} }
                && !$field->{secret} )
            {
                $field->{value} = $values->{ $field->{env} };
            }
            $field->{reset_command} = $self->gp_id->uuid;
        }
    }
    $self->res->headers->cache_control('no-store');
    return $self->render( json => $page, status => $status )
      if $self->wants_json;
    $page->{can_retry} = $values && keys %{$values} ? 1 : 0;
    return $self->render(
        template      => 'admin/configuration',
        status        => $page->{available} ? $status : $UNAVAILABLE,
        configuration => $page,
        notice        => $notice,
        command       => $self->gp_id->uuid
    );
}

sub _choices ( $self, $field ) {
    if ( $field->{name} eq 'default_locale' ) {
        return [ map { +{ value => $_->{locale}, label => $_->{native_name} } }
              @{ $self->ui_locale_options } ];
    }
    if ( $field->{name} eq 'default_theme' ) {
        return [
            map {
                +{ value => $_->{name}, label => $self->t( $_->{label_key} ) }
            } @{ $self->ui_theme_registry->theme_options( $field->{value} ) }
        ];
    }
    return undef if !$field->{one_of};
    return [
        map {
            +{
                value => $_,
                label => $self->t(
                    'admin.configuration_option_' . $field->{name} . '_' . $_
                )
            }
        } @{ $field->{one_of} }
    ];
}

1;

__END__

=head1 NAME

GPForum::Controller::Admin::Configuration - Administrator GUI configuration boundary.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Wired by GPForum bootstrap and the administrator routes.

=head1 DESCRIPTION

Implements core-owned GUI settings. Provider modules receive no access to
this service, its database or credentials. See docs/integrations.md.

=head1 SUBROUTINES/METHODS

=head2 show

Authorizes an administrator and renders the management page without caching its response.

=head2 change

Checks CSRF, administration permission and rate limits, then saves settings through the core configuration service.

=head2 restore

Restores an individual setting after the normal administrator write checks.

=head1 DIAGNOSTICS

Writes return explicit ok, invalid, conflict, forbidden or unavailable states.
Database errors follow the application's normal error boundary. Secrets and
submitted values are not included in diagnostics.

=head1 CONFIGURATION AND ENVIRONMENT

Installation configuration remains the bootstrap source. Durable overrides
are stored in PostgreSQL through versioned functions and administrator writes.

=head1 DEPENDENCIES

Uses the core configuration and authorization boundaries and PostgreSQL API.

=head1 INCOMPATIBILITIES

Requires the administrator configuration migration for editable settings.

=head1 BUGS AND LIMITATIONS

Host bootstrap settings remain deployment-owned; settings marked for restart
are read during service startup. A failed write never reports success.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
