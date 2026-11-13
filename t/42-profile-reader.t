# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use MIME::Base64 qw(encode_base64url);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Operations::LocalCache;
use GPForum::Service::Identity::ProfileReader;
use GPForum::Test::AnsweringFunctions;

our $VERSION = '0.001';

const my $PROFILE_LIMIT => 1;
const my $FETCH_ROWS    => $PROFILE_LIMIT + 1;
const my $TRUST_SCORE   => 55;
const my $AT_CODE       => 64;
const my $AT_SIGN       => chr $AT_CODE;
const my $PUBLIC_TOTAL  => 3;
const my $CURSOR_AT     => '2026-05-23T12:00:00Z';
const my $CURSOR_ID     => '018f1000-0000-7000-8000-000000000001';
const my $CURSOR        => encode_base64url("$CURSOR_AT|$CURSOR_ID");

# What is public is api.identity_profile_*'s to decide
# (t/integration/postgres-sql-function-identity.t); the reader asks for the
# member, pages the lists it answers, and caches the counts.
_profile_answered();
_cursors_asked();
_counts_cached();
_not_public();

done_testing();

sub _profile_answered {
    my $functions = _functions();
    my $profile   = _reader($functions)
      ->public_profile( ' GPForum_Contributors ', { limit => $PROFILE_LIMIT } );

    ok( $profile->{ok}, 'profile reader returns public profile' );
    my $user = $profile->{profile}{user};
    is(
        $user->{display_name},
        'GPForum Contributors',
        'profile exposes display name'
    );
    is( $user->{bio}, 'Writes about Perl.', 'profile exposes the bio' );
    is(
        $user->{profile_label},
        $AT_SIGN . 'gpforum_contributors',
        'profile exposes public username label'
    );
    ok( !exists $user->{email_normalized}, 'profile does not expose email' );
    is( $user->{avatar_id}, 'avatar-1', 'profile exposes the picture' );
    is( $profile->{profile}{trust}{score},
        $TRUST_SCORE, 'profile exposes trust score' );
    is(
        $profile->{profile}{trust}{badge},
        'Trusted contributor',
        'profile exposes trust badge'
    );
    is( $profile->{profile}{counts}{total_public},
        $PUBLIC_TOTAL, 'profile answers the counts' );
    is( scalar @{ $profile->{profile}{threads}{items} },
        1, 'profile threads are keyset-windowed' );
    is( $profile->{profile}{threads}{items}[0]{title},
        'Welcome', 'profile exposes public thread title' );
    ok(
        $profile->{profile}{threads}{next_cursor},
        'profile exposes next cursor for public threads'
    );
    is( $profile->{profile}{replies}{items}[0]{body},
        'Public reply', 'profile exposes the reply body' );
    ok(
        !$profile->{profile}{replies}{next_cursor},
        'and no cursor past the last reply'
    );
    is_deeply(
        $functions->asked('identity_user_by_identifier'),
        [ { identifier => 'gpforum_contributors', by_email => 0 } ],
        'profile lookup normalizes username'
    );

    for my $list (qw(threads replies)) {
        is_deeply(
            $functions->asked("identity_profile_$list"),
            [
                {
                    user_id   => 'user-1',
                    after_at  => undef,
                    after_id  => undef,
                    row_limit => $FETCH_ROWS
                }
            ],
            "profile $list are asked for one extra row, from the newest"
        );
    }

    return;
}

sub _cursors_asked {
    for my $case (
        [ after => 'identity_profile_threads', 'identity_profile_replies' ],
        [
            replies_after => 'identity_profile_replies',
            'identity_profile_threads'
        ],
      )
    {
        my ( $option, $paged, $first ) = @{$case};
        my $functions = _functions();
        _reader($functions)
          ->public_profile( 'gpforum_contributors',
            { limit => $PROFILE_LIMIT, $option => $CURSOR } );
        is_deeply(
            [ @{ $functions->asked($paged)->[0] }{qw(after_at after_id)} ],
            [ $CURSOR_AT, $CURSOR_ID ],
            "$option pages $paged"
        );
        is_deeply(
            [ @{ $functions->asked($first)->[0] }{qw(after_at after_id)} ],
            [ undef, undef ],
            "and leaves $first on its first page"
        );
    }

    return;
}

