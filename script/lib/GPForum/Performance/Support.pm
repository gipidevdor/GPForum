# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Performance::Support;

use v5.40;
use Carp           qw(croak);
use Cwd            qw(abs_path);
use English        qw(-no_match_vars);
use Exporter       qw(import);
use File::Basename qw(dirname);
use File::Path     qw(make_path);
use File::Spec;
use File::Temp qw(tempfile);
use JSON::PP;
use POSIX       qw(setsid WNOHANG);
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC sleep);
use GPForum::Performance::CommandError;

# The report/publisher must load before CPAN setup, so constants use core Perl.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    MAX_COMMAND_SECONDS  =>  1_800,
    LOG_LIMIT_BYTES      => 200_000,
    ERROR_TAIL_BYTES     =>  1_200,
    SIGNAL_BITS          =>  127,
    SIGNAL_STATUS_OFFSET =>  128,
    EXIT_SHIFT           =>  8,
    MIN_SECRET_LENGTH    =>  4,
    POLL_INTERVAL        =>  0.02,
    TERM_GRACE_SECONDS   =>  3,
    WAIT_ERROR           => -1,
    CHILD_FAILURE        =>  126,
};

our $VERSION = '0.001';
our @EXPORT_OK =
  qw(root_dir read_json write_json redact monotonic run_bounded terminate);

sub root_dir {
    return abs_path( File::Spec->catdir( dirname(__FILE__), qw(.. .. .. ..) ) );
}

sub monotonic {
    return clock_gettime(CLOCK_MONOTONIC);
}

sub read_json ($path) {
    open my $handle, '<:encoding(UTF-8)', $path
      or croak "Cannot read $path: $OS_ERROR";
    my $raw = do { local $INPUT_RECORD_SEPARATOR = undef; <$handle> };
    close $handle or croak "Cannot close $path: $OS_ERROR";
    return JSON::PP->new->decode($raw);
}

sub write_json ( $path, $data ) {
    make_path( dirname($path) );
    my ( $handle, $temporary ) =
      tempfile( '.performance-XXXXXX', DIR => dirname($path), UNLINK => 1 );
    binmode $handle, ':encoding(UTF-8)'
      or croak "Cannot encode $path: $OS_ERROR";
    my $json = JSON::PP->new->canonical->pretty;
    print {$handle} $json->encode($data)
      or croak "Cannot write $path: $OS_ERROR";
    close $handle or croak "Cannot close $path: $OS_ERROR";
    rename $temporary, $path or croak "Cannot replace $path: $OS_ERROR";
    return $data;
}

