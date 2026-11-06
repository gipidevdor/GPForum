# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::OS::SupervisorProbe;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Carp qw(croak);
use Const::Fast;
use English    qw(-no_match_vars);
use Mojo::File qw(path);
use Mojo::Util qw(xml_escape);
use GPForum::OS;
our $VERSION = '0.001';
const my $EPOLL     => 4;
const my $KQUEUE    => 8;
const my $LOG_MODE  => oct '600';
const my $PID_BYTES => 32;
const my $MAX_PID   => 2_147_483_647;
__PACKAGE__->requires(qw(directory arguments runner));
has platform  => sub { return GPForum::OS->detect; };
has label     => sub { return "com.gpforum.test.$PROCESS_ID"; };
has active    => 0;
has owner_pid => 0;
has domain    => q{};

# This maintainer probe can control only its own private test job. The runner
# is injected, keeping command capture and test assertions out of the OS layer.
sub start ($self) {
    croak 'native probe already started' if $self->active;
    croak 'native probe requires its own label'
      if $self->label ne "com.gpforum.test.$PROCESS_ID";
    $self->owner_pid($PROCESS_ID);
    for my $name (qw(supervisor.log supervisor.out)) {
        my $file = path( $self->directory, $name );
        $file->spew(q{});
        chmod $LOG_MODE, $file or croak 'cannot protect native probe log';
    }
    my $kind    = $self->platform->name;
    my @payload = (
        '/usr/bin/env',
        'MOJO_REACTOR=Mojo::Reactor::EV',
        'LIBEV_FLAGS=' . ( $kind eq 'linux' ? $EPOLL : $KQUEUE ),
        @{ $self->arguments },
    );
    my $result;
    if ( $kind eq 'darwin' ) { $result = $self->_launchd_start( \@payload ); }
    elsif ( $kind eq 'freebsd' ) {
        my $dir = $self->directory;
        $result = $self->_command(
            '/usr/sbin/daemon', '-f', '-r',                  '-R',
            '1',                '-P', "$dir/supervisor.pid", '-p',
            "$dir/child.pid",   '-o', "$dir/supervisor.log", @payload
        );
    }
    elsif ( $kind eq 'linux' ) { $result = $self->_systemd_start( \@payload ); }
    else                       { croak "no native supervisor probe for $kind"; }
    if ( !$result->{status} ) { $self->active(1); }
    return $result;
}

sub stop ($self) {
    return { status => 0, output => q{} } if !$self->active;
    $self->_owned;
    my $kind = $self->platform->name;
    my $result;
    if ( $kind eq 'darwin' ) {
        $result = $self->_command( 'launchctl', 'bootout',
            $self->domain . q{/} . $self->label );
    }
    elsif ( $kind eq 'linux' ) {
        $result =
          $self->_command( 'sudo', '-n', 'systemctl', 'stop', $self->label );
    }
    else {
        my $pid = _read_pid( $self->directory . '/supervisor.pid' );
        croak 'missing native test supervisor PID' if !$pid;
        $result = { status => kill( 'TERM', $pid ) ? 0 : 1, output => q{} };
    }
    if ( !$result->{status} ) { $self->active(0); }
    return $result;
}

sub crash ($self) {
    $self->_owned;
    my $kind = $self->platform->name;
    return $self->_command( 'launchctl', 'kill', 'SIGKILL',
        $self->domain . q{/} . $self->label )
      if $kind eq 'darwin';
    return $self->_command( 'sudo', '-n', 'systemctl', 'kill',
        '--kill-whom=main', '--signal=KILL', $self->label )
      if $kind eq 'linux';
    my $pid = $self->pid;
    croak 'missing native test manager PID' if !$pid;
    return { status => kill( 'KILL', $pid ) ? 0 : 1, output => q{} };
}

# On systemd an answering worker can precede READY=1 after a restart. The
# watchdog is armed only after the native unit has accepted that readiness.
sub ready ($self) {
    return $self->active if !$self->supports_watchdog;
    $self->_owned;
    my $result =
      $self->_command( 'sudo', '-n', 'systemctl', 'show', $self->label,
        '--property=ActiveState', '--value' );
    return !$result->{status} && $result->{output} =~ /\Aactive\n?\z/amsx;
}

sub supports_watchdog ($self) { return $self->platform->name eq 'linux'; }