# The counts walk every public post of the member, on a page anyone may ask
# for again: a second view within the cache's time takes them from it, and
# the purge of the member's tag, which their own write sends, reads them
# again.
sub _counts_cached {
    my $functions = _functions();
    my $cached    = _reader($functions);
    $cached->cache( GPForum::Service::Operations::LocalCache->new );
    my $counted = sub {
        return scalar @{ $functions->asked('identity_profile_counts') };
    };

    my $first =
      $cached->public_profile( 'gpforum_contributors',
        { limit => $PROFILE_LIMIT } );
    $cached->public_profile( 'gpforum_contributors',
        { limit => $PROFILE_LIMIT } );
    is( $counted->(), 1, 'a second view takes the counts from the cache' );
    is( $first->{profile}{counts}{total_public},
        $PUBLIC_TOTAL, 'the counts read' );
    $cached->cache->invalidate_tag(
        GPForum::Service::Identity::ProfileReader->counts_tag(
            $first->{profile}{user}{user_id}
        )
    );
    $cached->public_profile( 'gpforum_contributors',
        { limit => $PROFILE_LIMIT } );
    is( $counted->(), 2, q{and the member's own tag reads them again} );

    return;
}

sub _not_public {
    for my $case (
        [ missing   => undef ],
        [ deleted   => { deleted_at => '2026-05-23T12:00:00Z' } ],
        [ suspended => { status     => 'suspended' } ],
      )
    {
        my ( $name, $changes ) = @{$case};
        my $functions = _functions($changes);
        is_deeply(
            _reader($functions)
              ->public_profile( $name, { limit => $PROFILE_LIMIT } ),
            { ok => 0, error => 'not_found' },
            "$name profile is not public"
        );
        is( scalar @{ $functions->asked('identity_profile_threads') },
            0, 'and nothing else of it is read' );
    }

    return;
}

sub _reader ($functions) {
    return GPForum::Service::Identity::ProfileReader->new(
        functions => $functions,
        schema    => {}
    );
}

# The member's answers: undef $changes for no member, else the member's row
# changed by them.
sub _functions ( $changes = {} ) {
    my $user =
      defined $changes
      ? {
        id           => 'user-1',
        username     => 'gpforum_contributors',
        display_name => 'GPForum Contributors',
        bio          => 'Writes about Perl.',
        status       => 'active',
        trust_level  => 1,
        created_at   => '2026-05-23T12:00:00Z',
        updated_at   => '2026-05-23T12:00:00Z',
        deleted_at   => undef,
        %{$changes},
      }
      : undef;
    return GPForum::Test::AnsweringFunctions->new(
        answers => {
            identity_user_by_identifier => [ $user // () ],
            identity_profile_counts     => [
                {
                    public_threads => 2,
                    public_replies => 1,
                    total_public   => $PUBLIC_TOTAL
                }
            ],
            identity_profile_threads => [
                _thread( 'thread-1', 'Welcome', '2026-05-23T12:00:00Z' ),
                _thread( 'thread-2', 'Second',  '2026-05-23T11:00:00Z' ),
            ],
            identity_profile_replies => [
                {
                    post_id          => 'post-2',
                    thread_id        => 'thread-1',
                    author_user_id   => 'user-1',
                    position         => 2,
                    visibility       => 'public',
                    moderation_state => 'visible',
                    created_at       => '2026-05-23T12:30:00Z',
                    thread_title     => 'Welcome',
                    thread_slug      => 'welcome',
                    body             => 'Public reply',
                }
            ],
            community_avatar_status => [ { attachment_id => 'avatar-1' } ],
            identity_profile_trust  => [
                {
                    score         => $TRUST_SCORE,
                    trust_level   => 2,
                    calculated_at => '2026-05-23T12:00:00Z',
                    version       => 3,
                }
            ],
        }
    );
}

sub _thread ( $id, $title, $activity ) {
    return {
        thread_id        => $id,
        category_id      => 'category-1',
        author_user_id   => 'user-1',
        title            => $title,
        slug             => lc $title,
        visibility       => 'public',
        moderation_state => 'visible',
        last_activity_at => $activity,
        created_at       => '2026-05-23T10:00:00Z',
    };
}

1;
