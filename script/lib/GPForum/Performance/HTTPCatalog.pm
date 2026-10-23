# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Performance::HTTPCatalog;
use v5.40;
use Const::Fast;
use Exporter                        qw(import);
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Performance::HTTPClient;
our $VERSION   = '0.001';
our @EXPORT_OK = qw(reads journeys publishing);
const my $FIRST_POST => 10_001;
const my %HOT        => map { $_ => 1 } qw(home thread search notifications);
my $THREAD   = seed_id( thread   => 1 );
my $POST     = seed_id( post     => $FIRST_POST );
my $CATEGORY = seed_id( category => 1 );

sub reads {
    my @spec;
    my %groups = (
        guest => [
            [ 'home',             q{/} ],
            [ 'categories',       '/categories' ],
            [ 'category',         "/c/$CATEGORY" ],
            [ 'thread',           "/t/$THREAD" ],
            [ 'search',           '/search?q=performance' ],
            [ 'autocomplete',     '/search/autocomplete?q=per' ],
            [ 'profile',          '/u/perf_user_2' ],
            [ 'tags',             '/tags' ],
            [ 'robots',           '/robots.txt' ],
            [ 'sitemap',          '/sitemap.xml' ],
            [ 'sitemap_page',     '/sitemap-1.xml' ],
            [ 'atom',             '/feed.atom' ],
            [ 'keys',             '/.well-known/gpforum-signing-keys' ],
            [ 'signature',        "/p/$POST/signature" ],
            [ 'thread_archive',   "/t/$THREAD/archive.mbox" ],
            [ 'category_archive', "/c/$CATEGORY/archive.mbox" ],
            [ 'cookies',          '/legal/cookies' ],
            [ 'privacy_policy',   '/legal/privacy' ],
            [ 'terms',            '/legal/terms' ],
            [ 'health',           '/health' ],
            [ 'health_live',      '/health/live' ],
            [ 'health_ready',     '/health/ready' ],
            [ 'login',            '/login' ],
            [ 'register',         '/register' ],
            [ 'password_reset',   '/password/reset' ],
        ],
        member => [
            [ 'home',                 q{/} ],
            [ 'categories',           '/categories' ],
            [ 'category',             "/c/$CATEGORY" ],
            [ 'thread',               "/t/$THREAD" ],
            [ 'search',               '/search?q=performance' ],
            [ 'autocomplete',         '/search/autocomplete?q=per' ],
            [ 'new_thread',           '/new-thread' ],
            [ 'drafts',               '/drafts' ],
            [ 'pending',              '/pending' ],
            [ 'bookmarks',            '/bookmarks' ],
            [ 'feed',                 '/feed' ],
            [ 'notifications',        '/notifications' ],
            [ 'notification_summary', '/notifications/summary' ],
            [ 'mentions',             '/mentions' ],
            [ 'settings',             '/settings' ],
            [ 'avatar',               '/settings/avatar' ],
            [ 'security',             '/settings/security' ],
            [ 'relations',            '/settings/ignored' ],
            [ 'privacy',              '/privacy' ],
            [ 'messages',             '/messages' ],
            [ 'message_compose',      '/messages/new/perf_user_2' ],
        ],
        moderator => [
            map { [ $_, "/moderation/$_" ] }
              qw(reports actions suspensions review transfers)
        ],
        admin => [
            [ 'dashboard', '/admin' ],
            (
                map { [ $_, "/admin/$_" ] }
                  qw(users roles categories automod security address-bans announcements audit jobs status registration settings privacy)
            ),
            [ 'user_roles', '/admin/users/' . seed_id( user => 3 ) . '/roles' ],
            [ 'metrics',    '/metrics' ],
        ],
    );
    for my $actor (qw(guest member moderator admin)) {
        for my $item ( @{ $groups{$actor} } ) {
            push @spec,
              {
                name  => "$actor.$item->[0]",
                actor => $actor,
                path  => $item->[1],
                hot => $actor eq 'member' && exists $HOT{ $item->[0] } ? 1 : 0,
                expensive => $item->[0] =~ /archive/msx                ? 1 : 0
              };
        }
    }
    return \@spec;
}

sub _post ( $name, $path, $status, $form = {} ) {
    my %native_json = (
        thread_edit      => 'updated',
        post_edit        => 'updated',
        thread_delete    => 'deleted',
        post_delete      => 'deleted',
        thread_restore   => 'restored',
        post_restore     => 'restored',
        thread_mark_read => 'ok',
    );
    $status = $native_json{$name} // $status;
    return {
        name   => $name,
        method => 'POST',
        path   => $path,
        json   => 1,
        status => $status,
        form   => $form
    };
}

