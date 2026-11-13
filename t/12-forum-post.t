# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Forum::PostComposer;
use GPForum::Test::Id;

our $VERSION = '0.001';

# PostComposer builds the reply and revision commands. The stores' writes are
# PostgreSQL's (ADR 0177): t/integration covers them.

const my $EXPECTED_TESTS => 31;

plan tests => $EXPECTED_TESTS;

my $id_service = GPForum::Test::Id->new;
my $composer =
  GPForum::Service::Forum::PostComposer->new( id_service => $id_service, );

my $prepared = $composer->prepare(
    {
        thread_id       => 'thread-1',
        author_user_id  => 'user-1',
        position        => 2,
        body_source     => 'Reply <body> & thanks',
        body_hash       => 'hash-2',
        idempotency_key => 'reply-command-1',
        visibility      => 'public',
    }
);

ok( $prepared->{ok}, 'post command is prepared' );
is( $prepared->{command}{post}{post_id}, 'generated-1',
    'post id is generated' );
is( $prepared->{command}{body}{body_id}, 'generated-2',
    'body id is generated' );
is( $prepared->{command}{revision}{revision_id},
    'generated-3', 'revision id is generated' );
is( $prepared->{command}{post}{thread_id}, 'thread-1', 'post targets thread' );
is( $prepared->{command}{post}{position},  2, 'post position is kept' );
is( $prepared->{command}{idempotency_key},
    'reply-command-1', 'post command preserves boundary idempotency key' );
is( $prepared->{command}{post}{current_body_id},
    'generated-2', 'post points at current body' );
is( $prepared->{command}{post}{current_revision_id},
    'generated-3', 'post points at current revision' );
is(
    $prepared->{command}{body}{body_rendered_safe},
    '<p>Reply &lt;body&gt; &amp; thanks</p>',
    'body is rendered safely'
);
ok( !exists $prepared->{command}{counter_shard},
    'the reply command carries no counter part: the store counts it' );

my $invalid = $composer->prepare(
    {
        thread_id      => q{},
        author_user_id => q{},
        position       => 0,
        body_source    => q{},
        body_hash      => q{},
        visibility     => 'secret',
    }
);

ok( !$invalid->{ok}, 'invalid post command is rejected' );
is(
    $invalid->{errors}{thread_id},
    'thread_id is required',
    'thread is required'
);
is(
    $invalid->{errors}{author_user_id},
    'author_user_id is required',
    'author is required'
);
is(
    $invalid->{errors}{position},
    'position is invalid',
    'position is validated'
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

# ADR 0102: a reply without a visibility inherits its thread's effective
# visibility, and may not ask for a broader one.
my %in_members = (
    author_user_id   => 'user-1',
    body_hash        => 'hash-9',
    body_source      => 'Hello members',
    idempotency_key  => 'reply-command-9',
    position         => 3,
    thread_id        => 'thread-1',
    visibility_floor => 'members',
);
is( $composer->prepare( {%in_members} )->{command}{post}{visibility},
    'members', 'a reply inherits its thread\'s visibility' );
is(
    $composer->prepare( { %in_members, visibility => 'public' } )
      ->{errors}{visibility},
    'visibility is broader than its thread',
    'and may not be broader than it'
);
is(
    $composer->prepare( { %in_members, visibility => 'private' } )
      ->{command}{post}{visibility},
    'private',
    'but may be narrower'
);

my $allocated_prepared = $composer->prepare(
    {
        thread_id         => 'thread-1',
        author_user_id    => 'user-1',
        allocate_position => 1,
        body_source       => 'Allocated reply',
        body_hash         => 'hash-3',
        idempotency_key   => 'reply-command-2',
        visibility        => 'public',
    }
);
ok( $allocated_prepared->{ok}, 'post command can defer position allocation' );
is( $allocated_prepared->{command}{post}{position},
    0, 'deferred command keeps invalid placeholder out of caller logic' );

my $revision_prepared = $composer->prepare_revision(
    {
        post_id         => 'post-1',
        editor_user_id  => 'user-1',
        body_source     => 'Edited <body> text',
        body_hash       => 'hash-edit',
        idempotency_key => 'edit-command-1',
        thread_id       => 'thread-1',
    }
);
ok( $revision_prepared->{ok}, 'revision command is prepared' );
is( $revision_prepared->{command}{revision}{revision_number},
    0, 'revision command defers revision numbering to the store' );
is( $revision_prepared->{command}{post}{post_id},
    'post-1', 'revision command keeps the existing post id' );
like( $revision_prepared->{command}{body}{body_rendered_safe},
    qr/Edited/msx, 'revision command renders the new body' );

my $invalid_revision = $composer->prepare_revision(
    {
        post_id        => q{},
        editor_user_id => q{},
        body_source    => q{},
        body_hash      => q{},
    }
);
ok( !$invalid_revision->{ok}, 'invalid revision command is rejected' );
is(
    $invalid_revision->{errors}{post_id},
    'post_id is required',
    'revision requires post id'
);
is(
    $invalid_revision->{errors}{editor_user_id},
    'editor_user_id is required',
    'revision requires editor'
);
is(
    $invalid_revision->{errors}{body_source},
    'body is required',
    'revision requires body'
);

1;