sub redact ($raw) {
    $raw = "$raw";
    my $sensitive = qr/(?:password|passwd|secret|token|authorization)/msx;
    $raw =~
      s{(postgres(?:ql)?://)[^/\@\s]+:[^/\@\s]+\@}{$1 . '[redacted]@'}geimsx;
    $raw =~ s{dbi:Pg:[^\s"']+}{[redacted connection]}gimsx;
    $raw =~ s{((?:password|passwd)=)[^;\s]+}{$1 . '[redacted]'}geimsx;
    $raw =~ s{("$sensitive"\s*:\s*)"[^"\n]*"}{$1 . '"[redacted]"'}geimsx;
    $raw =~
s{gh[pousr]_[[:alnum:]]{20,}|github_pat_[[:alnum:]_]{20,}}{[redacted]}gamsx;
    for my $name ( keys %ENV ) {
        next
          if $name !~ /PASSWORD|SECRET|TOKEN/msx
          || length( $ENV{$name} ) < MIN_SECRET_LENGTH;
        my $value = $ENV{$name};
        $raw =~ s/\Q$value\E/[redacted]/gmsx;
    }
    return $raw;
}

sub _reap ( $pid, $until ) {
    while ( monotonic() < $until ) {
        my $result = waitpid $pid, WNOHANG;
        return $CHILD_ERROR if $result == $pid;
        return undef        if $result == WAIT_ERROR;
        sleep POLL_INTERVAL;
    }
    return undef;
}

sub terminate ($pid) {
    kill 'TERM', -$pid;
    my $status = _reap( $pid, monotonic() + TERM_GRACE_SECONDS );
    kill 'KILL', -$pid;
    if ( !defined $status ) {
        my $result = waitpid $pid, 0;
        if ( $result == $pid ) { $status = $CHILD_ERROR; }
    }
    return $status;
}

sub _spawn ( $command, $capture, $options ) {
    my $pid = fork;
    croak "Cannot fork benchmark: $OS_ERROR" if !defined $pid;
    return $pid                              if $pid;
    setsid() >= 0    or POSIX::_exit(CHILD_FAILURE);
    chdir root_dir() or POSIX::_exit(CHILD_FAILURE);
    local %ENV = %{ $options->{env} // \%ENV };
    open STDOUT, '>&', $capture or POSIX::_exit(CHILD_FAILURE);
    open STDERR, '>&', $capture or POSIX::_exit(CHILD_FAILURE);
    exec { $command->[0] } @{$command} or POSIX::_exit(SIGNAL_BITS);
}

sub _observe ( $pid, $options, $started ) {
    my $until       = $started + $options->{timeout};
    my $next_sample = $started;
    while ( monotonic() < $until ) {
        if ( $options->{on_sample} && monotonic() >= $next_sample ) {
            $options->{on_sample}->( $pid, monotonic() - $started );
            $next_sample = monotonic() + 1;
        }
        my $result = waitpid $pid, WNOHANG;
        return { status => $CHILD_ERROR, timed_out => 0 } if $result == $pid;
        croak 'Owned command unexpectedly disappeared' if $result == WAIT_ERROR;
        sleep POLL_INTERVAL;
    }
    return { status => undef, timed_out => 1 };
}

sub _captured ( $capture, $log ) {
    seek $capture, 0, 2 or croak "Cannot seek capture: $OS_ERROR";
    my $length = tell $capture;
    seek $capture, $length > LOG_LIMIT_BYTES ? $length - LOG_LIMIT_BYTES : 0, 0
      or croak "Cannot rewind capture: $OS_ERROR";
    my $output = do { local $INPUT_RECORD_SEPARATOR = undef; <$capture> }
      // q{};
    if ($log) {
        make_path( dirname($log) );
        open my $handle, '>:encoding(UTF-8)', $log
          or croak "Cannot write diagnostic: $OS_ERROR";
        print {$handle} redact($output)
          or croak "Cannot write diagnostic: $OS_ERROR";
        close $handle or croak "Cannot close diagnostic: $OS_ERROR";
    }
    return $output;
}

sub run_bounded ( $command, $options ) {
    croak 'Command arguments must be a nonempty array'
      if ref($command) ne 'ARRAY' || !@{$command};
    my $timeout = $options->{timeout} // 0;
    if (   $timeout <= 0
        || $timeout != $timeout
        || $timeout > MAX_COMMAND_SECONDS )
    {
        croak GPForum::Performance::CommandError->new(
            'No valid command budget remaining',
            1, undef );
    }
    my ($capture) = tempfile( UNLINK => 1 );
    my $started   = monotonic();
    my $pid       = _spawn( $command, $capture, $options );
    my ( $result, $failure );
    try { $result = _observe( $pid, $options, $started ); }
    catch ($error) { $failure = $error; };
    my $last_status = terminate($pid);
    my $output      = _captured( $capture, $options->{log} );
    close $capture or croak "Cannot close command capture: $OS_ERROR";
    croak $failure if $failure;
    my $status = $result->{status} // $last_status // 0;
    my $exit_code =
      ( $status & SIGNAL_BITS )
      ? SIGNAL_STATUS_OFFSET + ( $status & SIGNAL_BITS )
      : $status >> EXIT_SHIFT;

    if ( $options->{result} ) {
        @{ $options->{result} }{qw(returncode timed_out elapsed_seconds output)}
          = (
            $exit_code, $result->{timed_out}, monotonic() - $started, $output,
          );
    }
    if ( $result->{timed_out} ) {
        croak GPForum::Performance::CommandError->new(
            'Command exceeded its remaining deadline',
            1, $exit_code );
    }
    my %accepted = map { $_ => 1 } @{ $options->{accepted_codes} // [0] };
    if ( !$accepted{$exit_code} ) {
        croak GPForum::Performance::CommandError->new(
            "Command failed (exit $exit_code): "
              . redact( substr $output, -ERROR_TAIL_BYTES ),
            0, $exit_code
        );
    }
    return
      $output;   # Decode structured stdout before any fixture-secret redaction.
}

1;
