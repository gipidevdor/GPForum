# SPDX-FileCopyrightText: 2026 GPForum Contributors
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
const my $LISTED           => 100;
const my $PRIOR            => 'id user password prior now -';
const my $REPLACEMENT      => 'next user password replacement now -';
const my $SEEDED_USER      => 'user en auto - seeded';
const my $TOKEN_ROW        => 'id user password_reset hash:token-1 - now-7200';
const my $ISSUED => {
    expires_at => 'now+3600',
    raw_token  => 'token-1',
    row        =>
      'id user password_reset hash:token-1 - now now+3600 - mail=requested',
    token_hash => 'hash:token-1',
    token_id   => 'id'
};

const my %TIMESTAMP => map { $_ => 1 }
  qw(created_at updated_at expires_at used_at revoked_at calculated_at email_verified_at last_activity_at);

# The identity stores are written once (ADR 0177): each case states the
# answer and the credential, token and user rows it leaves. The public
# profile is compared with the resultset its thread function stands for.
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

# The ids and times the stated rows name, short (_lines).
my %NAME = ( $ID => 'id', $NEXT => 'next', $user => 'user', $other => 'other' );
my $SEEDED_AT = $support->epoch_from_timestamp(
    $dbh->selectrow_array(
        'SELECT updated_at FROM users WHERE id = ?',
        undef, $user
    )
);

_credentials();
_tokens();
_preferences();
_profiles();
_profile_replies();
_calls();
done_testing();

sub _credentials {
    for my $case (
        [
            fresh => sub { },
            'id user password replacement now -',
            ['id user password replacement now -']
        ],
        [
            active => sub { _credential($user); },
            "$PRIOR skipped", [$PRIOR]
        ],
        [
            id_collision => sub { _credential($other); },
            $REPLACEMENT, [ 'id other password prior now -', $REPLACEMENT ]
        ],
        [
            revoked_id => sub { _credential( $user, revoked_at => $NOW ); },
            $REPLACEMENT, [ 'id user password prior now now', $REPLACEMENT ]
        ],
        [
            other_type => sub { _credential( $user, type => 'totp' ); },
            $REPLACEMENT, [ 'id user totp prior now -', $REPLACEMENT ]
        ],
      )
    {
        my ( $name, $fixture, $answer, $credentials ) = @{$case};
        _stated(
            "credential create $name",
            $fixture,
            sub {
                return _store('CredentialStore')
                  ->create_password_credential(
                    { user_id => $user, secret_hash => 'replacement' } );
            },
            { answer => $answer, credentials => $credentials }
        );
    }
    for my $case (
        [
            'password rotation locks and revokes before replacement',
            sub { _credential($user); },
            'id user password prior now now'
        ],
        [
            'future credential creation bounds revocation',
            sub {
                _credential( $user, created_at => '2026-05-24T12:00:00Z' );
            },
            'id user password prior now+86400 now+86400'
        ],
      )
    {
        _stated(
            $case->[0],
            $case->[1],
            sub {
                return _store('CredentialStore')
                  ->rotate_password_credential(
                    { user_id => $user, secret_hash => 'replacement' } );
            },
            {
                answer      => $REPLACEMENT,
                credentials => [ $case->[2], $REPLACEMENT ]
            }
        );
    }
    for my $owner ( [ $user, $PRIOR ], [ $other, q{-} ] ) {
        _stated(
            "held password belongs to $NAME{ $owner->[0] }",
            sub { _credential($user); },
            sub {
                return _store('CredentialStore')
                  ->hold_active_password_credential( $owner->[0], $ID );
            },
            { answer => $owner->[1], credentials => [$PRIOR] }
        );
    }
    return;
}