sub publishing {
    return [
        {
            name => 'thread_form',
            path => '/new-thread',
            save => sub ( $ctx, $res ) {
                $ctx->{form} = GPForum::Performance::HTTPClient::fields( $res,
                    'form[data-composer]' );
            }
        },
        {
            name   => 'thread_create',
            method => 'POST',
            path   => '/threads',
            json   => 1,
            code   => 201,
            status => 'created',
            key    => 'thread_id',
            form   => sub ($ctx) {
                return {
                    %{ $ctx->{form} },
                    category_id => $CATEGORY,
                    title       => 'HTTP benchmark thread',
                    body_source => 'HTTP benchmark opening body'
                };
            },
            save =>
              sub ( $ctx, $res ) { $ctx->{thread} = $res->json->{thread_id}; }
        },
        {
            name => 'reply_form',
            path => sub ($ctx) { return "/t/$ctx->{thread}"; },
            save => sub ( $ctx, $res ) {
                $ctx->{form} = GPForum::Performance::HTTPClient::fields( $res,
                    'form[data-composer]' );
            }
        },
        {
            name   => 'reply_create',
            method => 'POST',
            path   => sub ($ctx) { return "/t/$ctx->{thread}/replies"; },
            json   => 1,
            code   => 201,
            status => 'created',
            key    => 'post_id',
            form   => sub ($ctx) {
                return {
                    %{ $ctx->{form} },
                    body_source => 'HTTP benchmark reply body'
                };
            },
            save => sub ( $ctx, $res ) { $ctx->{post} = $res->json->{post_id}; }
        },
    ];
}

sub journeys {
    my $thread = sub ($ctx) { return "/t/$ctx->{thread}"; };
    my @member = (
        @{ publishing() },
        _post(
            'thread_edit',
            sub ($ctx) { return $thread->($ctx) . '/edit'; },
            'thread_updated',
            { title => 'HTTP benchmark edited title' }
        ),
        _post(
            'post_edit',
            sub ($ctx) { return "/p/$ctx->{post}"; },
            'post_updated',
            {
                body_source      => 'HTTP benchmark revised reply',
                expected_version => 1,
                edit_reason      => 'benchmark'
            }
        ),
        _post(
            'thread_mark_read',
            sub ($ctx) { return $thread->($ctx) . '/read'; },
            'read_marked', { last_read_position => 2 }
        ),
        _post(
            'thread_bookmark',
            sub ($ctx) { return $thread->($ctx) . '/bookmark'; }, 'bookmarked'
        ),
        _post(
            'thread_bookmark_remove',
            sub ($ctx) { return $thread->($ctx) . '/bookmark/remove'; },
            'bookmark_removed'
        ),
        _post(
            'thread_subscribe',
            sub ($ctx) { return $thread->($ctx) . '/subscribe'; }, 'subscribed'
        ),
        _post(
            'thread_subscription_mute',
            sub ($ctx) { return $thread->($ctx) . '/subscribe/mute'; },
            'subscription_muted'
        ),
        _post(
            'thread_unsubscribe',
            sub ($ctx) { return $thread->($ctx) . '/subscribe/remove'; },
            'unsubscribed'
        ),
        _post( 'post_like',   "/p/$POST/like",        'post_liked' ),
        _post( 'post_unlike', "/p/$POST/like/remove", 'post_unliked' ),
        _post( 'post_react',  "/p/$POST/react/heart", 'post_reacted' ),
        _post(
            'post_unreact', "/p/$POST/react/heart/remove", 'post_unreacted'
        ),
        _post(
            'post_delete', sub ($ctx) { return "/p/$ctx->{post}/delete"; },
            'post_deleted'
        ),
        _post(
            'post_restore', sub ($ctx) { return "/p/$ctx->{post}/restore"; },
            'post_restored'
        ),
        _post(
            'thread_delete', sub ($ctx) { return $thread->($ctx) . '/delete'; },
            'thread_deleted'
        ),
        _post(
            'thread_restore',
            sub ($ctx) { return $thread->($ctx) . '/restore'; },
            'thread_restored'
        ),
    );
    my @draft = (
        {
            name => 'draft_form',
            path => '/new-thread',
            save => sub ( $ctx, $res ) {
                $ctx->{draft_form} =
                  GPForum::Performance::HTTPClient::fields( $res,
                    'form[data-composer]' );
            }
        },
        {
            name   => 'composer_preview',
            method => 'POST',
            path   => '/composer/preview',
            json   => 1,
            ok     => 1,
            form   => sub ($ctx) {
                return {
                    %{ $ctx->{draft_form} },
                    body_source => '**HTTP benchmark preview**'
                };
            }
        },
        {
            name   => 'draft_save',
            method => 'POST',
            path   => '/drafts',
            json   => 1,
            ok     => 1,
            form   => sub ($ctx) {
                return {
                    %{ $ctx->{draft_form} },
                    title       => 'Draft benchmark',
                    body_source => 'Private draft'
                };
            },
            save => sub ( $ctx, $res ) { $ctx->{draft} = $res->json->{draft}; }
        },
        {
            name => 'draft_resume',
            path => sub ($ctx) { return '/drafts/' . $ctx->{draft}{draft_id}; }
        },
        {
            name   => 'draft_delete',
            method => 'POST',
            json   => 1,
            ok     => 1,
            path   => sub ($ctx) {
                return '/drafts/' . $ctx->{draft}{draft_id} . '/delete';
            },
            form => sub ($ctx) {
                return { draft_revision => $ctx->{draft}{draft_revision} };
            }
        },
    );
    my @staff = ( @{ publishing() } );
    for my $change (qw(lock unlock pin unpin hide restore)) {
        push @staff, _post(
            "moderation_thread_$change",
            sub ($ctx) {
                return "/moderation/threads/$ctx->{thread}/$change";
            },
            'thread_'
              . (
                {
                    lock    => 'locked',
                    unlock  => 'unlocked',
                    pin     => 'pinned',
                    unpin   => 'unpinned',
                    hide    => 'hidden',
                    restore => 'restored'
                }->{$change}
              ),
            { reason => 'HTTP benchmark moderation' }
        );
    }
    push @staff, _post(
        'admin_role_create',
        '/admin/roles',
        'role_created',
        sub ($ctx) {
            return {
                name => 'bench_' . GPForum::Infrastructure::Id->new->uuid,
                description => 'Disposable benchmark role'
            };
        }
    );
    push @staff, _post(
        'admin_category_create',
        '/admin/categories',
        'category_created',
        sub ($ctx) {
            return {title => 'HTTP benchmark '
                  . GPForum::Infrastructure::Id->new->uuid };
        }
    );
    return [
        {
            name  => 'publishing_community',
            actor => 'member',
            steps => \@member
        },
        { name => 'drafts_preview',       actor => 'member', steps => \@draft },
        { name => 'staff_administration', actor => 'admin',  steps => \@staff },
        @{ _additional_journeys() },
    ];
}

