# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use utf8;
use Test::More;
use Test::Mojo;
use Const::Fast;
use lib 'lib';
use lib 't/lib';
use GPForum::Infrastructure::Id;
use GPForum::Test::PgDatabase;
our $VERSION = '0.001';
const my $HTTP_OK        => 200;
const my $HTTP_FOUND     => 302;
const my $HTTP_FORBIDDEN => 403;
const my $NAME_TOO_LONG  => 101;
const my $BIO_TOO_LONG   => 501;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'requires PostgreSQL';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $dbh = $database->dbh;
my $ids = GPForum::Infrastructure::Id->new;
my ( $owner, $other ) = map { $ids->uuid } qw(owner other);

for my $user ( [ $owner, 'profile_writer' ], [ $other, 'profile_reader' ] ) {
    $dbh->do(
q{INSERT INTO users(id,username,display_name,email_normalized,password_hash,status,email_verified_at) VALUES (?,?,?,?,'x','active',now())},
        undef,
        $user->[0],
        $user->[1],
        $user->[1],
        "$user->[1]\@example.test"
    );
}
my $t      = Test::Mojo->new('GPForum');
my $routes = $t->app->routes;
$routes->get('/__test/profile/session/:id')->to(
    cb => sub ($c) {
        $c->session( user_id => $c->param('id') );
        return $c->render( text => 'ready' );
    }
);
$t->get_ok('/settings')->status_is($HTTP_FOUND);
$t->get_ok('/u/profile_writer')->status_is($HTTP_OK);
$t->element_exists_not('a[href="/settings#settings-profile-heading"]');
$t->get_ok("/__test/profile/session/$owner")->status_is($HTTP_OK);
$t->get_ok('/u/profile_writer')->status_is($HTTP_OK);
$t->element_exists('a[href="/settings#settings-profile-heading"]');
$t->get_ok('/u/profile_reader')->status_is($HTTP_OK);
$t->element_exists_not('a[href="/settings#settings-profile-heading"]');
$t->get_ok('/settings')->status_is($HTTP_OK);
$t->element_exists('input[name="display_name"][value="profile_writer"]');
my $dom    = $t->tx->res->dom;
my $form   = $dom->at('form[action="/settings/profile"]');
my %fields = map { $_->attr('name') => $_->attr('value') }
  @{ $form->find('input[name]')->to_array };
%fields = (
    %fields,
    display_name => 'Nome pubblico',
    bio          => '<script>alert(1)</script>',
    user_id      => $other,
    status       => 'deleted',
    trust_level  => 99,
);
$t->post_ok( '/settings/profile' => form => \%fields )->status_is($HTTP_FOUND);
my $stored = $dbh->selectrow_hashref(
q{SELECT display_name,bio,username,status,trust_level,email_normalized FROM users WHERE id=?},
    undef, $owner
);
is(
    $stored->{display_name},
    'Nome pubblico',
    'an ordinary member changes their own display name'
);
is( $stored->{bio}, '<script>alert(1)</script>',
    'biography is saved as plain text' );
is( $stored->{username}, 'profile_writer',
    'login identity is independent of the public name' );
is( $stored->{status}, 'active',
    'submitted administrative fields are ignored' );
is( $stored->{trust_level}, 0, 'profile form cannot elevate trust' );
is(
    $dbh->selectrow_array(
        q{SELECT display_name FROM users WHERE id=?},
        undef, $other
    ),
    'profile_reader',
    'submitted user id cannot select another account'
);
my $payload = $dbh->selectrow_array(
    q{SELECT payload::text FROM command_log WHERE command_id=?},
    undef, $fields{command_id} );
unlike(
    $payload,
    qr/Nome[ ]pubblico|alert[(]1[)]/msx,
    'command responses retain no public profile text'
);
$t->post_ok( '/settings/profile' => form => \%fields )->status_is($HTTP_FOUND);
$t->post_ok( '/settings/profile' => form =>
      { %fields, display_name => 'Conflicting name' } )->status_is($HTTP_FOUND);
is(
    $dbh->selectrow_array(
        q{SELECT display_name FROM users WHERE id=?},
        undef, $owner
    ),
    'Nome pubblico',
    'a command reused with different fields cannot apply a second write'
);
$t->get_ok('/u/profile_writer')->status_is($HTTP_OK);
$t->text_is( 'h1' => 'Nome pubblico' );
$t->element_exists_not('.profile__bio script');
$t->text_is( '.profile__bio p' => '<script>alert(1)</script>' );
$t->post_ok( '/settings/profile' => form =>
      { display_name => 'Denied', bio => q{}, command_id => $ids->uuid } )
  ->status_is($HTTP_FORBIDDEN);

for my $invalid ( q{}, 'x' x $NAME_TOO_LONG, "Bad\nname" ) {
    _save( $invalid, 'must not replace biography' );
    is(
        $dbh->selectrow_array(
            q{SELECT display_name FROM users WHERE id=?},
            undef, $owner
        ),
        'Nome pubblico',
        'invalid name leaves both fields unchanged'
    );
    is(
        $dbh->selectrow_array(
            q{SELECT bio FROM users WHERE id=?},
            undef, $owner
        ),
        '<script>alert(1)</script>',
        'failed update is atomic'
    );
}
_save( 'Valid name', 'x' x $BIO_TOO_LONG );
is(
    $dbh->selectrow_array(
        q{SELECT display_name FROM users WHERE id=?},
        undef, $owner
    ),
    'Nome pubblico',
    'invalid biography cannot partially change the name'
);
_save( '  Altro nome  ', "First\r\n\r\nSecond" );
is(
    $dbh->selectrow_array(
        q{SELECT display_name FROM users WHERE id=?},
        undef, $owner
    ),
    'Altro nome',
    'public name is trimmed'
);
is(
    $dbh->selectrow_array( q{SELECT bio FROM users WHERE id=?}, undef, $owner ),
    "First\n\nSecond",
    'line ends are normalized'
);
my $gate = $t->app->build_controller->gp_identity_store;
ok(
    $gate->update_profile(
        {
            user_id      => $owner,
            display_name => 'Altro nome',
            bio          => "First\n\nSecond"
        }
    )->{skipped},
    'unchanged profile avoids a write'
);
$dbh->do( q{UPDATE users SET status='suspended' WHERE id=?}, undef, $owner );
my $row = $dbh->selectrow_hashref(
    q{SELECT * FROM api.identity_update_profile_v2(?, 'Changed', '')},
    undef, $owner );
ok( !$row, 'SQL refuses a suspended account even when called directly' );
done_testing();

sub _save( $name, $bio ) {
    $t->get_ok('/settings')->status_is($HTTP_OK);
    my $profile_dom = $t->tx->res->dom;
    my $profile     = $profile_dom->at('form[action="/settings/profile"]');
    my %input       = map { $_->attr('name') => $_->attr('value') }
      @{ $profile->find('input[name]')->to_array };
    $t->post_ok( '/settings/profile' => form =>
          { %input, display_name => $name, bio => $bio } )
      ->status_is($HTTP_FOUND);
    return;
}
1;