sub _tokens {
    my $reissued = "$TOKEN_ROW now+3600 - ";
    for my $case (
        [ fresh => sub { }, $ISSUED, [ $ISSUED->{row} ] ],
        [
            id_collision =>
              sub { _token( user_id => $other, token_hash => 'another' ); },
            {
                %{$ISSUED},
                row => 'next user password_reset hash:token-1 - now now+3600'
                  . ' - mail=requested',
                token_id => 'next'
            },
            [
                'id other password_reset another - now-7200 now+3600 - ',
                'next user password_reset hash:token-1 - now now+3600'
                  . ' - mail=requested'
            ]
        ],
        [
            hash_collision =>
              sub { _token( token_id => $NEXT, user_id => $other ); },
            {
                %{$ISSUED},
                raw_token => 'token-2',
                row => 'id user password_reset hash:token-2 - now now+3600'
                  . ' - mail=requested',
                token_hash => 'hash:token-2'
            },
            [
                'id user password_reset hash:token-2 - now now+3600'
                  . ' - mail=requested',
                'next other password_reset hash:token-1 - now-7200 now+3600 - '
            ]
        ],
        [
            reused => sub { _token(); },
            {
                row        => $reissued,
                skipped    => 1,
                token_hash => 'hash:token-1',
                token_id   => 'id'
            },
            [$reissued]
        ],
        [
            rotated =>
              sub { _token( token_id => $NEXT, token_hash => 'prior' ); },
            {
                %{$ISSUED},
                rotated => 1,
                row     => 'next user password_reset hash:token-1 - now-7200'
                  . ' now+3600 - mail=requested',
                token_id => 'next'
            },
            [
                    'next user password_reset hash:token-1 - now-7200 now+3600'
                  . ' - mail=requested'
            ]
        ],
      )
    {
        my ( $name, $fixture, $answer, $tokens ) = @{$case};
        _stated(
            "token issue $name",
            $fixture,
            sub {
                return _store('TokenStore')->create_token(
                    {
                        user_id     => $user,
                        token_type  => 'password_reset',
                        ttl_seconds => $TTL,
                        metadata    => { mail => 'requested' }
                    }
                );
            },
            { answer => $answer, tokens => $tokens }
        );
    }
    _token_spending();
    return;
}

# Who a token belongs to, read without deciding whether it can be used, and
# what spending it answers: only a valid one is marked used.
sub _token_spending {
    my $live    = "$TOKEN_ROW now+3600 - ";
    my $used    = "$TOKEN_ROW now+3600 now ";
    my $expired = "$TOKEN_ROW now - ";
    my %refused = map { $_ => { error => $_, ok => 0 } }
      qw(token_used token_expired invalid_token);
    for my $case (
        [
            valid => {},
            'password_reset',
            'token-1',
            'user',
            {
                email_normalized => q{-},
                ok               => 1,
                row              => $used,
                token_id         => 'id',
                user_id          => 'user'
            },
            $live,
            $used
        ],
        [
            used => { used_at => $NOW },
            'password_reset', 'token-1', 'user', $refused{token_used}, $used,
            $used
        ],
        [
            expired => { expires_at => $NOW },
            'password_reset', 'token-1', 'user', $refused{token_expired},
            $expired,         $expired
        ],
        [
            fraction_expired => { expires_at => '2026-05-23T12:00:00.9Z' },
            'password_reset', 'token-1', 'user', $refused{token_expired},
            $expired,         $expired
        ],
        [
            wrong_type => {},
            'email_change', 'token-1', q{-}, $refused{invalid_token}, $live,
            $live
        ],
        [
            missing => {},
            'password_reset', 'absent', q{-}, $refused{invalid_token}, $live,
            $live
        ],
      )
    {
        my ( $name, $changes, $type, $raw, $owner, $consumed, $read, $spent ) =
          @{$case};
        _stated(
            "token owner $name",
            sub { _token( %{$changes} ); },
            sub {
                return _store('TokenStore')->token_user_id( $type, $raw );
            },
            { answer => $owner, tokens => [$read] }
        );
        _stated(
            "token consume $name",
            sub { _token( %{$changes} ); },
            sub {
                return _store('TokenStore')->consume_token( $type, $raw );
            },
            { answer => $consumed, tokens => [$spent] }
        );
    }
    return;
}

