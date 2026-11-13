# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Forum::ThreadComposer;
use GPForum::Test::Id;

our $VERSION = '0.001';

# ThreadComposer builds the thread, title and move commands. The stores'
# writes are PostgreSQL's (ADR 0177): t/integration covers them.

const my $EXPECTED_TESTS => 30;

plan tests => $EXPECTED_TESTS;

my $id_service = GPForum::Test::Id->new;
my $composer =
  GPForum::Service::Forum::ThreadComposer->new( id_service => $id_service, );

my $prepared = $composer->prepare(
    {
        category_id     => 'category-1',
        author_user_id  => 'user-1',
        title           => '  Welcome to GP Forum  ',
        body_source     => 'Hello <forum> & welcome',
        body_hash       => 'hash-1',
        idempotency_key => 'thread-command-1',
        visibility      => 'public',
    }
);

ok( $prepared->{ok}, 'thread command is prepared' );
is( $prepared->{command}{thread}{thread_id},
    'generated-1', 'thread id is generated' );
is( $prepared->{command}{post}{post_id},
    'generated-2', 'post id is generated' );
is( $prepared->{command}{idempotency_key},
    'thread-command-1', 'thread command preserves boundary idempotency key' );
is( $prepared->{command}{body}{body_id},
    'generated-3', 'body id is generated' );
is( $prepared->{command}{revision}{revision_id},
    'generated-4', 'revision id is generated' );
is( $prepared->{command}{thread}{slug},
    'welcome-to-gp-forum', 'title is normalized into slug' );
ok(
    !exists $prepared->{command}{thread}{last_activity_at},
    'thread record lets PostgreSQL default last activity to now()'
);
ok(
    !exists $prepared->{command}{counter}{last_activity_at},
    'thread counter record lets PostgreSQL default last activity to now()'
);
is( $prepared->{command}{post}{current_body_id},
    'generated-3', 'post points at current body' );
is( $prepared->{command}{post}{current_revision_id},
    'generated-4', 'post points at current revision' );
is(
    $prepared->{command}{body}{body_rendered_safe},
    '<p>Hello &lt;forum&gt; &amp; welcome</p>',
    'body is rendered safely'
);
is( $prepared->{command}{revision}{revision_number},
    1, 'first revision number is one' );

my $invalid = $composer->prepare(
    {
        category_id    => q{},
        author_user_id => q{},
        title          => 'no',
        body_source    => q{},
        body_hash      => q{},
        visibility     => 'secret',
    }
);

ok( !$invalid->{ok}, 'invalid thread command is rejected' );
is(
    $invalid->{errors}{category_id},
    'category_id is required',
    'category is required'
);
is(
    $invalid->{errors}{author_user_id},
    'author_user_id is required',
    'author is required'
);
is(
    $invalid->{errors}{title},
    'title length is invalid',
    'title length is validated'
);
is( $invalid->{errors}{body_source}, 'body is required', 'body is required' );
is(
    $invalid->{errors}{body_hash},
    'body_hash is required',
    'body hash is required'
);
is(
    $invalid->{errors}{visibility},
    'visibility is invalid',
    'visibility is validated'
);

# ADR 0102: a thread without a visibility inherits its category's effective
# visibility, and may not ask for a broader one.
my %in_members = (
    author_user_id   => 'user-1',
    body_hash        => 'hash-9',
    body_source      => 'Hello members',
    category_id      => 'category-1',
    idempotency_key  => 'thread-command-9',
    title            => 'Members only',
    visibility_floor => 'members',
);
is( $composer->prepare( {%in_members} )->{command}{thread}{visibility},
    'members', 'a thread inherits its category\'s visibility' );
is(
    $composer->prepare( { %in_members, visibility => 'public' } )
      ->{errors}{visibility},
    'visibility is broader than its category',
    'and may not be broader than it'
);
is(
    $composer->prepare( { %in_members, visibility => 'private' } )
      ->{command}{thread}{visibility},
    'private',
    'but may be narrower'
);

my $title_prepared = $composer->prepare_title(
    {
        editor_user_id  => 'user-1',
        idempotency_key => 'thread-edit-command-1',
        thread_id       => 'thread-1',
        title           => '  Edited Welcome  ',
    }
);
ok( $title_prepared->{ok}, 'thread title command is prepared' );
is(
    $title_prepared->{command}{thread}{title},
    'Edited Welcome',
    'thread title is normalized'
);
is( $title_prepared->{command}{thread}{slug},
    'edited-welcome', 'edited title is normalized into slug' );
is(
    $composer->prepare_title(
        {
            editor_user_id => q{},
            thread_id      => q{},
            title          => 'no',
        }
    )->{errors}{title},
    'title length is invalid',
    'edited title length is validated'
);

my $move_prepared = $composer->prepare_move(
    {
        category_id     => 'category-2',
        editor_user_id  => 'user-1',
        idempotency_key => 'thread-move-command-1',
        thread_id       => 'thread-1',
    }
);
ok( $move_prepared->{ok}, 'thread move command is prepared' );
is( $move_prepared->{command}{thread}{category_id},
    'category-2', 'thread move keeps the destination category' );
is(
    $composer->prepare_move(
        {
            category_id    => q{},
            editor_user_id => 'user-1',
            thread_id      => 'thread-1',
        }
    )->{errors}{category_id},
    'category_id is required',
    'thread move requires a category'
);

1;