sub _additional_journeys {
    my @settings = (
        {
            name     => 'settings_profile_update',
            method   => 'POST',
            path     => '/settings/profile',
            code     => 302,
            location => '/settings',
            form     => { bio => 'HTTP benchmark biography' }
        },
        {
            name     => 'settings_profile_verify',
            path     => sub ($ctx) { return '/settings'; },
            contains => 'HTTP benchmark biography'
        },
        {
            name     => 'locale_update',
            method   => 'POST',
            path     => '/locale',
            code     => 302,
            location => '/settings',
            form     => { locale => 'en', return_to => '/settings' }
        },
        {
            name     => 'theme_update',
            method   => 'POST',
            path     => '/theme',
            code     => 302,
            location => '/settings',
            form     => { theme => 'dark', return_to => '/settings' }
        },
        {
            name   => 'profile_ignore',
            method => 'POST',
            path   => '/u/perf_user_2/ignore',
            json   => 1,
            ok     => 1
        },
        {
            name   => 'profile_relation_remove',
            method => 'POST',
            path   => '/u/perf_user_2/relation/remove',
            json   => 1,
            ok     => 1
        },
        {
            name   => 'notifications_read_all',
            method => 'POST',
            path   => '/notifications/read-all',
            json   => 1,
            status => 'all_read'
        },
    );
    my @messages = (
        {
            name   => 'message_start',
            method => 'POST',
            path   => '/messages/new/perf_user_2',
            json   => 1,
            code   => 201,
            status => 'sent',
            key    => 'message_id',
            form   => { body => 'HTTP benchmark direct message' },
            save   => sub ( $ctx, $res ) {
                $ctx->{conversation} = $res->json->{conversation_id};
            }
        },
        {
            name => 'message_conversation',
            path => sub ($ctx) { return "/messages/$ctx->{conversation}"; }
        },
        {
            name   => 'message_reply',
            method => 'POST',
            path   => sub ($ctx) { return "/messages/$ctx->{conversation}"; },
            json   => 1,
            code   => 201,
            status => 'sent',
            key    => 'message_id',
            form   => { body => 'HTTP benchmark message reply' }
        },
    );
    my @poll = (
        @{ publishing() },
        {
            name => 'poll_form',
            path => sub ($ctx) { return "/t/$ctx->{thread}/tools/poll"; }
        },
        _post(
            'poll_create',
            sub ($ctx) { return "/t/$ctx->{thread}/tools/poll"; },
            'ok',
            {
                operation => 'create',
                question  => 'Benchmark poll?',
                options   => "First\nSecond"
            }
        ),
        {
            name   => 'poll_read',
            path   => sub ($ctx) { return "/t/$ctx->{thread}/tools/poll"; },
            json   => 1,
            status => 'ok'
        },
        _post(
            'poll_vote', sub ($ctx) { return "/t/$ctx->{thread}/tools/poll"; },
            'ok', { operation => 'vote', choice => 1 }
        ),
        _post(
            'poll_close', sub ($ctx) { return "/t/$ctx->{thread}/tools/poll"; },
            'ok', { operation => 'close' }
        ),
    );
    my @privacy = (
        _post(
            'privacy_export_request', '/privacy/export', 'export_requested'
        ),
        { name => 'privacy_export_dashboard', path => '/privacy' },
    );
    return [
        {
            name  => 'settings_notifications',
            actor => 'member',
            steps => \@settings
        },
        { name => 'messages',       actor => 'member', steps => \@messages },
        { name => 'polls',          actor => 'member', steps => \@poll },
        { name => 'privacy_export', actor => 'member', steps => \@privacy },
    ];
}
1;
