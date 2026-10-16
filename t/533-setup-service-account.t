# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use English    qw(-no_match_vars);
use File::Temp qw(tempdir);
use IO::Socket::UNIX;
use Socket qw(SOL_SOCKET);
use Test::More;

use lib 'lib';

use GPForum::OS;
use GPForum::Service::Operations::ServiceAccount;

our $VERSION = '0.001';

const my $PRIVATE                 => oct '750';
const my $MODE_BITS               => oct '777';
const my $FREE_ID                 => 499;
const my $SOCKET_ACCESS           => oct '777';
const my $SOCKET_DIRECTORY_ACCESS => oct '755';

# ADR 0122: gpforum setup, run as root, makes the account the services run
# as where the system has one command for it -- useradd on Linux, pw on
# FreeBSD -- and on macOS says to make it by hand.

my $class = 'GPForum::Service::Operations::ServiceAccount';

subtest q{each system's command, or none} => sub {
    is_deeply(
        $class->new( os => GPForum::OS->from_name('linux') )
          ->commands('/opt/gpforum'),
        [
            [
                qw(useradd --system --user-group --home-dir /opt/gpforum),
                qw(--shell /usr/sbin/nologin gpforum)
            ]
        ],
        q{Linux: useradd, as docs/DEPLOYMENT.md typed it}
    );
    is_deeply(
        $class->new( os => GPForum::OS->from_name('freebsd') )
          ->commands('/usr/local/www/gpforum'),
        [
            [
                qw(pw useradd gpforum -d /usr/local/www/gpforum),
                qw(-s /usr/sbin/nologin -c GPForum)
            ]
        ],
        'FreeBSD: pw, which makes the group too'
    );
    my $mac = GPForum::OS->from_name('darwin')->account_id($FREE_ID);
    is_deeply(
        $class->new( os => $mac )->commands('/opt/gpforum'),
        [
            (
                map { [ qw(dscl . -create /Groups/gpforum), @{$_} ] }
                  [ 'PrimaryGroupID', $FREE_ID ],
                [qw(RealName GPForum)],
                [ 'Password', q{*} ]
            ),
            (
                map { [ qw(dscl . -create /Users/gpforum), @{$_} ] }
                  [ 'UniqueID', $FREE_ID ],
                [ 'PrimaryGroupID', $FREE_ID ],
                [qw(UserShell /usr/bin/false)],
                [qw(NFSHomeDirectory /var/empty)],
                [qw(RealName GPForum)],
                [ 'Password', q{*} ],
                [qw(IsHidden 1)]
            ),
        ],
        'macOS: dscl, the group and the account under one free id'
    );
    is_deeply(
        $class->new(
            os => GPForum::OS->from_name('darwin')->account_id(undef)
        )->commands('/opt/gpforum'),
        [],
        'and none when every id under 500 is taken'
    );
};

subtest 'the commands are run, and a failure says which' => sub {
    my @ran;
    my $account = $class->new(
        os  => GPForum::OS->from_name('linux'),
        run => sub (@command) { push @ran, [@command]; return undef; },
    );
    is( $account->make('/opt/gpforum'), undef,     'made' );
    is( $ran[0][0],                     'useradd', 'with useradd' );

    my $failed = $class->new(
        os  => GPForum::OS->from_name('linux'),
        run => sub (@command) { return 'it exited 9'; },
    )->make('/opt/gpforum');
    like(
        $failed->{command},
        qr/\A useradd [ ] --system/msx,
        'the command that failed'
    );
    is( $failed->{reason}, 'it exited 9', 'and why' );
};

