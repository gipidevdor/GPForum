# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use lib 'lib', 't/lib';
use Path::Tiny qw(path);
use GPForum::Controller::Base;
use GPForum::Infrastructure::AsyncWork;
use GPForum::Infrastructure::PgStorage;
our $VERSION = '0.001';

# A web worker never forks to reach PostgreSQL. Database work runs on the
# pooled asynchronous connections (SqlFunction rows_p, row_p,
# transaction_p); a child process is for CPU or blocking system work only,
# through AsyncWork cpu_p, and cannot open a connection.

subtest 'the fork fallback is gone' => sub {
    my $work = GPForum::Infrastructure::AsyncWork->new;
    for my $method (qw(service_p service_args_p service_result_p)) {
        ok( !$work->can($method), "AsyncWork has no $method" );
    }
    for my $method (qw(work_p work_args_p)) {
        ok(
            !GPForum::Controller::Base->can($method),
            "Controller::Base has no $method"
        );
    }
};

subtest 'only cpu_p starts a child, and job_p only for the outbox runner' =>
  sub {
    my ( @run, @job );
    path('lib')->visit(
        sub ( $file, $ ) {
            return if $file !~ /[.]pm\z/msx;
            return if $file->basename eq 'AsyncWork.pm';
            my $text = $file->slurp_utf8;
            if (   $text =~ /AsyncWork\b[^;]{0,80}?->run_p\b/msx
                || $text =~ /async_work->run_p\b/msx )
            {
                push @run, "$file";
            }
            if ( $text =~ /->job_p\b/msx ) { push @job, "$file"; }
        },
        { recurse => 1 }
    );
    is_deeply( \@run, [], 'no module calls AsyncWork run_p directly' );
    is_deeply(
        \@job,
        ['lib/GPForum/Service/Outbox/Dispatcher.pm'],
        'job_p belongs to the command-line outbox runner alone'
    );
  };

subtest 'a CPU child cannot open PostgreSQL' => sub {
    local $GPForum::Infrastructure::PgStorage::NO_DATABASE = 1;
    my $storage = bless {}, 'GPForum::Infrastructure::PgStorage';
    for my $method (qw(database dbh)) {
        my $error;
        try { $storage->$method; }
        catch ($caught) { $error = $caught; };
        like( $error, qr/CPU-only[ ]child/msx, "$method refuses" );
    }
};

subtest 'cpu_p sets that guard in its child' => sub {
    my $storage = bless {}, 'GPForum::Infrastructure::PgStorage';
    my $work    = GPForum::Infrastructure::AsyncWork->new;
    my $error;
    my $refused = $work->cpu_p( sub { $storage->database; return 1; } );
    $refused->catch( sub ($failure) { $error = $failure; return; } )->wait;
    like(
        $error,
        qr/CPU-only[ ]child/msx,
        'a child that reaches for PostgreSQL fails'
    );
    my $answer;
    my $plain = $work->cpu_p( sub { return 'plain data'; } );
    $plain->then( sub ($value) { $answer = $value; return; } )->wait;
    is( $answer, 'plain data', 'and plain work still answers' );
};

done_testing();
1;