sub block ($self) {
    $self->_owned;
    croak 'this native supervisor has no watchdog probe'
      if !$self->supports_watchdog;
    return $self->_command( 'sudo', '-n', 'systemctl', 'kill',
        '--kill-whom=main', '--signal=STOP', $self->label );
}

sub pid ($self) { return _read_pid( $self->directory . '/manager.pid' ); }

sub diagnostics ($self) {
    my $native = q{};
    if ( $self->domain ) {
        $self->_owned;
        my $output = $self->_command( 'launchctl', 'print',
            $self->domain . q{/} . $self->label )->{output};
        $native = join "\n",
          grep { /\A\s*(?:state|pid|program|runs|last[ ]exit|spawn)[ ]*=/msx }
          split /\n/msx, $output;
    }
    if ( $self->supports_watchdog ) {
        $self->_owned;
        $native = $self->_command(
            'sudo',
            '-n',
            'systemctl',
            'show',
            $self->label,
'--property=ActiveState,SubState,Result,NRestarts,MainPID,WatchdogUSec,TimeoutAbortUSec,TimeoutStopUSec'
        )->{output};
        $native .= $self->_command( 'sudo', '-n', 'journalctl', '--unit',
            $self->label, '--lines=40', '--no-pager' )->{output};
    }
    my $dir = $self->directory;
    return $native . join "\n", map { path($_)->slurp }
      grep { -f && -r } ( "$dir/supervisor.log", "$dir/application.log" );
}

sub _owned ($self) {
    croak 'native probe does not own this job'
      if $self->owner_pid != $PROCESS_ID
      || $self->label ne "com.gpforum.test.$PROCESS_ID";
    return;
}

sub _command ( $self, @arguments ) { return $self->runner->(@arguments); }

sub _launchd_start ( $self, $payload ) {
    my $dir   = $self->directory;
    my $label = xml_escape( $self->label );
    my $args  = join q{},
      map { '<string>' . xml_escape($_) . '</string>' } @{$payload};
    my $error_path  = xml_escape("$dir/supervisor.log");
    my $output_path = xml_escape("$dir/supervisor.out");
    my $plist       = <<"PLIST";
<?xml version="1.0"?><plist version="1.0"><dict>
<key>Label</key><string>$label</string><key>ProgramArguments</key><array>$args</array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>ExitTimeOut</key><integer>8</integer><key>ThrottleInterval</key><integer>1</integer>
<key>Umask</key><integer>23</integer><key>StandardErrorPath</key><string>$error_path</string>
<key>StandardOutPath</key><string>$output_path</string></dict></plist>
PLIST
    path("$dir/job.plist")->spew($plist);
    my $result;

    for my $domain ( "gui/$UID", "user/$UID" ) {
        $self->domain($domain);
        $result = $self->_command( 'launchctl', 'bootstrap', $domain,
            "$dir/job.plist" );
        return $result if !$result->{status};
    }
    return $result;
}

sub _systemd_start ( $self, $payload ) {
    my $dir   = $self->directory;
    my ($gid) = split q{ }, $GID;
    return $self->_command(
        'sudo',                                      '-n',
        'systemd-run',                               '--unit',
        $self->label,                                '--collect',
        '--service-type=notify',                     "--uid=$UID",
        "--gid=$gid",                                '-p',
        'NotifyAccess=main',                         '-p',
        'WatchdogSec=3',                             '-p',
        'TimeoutStartSec=12',                        '-p',
        'TimeoutAbortSec=3',                         '-p',
        'TimeoutStopSec=8',                          '-p',
        'KillMode=mixed',                            '-p',
        'KillSignal=SIGTERM',                        '-p',
        'Restart=on-failure',                        '-p',
        'RestartSec=1',                              '-p',
        'UMask=0027',                                '-p',
        "StandardError=append:$dir/supervisor.log",  '-p',
        "StandardOutput=append:$dir/supervisor.out", @{$payload}
    );
}

sub _read_pid ($file) {

    # A disappearing or unreadable PID is never ready and never a signal target.
    open my $handle, '<', $file or return 0;
    my $value = q{};
    my $read  = sysread $handle, $value, $PID_BYTES;
    close $handle or croak 'cannot close native probe PID file';
    return 0 if !defined $read;
    my ($digits) = $value =~ /\A([1-9]\d*)\n?\z/amsx;
    return 0 if !defined $digits;
    my $pid = 0 + $digits;
    return $pid <= $MAX_PID ? $pid : 0;
}
1;
