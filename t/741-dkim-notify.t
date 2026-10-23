# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Const::Fast;
use Test::More;
use Carp qw(croak);
use IO::Select;
use Socket qw(AF_UNIX SOCK_DGRAM sockaddr_un);
use Crypt::OpenSSL::RSA;
use Email::Simple;
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Mail::DKIM::Verifier;
use Net::DNS::RR;
use GPForum::Config;
use GPForum::Service::Identity::Dkim;
use GPForum::OS::SystemdNotify;
use lib 't/lib';
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
our $VERSION = '0.001';

const my $PRIVATE_MODE  => oct '600';
const my $PUBLIC_MODE   => oct '644';
const my $RSA_BITS      => 2048;
const my $MESSAGE_BYTES => 4096;

{

    package GPForum::Test::Notify;    ## no critic (Modules::ProhibitMultiplePackages) -- scoped notifier test double
    use Mojo::Base 'GPForum::OS::SystemdNotify', -signatures;
    use v5.40;
    has messages => sub { return [] };

    sub notify ( $self, $message ) {
        push @{ $self->messages }, $message;
        return true;
    }
}
{

    package GPForum::Test::Prefork;    ## no critic (Modules::ProhibitMultiplePackages) -- scoped prefork test double
    use Mojo::Base 'Mojo::Server::Prefork', -signatures;
    use v5.40;
    has available => 0;
    sub healthy ($self) { return $self->available; }
}

subtest 'notification is a real Unix datagram' => sub {
    my $directory   = tempdir( CLEANUP => 1 );
    my $socket_path = "$directory/notify";
    socket my $receiver, AF_UNIX, SOCK_DGRAM, 0 or croak 'cannot open receiver';
    bind $receiver, sockaddr_un($socket_path) or croak 'cannot bind receiver';
    my $notifier =
      GPForum::OS::SystemdNotify->new( socket_path => $socket_path );
    ok( $notifier->notify("READY=1\nWATCHDOG=1"), 'notification sent' );
    ok( IO::Select->new($receiver)->can_read(2),  'notification readable' );
    defined( recv $receiver, my $message, $MESSAGE_BYTES, 0 )
      or croak 'cannot receive notification';
    is( $message, "READY=1\nWATCHDOG=1", 'payload matches systemd protocol' );
    close $receiver or croak 'cannot close receiver';
};

subtest 'manager and worker readiness both gate notifications' => sub {
    local $ENV{WATCHDOG_PID} = undef;
    my $answers = 0;
    my @paths;
    my $notify = GPForum::Test::Notify->new(
        socket_path => '/unused',
        interval    => 0,
        probe => sub ( $listen, $path ) { push @paths, $path; return $answers; }
    );
    my $server = GPForum::Test::Prefork->new( cleanup => 0 );
    ok( $notify->attach( $server, 'http://127.0.0.1' ),
        'attached to manager events' );
    $server->emit('wait');
    is_deeply( $notify->messages, [], 'no heartbeat: no ready or watchdog' );
    $server->available(1)->emit('wait');
    is_deeply( $notify->messages, [],
        'heartbeat without HTTP response is insufficient' );
    $answers = 1;
    $server->emit('wait');
    is( scalar @{ $notify->messages },
        2, 'HTTP response triggers ready and watchdog' );
    like( $notify->messages->[0], qr/READY=1/msx, 'ready first' );
    is( $paths[-1], '/health/ready', 'startup requires operational readiness' );
    $server->emit('wait');
    is( $paths[-1], '/health/live',
        'watchdog checks the serving loop after startup' );
    is( scalar( grep { /READY=1/msx } @{ $notify->messages } ),
        1, 'ready only once' );
    $answers = 0;
    my $count = @{ $notify->messages };
    $server->emit('wait');
    is( scalar @{ $notify->messages },
        $count, 'no watchdog when HTTP stops answering' );
};

subtest 'DKIM survives serialization and covers one-click unsubscribe' => sub {
    my $directory = path( tempdir( CLEANUP => 1 ) );
    my $key       = Crypt::OpenSSL::RSA->generate_key($RSA_BITS);
    my $file =
      $directory->child('private.pem')
      ->spew( $key->get_private_key_string )
      ->chmod($PRIVATE_MODE);
    my $public = $key->get_public_key_x509_string;
    $public =~ s/-----[^\n]+-----|\s//gmsx;
    my $config = GPForum::Config->new(
        dkim_key_file => "$file",
        dkim_domain   => 'forum.test',
        dkim_selector => 'forum',
        mail_from     => 'forum@forum.test'
    );
    my $dkim  = GPForum::Service::Identity::Dkim->new( config => $config );
    my $email = Email::Simple->create(
        header => [
            From                    => 'forum@forum.test',
            To                      => 'member@example.invalid',
            Subject                 => 'Hello',
            'List-Unsubscribe'      => '<https://forum.test/unsubscribe>',
            'List-Unsubscribe-Post' => 'List-Unsubscribe=One-Click'
        ],
        body => "Message\n"
    );
    my $signed = $dkim->sign($email);
    like( $signed->header('DKIM-Signature'),
        qr/list-unsubscribe-post/imsx, 'one-click header is signed' );
    with_replaced_subs(
        'Mail::DKIM::DNS',
        {
            query => sub {
                return Net::DNS::RR->new(
"forum._domainkey.forum.test IN TXT \"v=DKIM1; k=rsa; p=$public\""
                );
            }
        },
        sub {
            my $verifier = Mail::DKIM::Verifier->new;
            $verifier->PRINT( $signed->as_string );
            $verifier->CLOSE;
            is( $verifier->result, 'pass',
                'serialized message verifies with DNS public key' );
            is( $dkim->check->{status},
                'ok', 'doctor verifies a probe without sending' );
            $signed->body_set("Modified\r\n");
            $verifier = Mail::DKIM::Verifier->new;
            $verifier->PRINT( $signed->as_string );
            $verifier->CLOSE;
            isnt( $verifier->result, 'pass',
                'body tampering fails verification' );
        }
    );
    $file->chmod($PUBLIC_MODE);
    my $error;
    try { $dkim->sign($email) } catch ($caught) {
        $error = $caught
    };
    like(
        $error,
        qr/private[ ]file/msx,
        'unsafe key permissions refuse delivery'
    );
};

done_testing();

1;