sub _preferences {
    my $changed = sub ( $column, $value, $line ) {
        return ( { ok => 1, $column => $value, user => $line }, $line );
    };
    for my $case (
        [
            update_preferred_locale => { preferred_locale => 'it' },
            $changed->( preferred_locale => 'it', 'user it auto - now' )
        ],
        [
            update_preferred_locale => { preferred_locale => 'en' },
            {
                ok               => 1,
                preferred_locale => 'en',
                skipped          => 1,
                user             => $SEEDED_USER
            },
            $SEEDED_USER
        ],
        [
            update_preferred_locale => { preferred_locale => q{ } },
            { error => 'locale_required', ok => 0 }, $SEEDED_USER
        ],
        [
            update_preferred_theme => { preferred_theme => 'dark' },
            $changed->( preferred_theme => 'dark', 'user en dark - now' )
        ],
        [
            update_preferred_timezone =>
              { preferred_timezone => 'Europe/Rome' },
            $changed->(
                preferred_timezone => 'Europe/Rome',
                'user en auto Europe/Rome now'
            )
        ],
        [
            update_preferred_timezone => { preferred_timezone => q{ } },
            {
                ok                 => 1,
                preferred_timezone => q{-},
                skipped            => 1,
                user               => $SEEDED_USER
            },
            $SEEDED_USER
        ],
        [
            update_preferred_timezone => { preferred_timezone => 'bad/zone' },
            { error => 'timezone_invalid', ok => 0 }, $SEEDED_USER
        ],
      )
    {
        my ( $method, $input, $answer, $stored ) = @{$case};
        _stated(
            "preference $method/$input->{(keys %{$input})[0]}",
            sub { },
            sub {
                return _store('PreferenceStore')
                  ->$method( { user_id => $user, %{$input} } );
            },
            { answer => $answer, user => $stored }
        );
    }
    return;
}

# Each page of the profile's threads is the page the evidence resultset
# reads, in every visibility of the space and at every limit, and the
# counts are what the pages hold. Suspended members have no profile; a
# deleted one is hidden by deleted_at, which the status alone does not set.
sub _profiles {
    my $reader = _store('ProfileReader');
    my $username =
      $dbh->selectrow_array( 'SELECT username FROM users WHERE id = ?',
        undef, $user );
    for my $visibility (qw(public members private)) {
        $schema->txn_begin;
        $dbh->do( 'UPDATE spaces SET visibility = ? WHERE space_id = ?',
            undef, $visibility, seed_id( space => 1 ) );
        for my $limit (@LIMITS) {
            my ( $after, $listed, $counts );
            for my $page ( 1 .. $PAGE_GUARD ) {
                my $options = { limit => $limit, after => $after };
                my $profile = $reader->public_profile( $username, $options );
                $counts //= $profile->{profile}{counts};
                is_deeply(
                    [
                        map { $_->{thread_id} }
                          @{ $profile->{profile}{threads}{items} }
                    ],
                    _evidence( $reader, $options ),
                    "profile $visibility/$limit page $page"
                );
                $listed += @{ $profile->{profile}{threads}{items} };
                $after = $profile->{profile}{threads}{next_cursor};
                last if !$after;
                if ( $page == $PAGE_GUARD ) {
                    fail('profile pagination terminates');
                }
            }
            is( $counts->{public_threads},
                $listed,
                "profile $visibility/$limit counts the threads it pages" );
        }
        $schema->txn_rollback;
    }
    my %found = ( active => 1, pending => 1, suspended => 0, deleted => 1 );
    for my $status (qw(active pending suspended deleted)) {
        $schema->txn_begin;
        $dbh->do( 'UPDATE users SET status = ? WHERE id = ?',
            undef, $status, $user );
        my $profile = $reader->public_profile( " $username ", {} );
        is( $profile->{ok} ? 1 : 0,
            $found{$status}, "public profile status $status" );
        if ( !$found{$status} ) {
            is( $profile->{error}, 'not_found', 'answered as not found' );
        }
        $schema->txn_rollback;
    }
    return;
}

# The replies a profile lists are the member's public, visible posts after
# the opening one: a reply hidden by moderation or made private leaves the
# list and the count, and no opening post is ever listed.
sub _profile_replies {
    my $reader = _store('ProfileReader');
    my $username =
      $dbh->selectrow_array( 'SELECT username FROM users WHERE id = ?',
        undef, $user );
    my $read = sub {
        my $profile =
          $reader->public_profile( $username, { limit => $LISTED } )->{profile};
        return ( $profile->{counts}{public_replies},
            [ map { $_->{post_id} } @{ $profile->{replies}{items} } ] );
    };
    $schema->txn_begin;
    my ( $count, $listed ) = $read->();
    cmp_ok( scalar @{$listed}, q{>=}, 2, 'the member has replies to hide' );
    my ( $hidden, $private ) = @{$listed};
    is_deeply(
        $dbh->selectcol_arrayref(
            'SELECT post_id FROM posts WHERE position = 1 AND post_id = ANY(?)',
            undef,
            $listed
        ),
        [],
        'no opening post is listed as a reply'
    );
    $dbh->do( q{UPDATE posts SET moderation_state = 'hidden' WHERE post_id = ?},
        undef, $hidden );
    $dbh->do( q{UPDATE posts SET visibility = 'private' WHERE post_id = ?},
        undef, $private );
    my ( $after, $remaining ) = $read->();
    is( $after, $count - 2,
        'the hidden and the private reply are not counted' );
    ok( !( grep { $_ eq $hidden || $_ eq $private } @{$remaining} ),
        'and not listed' );
    $schema->txn_rollback;
    return;
}

