# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use JSON::MaybeXS qw(decode_json);
use Scalar::Util  qw(blessed);
use Test::More;

use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Service::Identity::CredentialStore;
use GPForum::Service::Identity::PreferenceStore;
use GPForum::Service::Identity::ProfileReader;
use GPForum::Service::Identity::Support;
use GPForum::Service::Identity::TokenStore;
use GPForum::Test::FixedClock;
use GPForum::Test::PgDatabase;
use GPForum::Test::ScriptedId;
use GPForum::Test::SessionToken;

our $VERSION = '0.001';

const my $ID               => '018f1000-0000-7000-8000-000000000091';
const my $NEXT             => '018f1000-0000-7000-8000-000000000092';
const my $NOW              => '2026-05-23T12:00:00Z';
const my $EPOCH            => 1_779_537_600;
const my $TOKEN_TEXT_INDEX => 3;
const my $OTHER_USER       => 3;
const my $TTL              => 3_600;
const my @LIMITS           => ( 1, 3, 100 );
const my $PAGE_GUARD       => 100;
const my %TIMESTAMP => map { $_ => 1 }
  qw(created_at updated_at expires_at used_at revoked_at calculated_at email_verified_at last_activity_at);

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to compare identity functions';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $schema   = $database->schema;
my $dbh      = $database->dbh;
my $user     = seed_id( user => 2 );
my $other    = seed_id( user => $OTHER_USER );
my $support  = GPForum::Service::Identity::Support->new;
my $clock = GPForum::Test::FixedClock->new( iso8601 => $NOW, epoch => $EPOCH );

_credentials();
_tokens();
_preferences();
_profiles();
_calls();
done_testing();

sub _credentials {
    for my $case (
        [ fresh        => sub { } ],
        [ active       => sub { _credential($user); } ],
        [ id_collision => sub { _credential($other); } ],
        [ revoked_id   => sub { _credential( $user, revoked_at => $NOW ); } ],
        [ other_type   => sub { _credential( $user, type       => 'totp' ); } ],
      )
    {
        _differential(
            "credential create $case->[0]",
            $case->[1],
            sub ($old) {
                return _store( 'CredentialStore', $old )
                  ->create_password_credential(
                    { user_id => $user, secret_hash => 'replacement' } );
            }
        );
    }
    _differential(
        'password rotation locks and revokes before replacement',
        sub { _credential($user); },
        sub ($old) {
            return _store( 'CredentialStore', $old )
              ->rotate_password_credential(
                { user_id => $user, secret_hash => 'replacement' } );
        }
    );
    _differential(
        'future credential creation bounds revocation',
        sub { _credential( $user, created_at => '2026-05-24T12:00:00Z' ); },
        sub ($old) {
            return _store( 'CredentialStore', $old )
              ->rotate_password_credential(
                { user_id => $user, secret_hash => 'replacement' } );
        }
    );
    for my $owner ( $user, $other ) {
        _differential(
            "held password belongs to $owner",
            sub { _credential($user); },
            sub ($old) {
                return _store( 'CredentialStore', $old )
                  ->hold_active_password_credential( $owner, $ID );
            }
        );
    }
    return;
}

sub _tokens {
    for my $case (
        [ fresh => sub { } ],
        [
            id_collision =>
              sub { _token( user_id => $other, token_hash => 'another' ); }
        ],
        [
            hash_collision =>
              sub { _token( token_id => $NEXT, user_id => $other ); }
        ],
        [ reused => sub { _token(); } ],
        [
            rotated =>
              sub { _token( token_id => $NEXT, token_hash => 'prior' ); }
        ],
      )
    {
        _differential(
            "token issue $case->[0]",
            $case->[1],
            sub ($old) {
                return _store( 'TokenStore', $old )->create_token(
                    {
                        user_id     => $user,
                        token_type  => 'password_reset',
                        ttl_seconds => $TTL,
                        metadata    => { mail => 'requested' }
                    }
                );
            }
        );
    }
    for my $case (
        [ valid   => {}, 'password_reset', 'token-1' ],
        [ used    => { used_at    => $NOW }, 'password_reset', 'token-1' ],
        [ expired => { expires_at => $NOW }, 'password_reset', 'token-1' ],
        [
            fraction_expired => { expires_at => '2026-05-23T12:00:00.9Z' },
            'password_reset', 'token-1'
        ],
        [ wrong_type => {}, 'email_change',   'token-1' ],
        [ missing    => {}, 'password_reset', 'absent' ],
      )
    {
        _differential(
            "token consume $case->[0]",
            sub { _token( %{ $case->[1] } ); },
            sub ($old) {
                return _store( 'TokenStore', $old )
                  ->consume_token( $case->[2], $case->[$TOKEN_TEXT_INDEX] );
            }
        );
    }
    return;
}

