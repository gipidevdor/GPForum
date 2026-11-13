# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use Mojo::DOM;
use GPForum::OS;
use GPForum::Config;
use GPForum::Command::Support::ServiceEnvironment;
use GPForum::Service::Admin::Settings;
use GPForum::Service::I18N::CliCatalog;
use GPForum::Service::Operations::Findings;
use GPForum::Service::Operations::Host;
use GPForum::Service::Operations::ServiceFiles;
use GPForum::Service::Operations::ServiceUnits;
our $VERSION = '0.001';

for my $case (
    [ linux   => 'systemd', 'gpforum-push.service' ],
    [ freebsd => 'rc',      'gpforum_push' ],
    [ darwin  => 'launchd', 'com.gpforum.push.plist' ],
  )
{
    my ( $os, $target, $name ) = @{$case};
    subtest "$target connects the enabled Push worker to deployment" => sub {
        my $disabled = _files( $os, 0 );
        ok( !grep( { $_->{name} eq $name } @{ $disabled->render($target) } ),
            'disabled Push adds no worker to the deployment' );
        my $files = _files( $os, 1 );
        for my $value ( 'yes', 'true', ' ON ' ) {
            ok(
                grep( { $_->{name} eq $name }
                    @{ _files( $os, $value )->render($target) } ),
"$value enables the same worker as the application configuration"
            );
            my $reader = GPForum::Command::Support::ServiceEnvironment->new(
                os          => GPForum::OS->from_name($os),
                environment => { GPFORUM_PUSH_ENABLED => $value }
            );
            like( $reader->restart_command, qr/gpforum[-._]push/msx,
                'restart advice accepts the same boolean spelling' );
        }
        my ($worker) =
          grep { $_->{name} eq $name } @{ $files->render($target) };
        ok( $worker, 'enabled Push includes its supervised worker' );
        is( $worker->{starts}, 'gpforum-push',
            'start/reload identity follows the shared service catalogue' );
        my $commands = join "\n", @{ $files->steps( $target, start => 1 ) };
        like( $commands, qr/gpforum[-._]push/msx,
            'generated installation starts the Push worker' );

        if ( $target eq 'launchd' ) {
            my $dom = Mojo::DOM->new->xml(1)->parse( $worker->{text} );
            my @arguments =
              map { $_->text } $dom->find('key + array > string')->each;
            is_deeply(
                [ splice @arguments, @arguments - 2 ],
                [ 'push',            '--loop' ],
                'launchd runs the real Push command'
            );
            like( $worker->{text}, qr/SuccessfulExit/msx,
                'a disabled worker can exit without a restart loop' );
        }
        else {
            like(
                $worker->{text},
                qr{bin/gpforum[^\n]+[ ]push[ ]--loop}msx,
                'the supervisor invokes the real Push command'
            );
        }
        my $reader = GPForum::Command::Support::ServiceEnvironment->new(
            os          => GPForum::OS->from_name($os),
            environment => { GPFORUM_PUSH_ENABLED => 1 }
        );
        like( $reader->restart_command, qr/gpforum[-._]push/msx,
            'configuration restart instructions include Push' );
        like( $reader->start_command, qr/gpforum[-._]push/msx,
            'configuration start instructions include Push' );
    };
}

subtest
  'doctor checks the enabled sender rather than just the web and mail workers'
  => sub {
    my $files    = _files( 'linux', 1 );
    my $findings = GPForum::Service::Operations::Findings->new(
        catalog => $files->host->catalog );
    my @checked;
    my $units = GPForum::Service::Operations::ServiceUnits->new(
        files        => $files,
        host         => $files->host,
        code_changed => 0,
        systemctl    => sub (@arguments) {
            my $name = $arguments[-1];
            push @checked, $name;
            return {
                exit   => 0,
                output => "LoadState=loaded\nActiveState="
                  . ( $name eq 'gpforum-push.service' ? 'failed' : 'active' )
                  . "\n"
            };
        }
    );
    $units->running($findings);
    ok(
        grep( { $_ eq 'gpforum-push.service' } @checked ),
        'doctor observes the configured Push sender'
    );
    is( $findings->status, 'fail',
        'a stopped Push worker fails the operational check' );
    like(
        $findings->human_text,
        qr/systemctl[ ]enable[ ]--now[ ]gpforum-push/msx,
        'doctor supplies the concrete Push recovery command'
    );
  };

subtest 'the diagnostics GUI restart advice includes its enabled sender' =>
  sub {
    my $config =
      GPForum::Config->from_environment( { GPFORUM_PUSH_ENABLED => 1 } );
    my $view =
      GPForum::Service::Admin::Settings->new( config => $config )->view;
    like( $view->{change}{restart},
        qr/gpforum-push/msx, 'GUI diagnostics restart the Push sender' );
  };

done_testing();

sub _files ( $os, $enabled ) {
    my $catalog = GPForum::Service::I18N::CliCatalog->new( language => 'en' );
    my $host    = GPForum::Service::Operations::Host->new(
        catalog => $catalog,
        os      => GPForum::OS->from_name($os)
    );
    return GPForum::Service::Operations::ServiceFiles->new(
        host             => $host,
        home             => '/srv/forum',
        environment_file => '/srv/forum.env',
        environment      => { GPFORUM_PUSH_ENABLED => $enabled },
        exists           => sub { return 1; }
    );
}
1;