subtest 'the uploads directory is made for the account' => sub {
    my $name    = getpwuid $EFFECTIVE_USER_ID;
    my $account = $class->new( name => $name );
    my ( $uid, $gid ) = $account->ids;
    is( $uid, $EFFECTIVE_USER_ID, q{an account's ids} );

    my $root = tempdir( CLEANUP => 1 );
    my $made = $account->make_directory("$root/var/attachments");
    is_deeply(
        $made,
        [ "$root/var", "$root/var/attachments" ],
        'each directory missing, from the top'
    );
    is( ( stat "$root/var/attachments" )[2] & $MODE_BITS,
        $PRIVATE, 'readable by its group and nobody else' );
    is_deeply( $account->make_directory("$root/var/attachments"),
        [], 'and nothing the second time' );

    ok(
        !$class->new( name => 'no-such-account-530' )->ids,
        'an account that does not exist has no ids'
    );
};

subtest 'a callback can use the current account' => sub {
    my $account = $class->new( name => scalar getpwuid $EFFECTIVE_USER_ID );
    is( $account->with_identity( sub { return $EFFECTIVE_USER_ID; } ),
        $EFFECTIVE_USER_ID, 'the current identity needs no privilege change' );
};

subtest 'root restores its identity after success and failure' => sub {
    if ( $EFFECTIVE_USER_ID != 0 || !defined getpwnam 'nobody' ) {
        plan skip_all => 'requires root and the unprivileged nobody account';
    }
    my $account = $class->new( name => 'nobody' );
    my ( $uid, $gid ) = $account->ids;
    my $groups = "$EFFECTIVE_GROUP_ID";
    my $inside = $account->with_identity(
        sub {
            return [ $EFFECTIVE_USER_ID,
                ( split q{ }, $EFFECTIVE_GROUP_ID )[0] ];
        }
    );
    is_deeply(
        $inside,
        [ $uid, $gid ],
        'the callback uses the service identity'
    );
    is( $EFFECTIVE_USER_ID,    0,       'the caller uid is restored' );
    is( "$EFFECTIVE_GROUP_ID", $groups, 'the caller groups are restored' );
    my $error;
    try {
        $account->with_identity( sub { croak 'identity test failure'; } );
    }
    catch ($caught) { $error = "$caught"; };
    like(
        $error,
        qr/identity[ ]test[ ]failure/msx,
        'the callback error is preserved'
    );
    is( $EFFECTIVE_USER_ID, 0,
        'the caller uid is restored after an exception' );
    is( "$EFFECTIVE_GROUP_ID", $groups,
        'the caller groups are restored after an exception' );
};

subtest 'Unix socket credentials carry the service uid' => sub {
    if ( $EFFECTIVE_USER_ID != 0 || !defined getpwnam 'nobody' ) {
        plan skip_all => 'requires root and the unprivileged nobody account';
    }
    my $option;
    try { $option = Socket::SO_PEERCRED(); }
    catch ($error) { $option = undef; };
    if ( !defined $option ) {
        plan skip_all => 'SO_PEERCRED is unavailable on this host';
    }
    my $root = tempdir( 'gpforum-peer-XXXXXX', DIR => '/tmp', CLEANUP => 1 );
    chmod $SOCKET_DIRECTORY_ACCESS, $root or croak "chmod: $OS_ERROR";
    my $socket   = "$root/peer.sock";
    my $listener = IO::Socket::UNIX->new( Local => $socket, Listen => 1 )
      or croak "listen: $OS_ERROR";
    chmod $SOCKET_ACCESS, $socket or croak "chmod: $OS_ERROR";
    my $account = $class->new( name => 'nobody' );
    my $client  = $account->with_identity(
        sub {
            return IO::Socket::UNIX->new( Peer => $socket )
              // croak "connect: $OS_ERROR";
        }
    );
    my $accepted    = $listener->accept // croak "accept: $OS_ERROR";
    my $credentials = getsockopt $accepted, SOL_SOCKET, $option;
    croak "peer credentials: $OS_ERROR" if !defined $credentials;
    my ( undef, $uid, $gid ) = unpack 'iII', $credentials;
    is_deeply(
        [ $uid, $gid ],
        [ $account->ids ],
'the kernel reports the effective service identity used by peer authentication'
    );
    is( $EFFECTIVE_USER_ID, 0, 'the setup process is root again' );
};

done_testing();

1;