sub _preferences {
    for my $case (
        [ update_preferred_locale => { preferred_locale => 'it' } ],
        [ update_preferred_locale => { preferred_locale => 'en' } ],
        [ update_preferred_locale => { preferred_locale => q{ } } ],
        [ update_preferred_theme  => { preferred_theme  => 'dark' } ],
        [
            update_preferred_timezone => { preferred_timezone => 'Europe/Rome' }
        ],
        [ update_preferred_timezone => { preferred_timezone => q{ } } ],
        [ update_preferred_timezone => { preferred_timezone => 'bad/zone' } ],
      )
    {
        my ( $method, $input ) = @{$case};
        _differential(
            "preference $method/$input->{(keys %{$input})[0]}",
            sub { },
            sub ($old) {
                return _store( 'PreferenceStore', $old )
                  ->$method( { user_id => $user, %{$input} } );
            }
        );
    }
    return;
}

sub _profiles {
    my %path = (
        old => _store( 'ProfileReader', 1 ),
        new => _store( 'ProfileReader', 0 )
    );
    my $username =
      $dbh->selectrow_array( 'SELECT username FROM users WHERE id = ?',
        undef, $user );
    for my $visibility (qw(public members private)) {
        $schema->txn_begin;
        $dbh->do( 'UPDATE spaces SET visibility = ? WHERE space_id = ?',
            undef, $visibility, seed_id( space => 1 ) );
        for my $limit (@LIMITS) {
            my $after;
            for my $page ( 1 .. $PAGE_GUARD ) {
                my $options = { limit => $limit, after => $after };
                my $old     = $path{old}->public_profile( $username, $options );
                my $new     = $path{new}->public_profile( $username, $options );
                is_deeply( _normalize($new), _normalize($old),
                    "profile $visibility/$limit page $page" );
                $after = $new->{profile}{threads}{next_cursor};
                last if !$after;
                if ( $page == $PAGE_GUARD ) {
                    fail('profile pagination terminates');
                }
            }
        }
        $schema->txn_rollback;
    }
    for my $status (qw(active pending suspended deleted)) {
        $schema->txn_begin;
        $dbh->do( 'UPDATE users SET status = ? WHERE id = ?',
            undef, $status, $user );
        is_deeply(
            _normalize( $path{new}->public_profile( " $username ", {} ) ),
            _normalize( $path{old}->public_profile( " $username ", {} ) ),
            "public profile status $status"
        );
        $schema->txn_rollback;
    }
    return;
}

sub _calls {
    $schema->txn_begin;
    $dbh->do( 'DELETE FROM credentials WHERE user_id = ?', undef, $user );
    my @statements;
    $schema->storage->debugcb(
        sub ( $kind, $statement ) { push @statements, $statement; } );
    $schema->storage->debug(1);
    _store( 'CredentialStore', 0 )
      ->create_password_credential(
        { user_id => $user, secret_hash => 'check' } );
    _store( 'TokenStore', 0 )->create_token(
        {
            user_id     => $user,
            token_type  => 'password_reset',
            ttl_seconds => $TTL
        }
    );
    _store( 'TokenStore', 0 )->consume_token( 'password_reset', 'token-1' );
    _store( 'PreferenceStore', 0 )
      ->update_preferred_locale(
        { user_id => $user, preferred_locale => 'it' } );
    _store( 'ProfileReader', 0 )->public_profile(
        $dbh->selectrow_array(
            'SELECT username FROM users WHERE id = ?',
            undef, $user
        ),
        {}
    );
    $schema->storage->debug(0);
    $schema->storage->debugcb(undef);
    ok( @statements, 'identity operations are traced' );
    is_deeply(
        [
            grep {
                     !/\A SELECT [ ] [*] [ ] FROM [ ] api[.]/msx
                  && !/\A (?:SAVEPOINT|RELEASE|ROLLBACK) /msx
            } @statements
        ],
        [],
        'every traced identity data statement is a fixed API call'
    );
    $schema->txn_rollback;
    return;
}

