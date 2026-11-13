# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::Navigation;
use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;
our $VERSION = '0.001';
const my $GROUP_LINKS => 3;

# Route, translation and required global permission. Member-only groups are
# omitted for guests. No database call or generated HTML occurs here.
const my @GROUPS => (
    [
        'moderation',
        'nav.moderation',
        1,
        [
            [ 'moderation_media', 'nav.menu_uploads', 'thread.moderate' ],
            [
                'moderation_review', 'moderation.review_queue',
                'report.view_queue'
            ],
            [ 'moderation_reports', 'moderation.reports', 'report.view_queue' ],
            [
                'moderation_transfers', 'moderation.organize',
                'thread.moderate'
            ],
            [
                'moderation_actions', 'moderation.actions',
                'moderation_action.view'
            ],
            [
                'moderation_suspensions', 'moderation.suspensions',
                'suspension.view'
            ],
        ]
    ],
    [
        'administration',
        'admin.admin',
        1,
        [
            [ 'admin_dashboard', 'admin.admin', 'admin_console.view' ],
            [
                'admin_configuration', 'admin.configuration_general',
                'admin_console.view'
            ],
            [ 'admin_plugins', 'admin.plugins', 'admin_console.view' ],
            [
                'admin_integrations', 'admin.integrations_network',
                'admin_console.view'
            ],
            [
                'admin_registration', 'admin.registration',
                'admin_console.view'
            ],
            [ 'admin_users',      'admin.users',      'admin_console.view' ],
            [ 'admin_roles',      'admin.roles',      'admin_console.view' ],
            [ 'admin_categories', 'admin.categories', 'admin_console.view' ],
            [
                'admin_announcements', 'admin.announcements',
                'admin_console.view'
            ],
            [ 'admin_automod', 'admin.automod', 'admin_console.view' ],
            [
                'admin_second_factor', 'admin.second_factor',
                'admin_console.view'
            ],
            [
                'admin_address_bans', 'admin.address_bans',
                'admin_console.view'
            ],
            [ 'admin_audit',  'admin.audit',          'admin_console.view' ],
            [ 'admin_jobs',   'admin.async_jobs',     'admin_console.view' ],
            [ 'admin_status', 'admin.health_runtime', 'admin_console.view' ],
            [
                'admin_settings', 'admin.configuration_diagnostics',
                'admin_console.view'
            ],
            [ 'privacy_review', 'admin.privacy_review', 'privacy_rights.view' ],
        ]
    ],
    [
        'account',
        'nav.menu_account',
        1,
        [
            [ 'settings', 'settings.title' ],
            [ 'settings', 'profile.edit', undef, 'settings-profile-heading' ],
            [ 'settings_avatar',   'profile.avatar_title' ],
            [ 'settings_security', 'auth.second_factor_title' ],
            [ 'settings_passkeys', 'auth.passkey_title' ],
            [ 'settings_openid',   'auth.oidc_settings' ],
            [ 'member_relations',  'community.relation_page_title' ],
            [ 'privacy_dashboard', 'nav.your_data' ],
        ]
    ],
    [
        'forum',
        'nav.menu_forum',
        0,
        [
            [ 'home',       'nav.home' ],
            [ 'categories', 'nav.categories' ],
            [ 'tags',       'nav.tags' ],
            [ 'tags', 'forum.tag_filter_title', undef, 'tag-filter-form' ],
            [ 'forum_search',  'nav.search' ],
            [ 'new_thread',    'nav.start_thread',  'member' ],
            [ 'new_media',     'media.publish',     'member' ],
            [ 'feed',          'nav.feed',          'member' ],
            [ 'following',     'follow.title',      'member' ],
            [ 'bookmarks',     'nav.bookmarks',     'member' ],
            [ 'drafts',        'nav.drafts',        'member' ],
            [ 'pending_posts', 'nav.menu_pending',  'member' ],
            [ 'mentions',      'nav.mentions',      'member' ],
            [ 'notifications', 'nav.notifications', 'member' ],
            [ 'messages',      'nav.messages',      'member' ],
            [ 'message_new',   'messages.new',      'member' ],
        ]
    ],
    [
        'information',
        'nav.menu_information',
        0,
        [
            [ 'public_feed',   'nav.menu_public_feed' ],
            [ 'legal_terms',   'layout.footer_terms' ],
            [ 'legal_privacy', 'layout.footer_privacy' ],
            [ 'legal_cookies', 'layout.footer_cookies' ],
            [ 'legal_notice',  'layout.footer_notice' ],
        ]
    ],
);

sub groups ( $self, $input = {} ) {
    my $permissions = $input->{permissions} // {};
    my @groups;
    for my $definition (@GROUPS) {
        my ( $id, $label, $member, $items ) = @{$definition};
        if ( $member && !$input->{member} ) { next; }
        my @links;
        for my $item ( @{$items} ) {
            my ( $route, $key, $required, $fragment ) = @{$item};
            if (
                defined $required
                && !(
                      $required eq 'member'
                    ? $input->{member}
                    : $permissions->{$required}
                )
              )
            {
                next;
            }
            push @links,
              {
                route     => $route,
                label_key => $key,
                ( defined $fragment ? ( fragment => $fragment ) : () )
              };
        }
        if ( !@links ) { next; }
        if ( $id eq 'account' && length( $input->{username} // q{} ) ) {
            unshift @links,
              {
                route      => 'profile',
                label_key  => 'nav.profile',
                parameters => { username => $input->{username} }
              };
        }
        push @groups, { id => $id, label_key => $label, links => \@links };
    }
    my %order = (
        forum          => 0,
        account        => 1,
        moderation     => 2,
        administration => 3,
        information    => 4,
    );
    return [ sort { $order{ $a->{id} } <=> $order{ $b->{id} } } @groups ];
}

sub routes ($self) {
    return [
        'profile',
        map {
            map { $_->[0] }
              @{ $_->[$GROUP_LINKS] }
        } @GROUPS
    ];
}
1;

__END__

=head1 NAME

GPForum::Web::Navigation - The finite catalogue of forum, account and staff destinations.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # See the description and methods below.

=head1 DESCRIPTION

The finite catalogue of forum, account and staff destinations.

=head1 SUBROUTINES/METHODS

=head2 groups

Accepts member, username and permissions. Returns fresh groups of permitted links.
Unknown permissions do not expose extra destinations.

=head2 routes

Lists the catalogue route names for route and GUI coverage checks.

=head1 DIAGNOSTICS

Permission failures omit staff destinations; target controllers retain their authorization.

=head1 CONFIGURATION AND ENVIRONMENT

Uses request-owned navigation context. No permission cache crosses requests.

=head1 DEPENDENCIES

L<Const::Fast>, L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Contextual actions remain on their resource pages.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