# The thread ids the evidence resultset reads for a page of the profile.
sub _evidence ( $reader, $options ) {
    my $plan = $reader->page_window->plan(
        {
            limit => $options->{limit},
            after => $options->{after},
            sort  => 'timestamp',
        }
    );
    my @ids =
      map { $_->get_column('thread_id') }
      $reader->public_threads_resultset( $user, $plan )->all;
    if ( @ids > $plan->{limit} ) { splice @ids, $plan->{limit}; }
    return \@ids;
}

sub _calls {
    $schema->txn_begin;
    $dbh->do( 'DELETE FROM credentials WHERE user_id = ?', undef, $user );
    my @statements;
    $schema->storage->debugcb(
        sub ( $kind, $statement ) { push @statements, $statement; } );
    $schema->storage->debug(1);
    _store('CredentialStore')
      ->create_password_credential(
        { user_id => $user, secret_hash => 'check' } );
    _store('TokenStore')->create_token(
        {
            user_id     => $user,
            token_type  => 'password_reset',
            ttl_seconds => $TTL
        }
    );
    _store('TokenStore')->consume_token( 'password_reset', 'token-1' );
    _store('PreferenceStore')
      ->update_preferred_locale(
        { user_id => $user, preferred_locale => 'it' } );
    _store('ProfileReader')->public_profile(
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

sub _stated ( $label, $fixture, $operation, $expected ) {
    subtest $label => sub {
        $schema->txn_begin;
        $dbh->do( 'DELETE FROM credentials WHERE user_id IN (?, ?)',
            undef, $user, $other );
        $dbh->do( 'DELETE FROM identity_tokens WHERE user_id IN (?, ?)',
            undef, $user, $other );
        $fixture->();
        my $answer = $operation->();
        my %state  = (
            credentials => $dbh->selectall_arrayref(
                'SELECT * FROM credentials WHERE user_id IN (?, ?) ORDER BY id',
                { Slice => {} },
                $user,
                $other
            ),
            tokens => $dbh->selectall_arrayref(
                'SELECT * FROM identity_tokens WHERE user_id IN (?, ?)'
                  . ' ORDER BY token_id',
                { Slice => {} },
                $user,
                $other
            ),
            user => $dbh->selectrow_hashref(
                'SELECT * FROM users WHERE id = ?',
                undef, $user
            ),
        );
        $schema->txn_rollback;
        is_deeply(
            _lines( _normalize( { answer => $answer, %state } ) ),
            {
                credentials => [],
                tokens      => [],
                user        => $SEEDED_USER,
                %{$expected}
            },
            'the answer and every persisted row'
        );
    };
    return;
}

# A row, or a value holding rows, as one line per row: a token's, a
# credential's or a member's columns, the ids named and the times relative
# to the clock's now.
sub _lines ($value) {
    return _short($value)                   if !ref $value;
    return [ map { _lines($_) } @{$value} ] if ref $value eq 'ARRAY';
    my @columns = exists $value->{token_type}
      ? qw(token_id user_id token_type token_hash email_normalized created_at
      expires_at used_at metadata)
      : exists $value->{secret_hash}
      ? qw(id user_id type secret_hash created_at revoked_at)
      : exists $value->{username}
      ? qw(id preferred_locale preferred_theme preferred_timezone updated_at)
      : ();
    return { map { $_ => _lines( $value->{$_} ) } keys %{$value} }
      if !@columns;

    my $line = join q{ }, map { _short( $value->{$_} ) } @columns;
    return $value->{skipped} ? "$line skipped" : $line;
}

sub _short ($value) {
    return q{-} if !defined $value;
    return join q{,}, map { "$_=$value->{$_}" } sort keys %{$value}
      if ref $value eq 'HASH';
    return $NAME{$value} if exists $NAME{$value};
    return 'seeded'      if $value eq $SEEDED_AT;
    return $value        if $value !~ /\A \d{10} \z/msx;
    my $offset = $value - $EPOCH;
    return $offset ? sprintf 'now%+d', $offset : 'now';
}

sub _store ($kind) {
    my $class = 'GPForum::Service::Identity::' . $kind;
    my %args  = ( schema => $schema );
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