sub _differential ( $label, $fixture, $operation ) {
    subtest $label => sub {
        my @runs;
        for my $old ( 1, 0 ) {
            $schema->txn_begin;
            $dbh->do( 'DELETE FROM credentials WHERE user_id IN (?, ?)',
                undef, $user, $other );
            $dbh->do( 'DELETE FROM identity_tokens WHERE user_id IN (?, ?)',
                undef, $user, $other );
            $fixture->();
            my $answer = $operation->($old);
            push @runs,
              {
                answer => _normalize($answer),
                state  => _normalize(
                    {
                        credentials => $dbh->selectall_arrayref(
'SELECT * FROM credentials WHERE user_id IN (?, ?) ORDER BY id',
                            { Slice => {} },
                            $user,
                            $other
                        ),
                        tokens => $dbh->selectall_arrayref(
'SELECT * FROM identity_tokens WHERE user_id IN (?, ?) ORDER BY token_id',
                            { Slice => {} },
                            $user,
                            $other
                        ),
                        user => $dbh->selectrow_hashref(
                            'SELECT * FROM users WHERE id = ?', undef,
                            $user
                        ),
                    }
                )
              };
            $schema->txn_rollback;
        }
        is_deeply( $runs[1], $runs[0], 'answer and every persisted row agree' );
    };
    return;
}

sub _store ( $kind, $old ) {
    my $class = 'GPForum::Service::Identity::' . $kind;
    my %args  = ( schema => $schema, ( $old ? ( functions => undef ) : () ) );
    if ( $kind eq 'CredentialStore' || $kind eq 'TokenStore' ) {
        $args{id_service} =
          GPForum::Test::ScriptedId->new( next_ids => [ $ID, $NEXT ] );
        $args{clock} = $clock;
    }
    if ( $kind eq 'TokenStore' ) {
        $args{session_tokens} = GPForum::Test::SessionToken->new;
    }
    if ( $kind eq 'PreferenceStore' ) { $args{clock} = $clock; }
    return $class->new(%args);
}

sub _credential ( $owner, %changes ) {
    my %row = (
        id          => $ID,
        user_id     => $owner,
        type        => 'password',
        secret_hash => 'prior',
        created_at  => $NOW,
        revoked_at  => undef,
        %changes,
    );
    $schema->resultset('Credential')->create( \%row );
    return;
}

sub _token (%changes) {
    my %row = (
        token_id   => $ID,
        user_id    => $user,
        token_type => 'password_reset',
        token_hash => 'hash:token-1',
        created_at => '2026-05-23T10:00:00Z',
        expires_at => '2026-05-23T13:00:00Z',
        used_at    => undef,
        metadata   => {},
        %changes,
    );
    $schema->resultset('IdentityToken')->create( \%row );
    return;
}

sub _normalize ( $value, $key = q{} ) {
    if ( blessed $value && $value->can('get_columns') ) {
        $value = { $value->get_columns };
    }
    if ( ref $value eq 'ARRAY' ) {
        return [ map { _normalize($_) } @{$value} ];
    }
    if ( ref $value eq 'HASH' ) {
        return { map { $_ => _normalize( $value->{$_}, $_ ) } keys %{$value} };
    }
    if ( exists $TIMESTAMP{$key} && defined $value ) {
        return $support->epoch_from_timestamp($value);
    }
    if ( $key eq 'metadata' && defined $value && !ref $value ) {
        return decode_json($value);
    }
    return $value;
}

1;
