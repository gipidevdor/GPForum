# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Performance::HTTPComplete;
use v5.40;
use GPForum::OS::Reactor;
use Mojo::Base -base, -signatures;
use Carp qw(croak);
use Const::Fast;
use English     qw(-no_match_vars);
use Config      qw(%Config);
use Digest::SHA qw(sha256_hex);
use Mojo::File  qw(path);
use Mojolicious ();
use File::Path  qw(make_path);
use File::Temp  qw(tempdir);
use List::Util  qw(max any sum0);
use Mojo::Promise;
use Test::PostgreSQL;
use GPForum::Benchmark::Measure     qw(percentile);
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Command::Migrate;
use GPForum::Command::PerformanceSeed;
use GPForum::Command::QueryBudget;
use GPForum::Config;
use GPForum::Schema;
use GPForum::Service::Password;
use GPForum::Service::Admin::Bootstrapper;
use GPForum::Performance::HTTPClient;
use GPForum::Performance::HTTPReport  qw(write_report);
use GPForum::Performance::Metadata    qw(initial);
use GPForum::Performance::HTTPCatalog qw(reads journeys publishing);
use GPForum::Performance::Operations  qw(inventory);
use GPForum::Performance::Server;
use GPForum::Performance::Support qw(monotonic write_json root_dir);
our $VERSION = '0.001';
const my $PASSWORD  => 'complete HTTP benchmark correct horse battery staple';
const my $MIN_USERS => 5;
const my $MEMBER_OFFSET   => 3;
const my $CATEGORIES      => 8;
const my $THREADS         => 240;
const my $POSTS           => 20;
const my $ARCHIVE_DIVISOR => 5;
const my $THREAD_WEIGHT   => 4;
const my $P50             => 50;
const my $P95             => 95;
const my $P99             => 99;
has options => sub { return {}; };
has report  => sub {
    return {
        schema_version => 1,
        status         => 'running',
        cells          => [],
        failures       => [],
        skipped        => []
    };
};
has [qw(server schema cluster directory)];
has samples     => sub { return []; };
has all_samples => sub { return []; };
has pools       => sub { return {}; };
has collecting  => 0;
has writes      => sub { return {}; };

sub run ($self) {
    my $o = $self->options;
    croak 'output directory already exists' if -e $o->{output};
    make_path( $o->{output} );
    $self->directory( tempdir( CLEANUP => 1 ) );
    my $started = monotonic();
    $o->{expires} = $started + $o->{deadline};
    local %ENV = %ENV;
    $self->report->{metadata} = initial('main');
    $self->report->{harness_sha256} =
      { map { $_ => sha256_hex( path( root_dir(), $_ )->slurp ) }
          qw(script/benchmark-http-complete script/lib/GPForum/Performance/HTTPComplete.pm script/lib/GPForum/Performance/HTTPClient.pm script/lib/GPForum/Performance/HTTPCatalog.pm script/lib/GPForum/Performance/HTTPReport.pm benchmarks/hypnotoad-app.pl)
      };
    $self->report->{configuration} =
      { map { $_ => $o->{$_} }
          qw(profile workers concurrency iterations write_clients write_iterations repetitions duration warmup deadline scenario)
      };
    $self->_save;
    my $error;
    try {
        $self->_prepare;
        $self->_clients;
        $self->_reads;
        $self->_journeys;
        $self->_mixed;
        $self->_authentication;
        $self->report->{worker_telemetry} = $self->server->telemetry;
        $self->_verify_writes;
    }
    catch ($caught) { $error = "$caught"; };
    if ( $self->server )  { $self->server->close; }
    if ( $self->schema )  { $self->schema->storage->disconnect; }
    if ( $self->cluster ) { $self->cluster->stop; }
    if ($error)           { push @{ $self->report->{failures} }, $error; }
    $self->_finish( monotonic() - $started );
    return $self->report->{status} eq 'ok' ? 0 : 1;
}

sub _quiet ( $self, $code ) {
    open my $log, '>>', "$self->{options}{output}/setup.log"
      or croak "setup log: $OS_ERROR";
    my $result = do { local *STDOUT = $log; $code->(); };
    close $log or croak "close setup log: $OS_ERROR";
    croak 'database preparation failed' if $result;
    return undef;
}

## no critic (Variables::RequireLocalizedPunctuationVars) -- run localizes the whole environment through server shutdown
sub _prepare ($self) {
    my $o       = $self->options;
    my $cluster = Test::PostgreSQL->new(
        unix_socket           => 1,
        extra_initdb_args     => '--encoding=UTF8 --no-locale',
        extra_postmaster_args =>
'-c max_connections=80 -c fsync=on -c full_page_writes=on -c synchronous_commit=on'
    ) // croak 'cannot create temporary PostgreSQL';
    $self->cluster($cluster);
    $ENV{GPFORUM_ENV}               = 'test';
    $ENV{GPFORUM_DATABASE_DSN}      = $cluster->dsn( dbname => 'postgres' );
    $ENV{GPFORUM_DATABASE_USER}     = 'postgres';
    $ENV{GPFORUM_DATABASE_PASSWORD} = q{};
    my $admin =
      GPForum::Schema->connect_from_config( GPForum::Config->from_environment );
    my $name = "gpforum_perf_http_$PROCESS_ID";
    $admin->storage->dbh->do("CREATE DATABASE $name");
    $admin->storage->disconnect;
    $ENV{GPFORUM_DATABASE_DSN}     = $cluster->dsn( dbname => $name );
    $ENV{GPFORUM_POST_SIGNING_KEY} = $self->directory . '/signing-key.pem';
    $ENV{GPFORUM_ATTACHMENT_ROOT}  = $self->directory . '/attachments';
    $ENV{GPFORUM_MINION_ENABLED}   = 0;
    $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
    $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
    $ENV{GPFORUM_PERFORMANCE_FULL_HTTP}     = 1;
    $self->_quiet(
        sub { return GPForum::Command::Migrate->new->run('--apply'); } );
    my $users = max( $MIN_USERS, $o->{max_concurrency} + $MEMBER_OFFSET );
    $self->_quiet(
        sub {
            return GPForum::Command::PerformanceSeed->new->run( '--users',
                $users, '--categories', $CATEGORIES, '--threads', $THREADS,
                '--posts-per-thread', $POSTS );
        }
    );
    $self->schema(
        GPForum::Schema->connect_from_config(
            GPForum::Config->from_environment
        )
    );
    my $db = $self->schema->storage->dbh;
    GPForum::Service::Admin::Bootstrapper->new( schema => $self->schema )
      ->bootstrap( { user_id => seed_id( user => 1 ) } );
    $db->do(
q{UPDATE role_bindings SET resource_type='global', space_id=NULL WHERE user_id=?},
        undef,
        seed_id( user => 2 )
    );
    $db->do(
q{INSERT INTO role_permissions(role_id,permission_id) SELECT ?,permission_id FROM permissions WHERE resource_type IN ('report','moderation_action','suspension','thread','post','user') ON CONFLICT DO NOTHING},
        undef,
        seed_id( role => 2 )
    );
    $self->_quiet(
        sub { return GPForum::Command::QueryBudget->new->run('--sync'); } );
    my $hash = GPForum::Service::Password->new->hash_password($PASSWORD);
    $db->do(
q{UPDATE users SET password_hash=?, email_verified_at=now(), status='active', trust_level=3},
        undef, $hash
    );
    $db->do('DELETE FROM credentials');
    $db->do(
q{INSERT INTO credentials(id,user_id,type,secret_hash) SELECT gen_random_uuid(),id,'password',? FROM users},
        undef, $hash
    );
    $self->report->{dataset} = {
        users         => $users,
        categories    => $CATEGORIES,
        threads       => $THREADS,
        posts         => $THREADS * $POSTS,
        private_lists =>
'seeded members retain seeded inbox/feed/bookmark rows; writes use independent member identities'
    };
    $self->report->{versions} = {
        perl        => "$PERL_VERSION",
        postgres    => scalar $db->selectrow_array('SHOW server_version'),
        platform    => $Config{archname},
        mojolicious => Mojolicious->VERSION,
    };
    $self->report->{postgres_settings} = $db->selectall_arrayref(
q{SELECT name,setting,unit FROM pg_settings WHERE name IN ('fsync','full_page_writes','synchronous_commit','shared_buffers','work_mem','jit','max_connections') ORDER BY name},
        { Slice => {} }
    );
    $self->report->{initial_counts} = $self->_counts;
    $self->server(
        GPForum::Performance::Server->new(
            {
                output     => $o->{output},
                index      => 1,
                workers    => $o->{workers},
                reactor    => 'EV',
                cache_mode => 'normal',
                deadline   => $o->{expires}
            }
        )
    );
    return undef;
}

## use critic

sub _counts ($self) {
    return $self->schema->storage->dbh->selectrow_hashref(
'SELECT (SELECT count(*) FROM threads) AS threads, (SELECT count(*) FROM posts) AS posts, (SELECT count(*) FROM event_log) AS events'
    );
}

sub _verify_writes ($self) {
    my $initial = $self->report->{initial_counts};
    my $final   = $self->_counts;
    $self->report->{final_counts} = $final;
    my $threads = scalar keys %{ $self->writes->{thread_id} // {} };
    my $replies = scalar keys %{ $self->writes->{post_id}   // {} };
    my $valid   = $final->{threads} - $initial->{threads} == $threads
      && $final->{posts} - $initial->{posts} == $threads + $replies;
    $self->report->{correctness} = {
        status                  => $valid ? 'ok' : 'fail',
        created_threads         => $threads,
        created_replies         => $replies,
        thread_delta            => $final->{threads} - $initial->{threads},
        post_delta              => $final->{posts} - $initial->{posts},
        unique_write_identities => 1
    };
    croak 'HTTP created identities differ from persisted thread/post counts'
      if !$valid;
    return undef;
}

sub _client ( $self, $actor, $index = 0 ) {
    my $user =
        $actor eq 'admin'     ? 1
      : $actor eq 'moderator' ? 2
      :                         $index + $MEMBER_OFFSET;
    return GPForum::Performance::HTTPClient->new(
        base     => $self->server->{base},
        actor    => $actor,
        username => "perf_user_$user",
        password => $PASSWORD,
        collect  => sub ($row) {
            if ( $row->{valid} && $row->{identity} ) {
                croak 'replayed identity in a fresh HTTP write'
                  if $self->writes->{ $row->{identity_key} }
                  { $row->{identity} }++;
            }
            if ( $self->collecting ) { push @{ $self->samples }, $row; }
        }
    );
}

sub _await ($promise) {
    my $failure;
    $promise->catch( sub ($error) { $failure = $error; return undef; } )->wait;
    croak $failure if defined $failure;
    return undef;
}

sub _clients ($self) {
    my $o = $self->options;
    for my $actor (qw(guest member moderator admin)) {
        my $count =
            $actor eq 'member' ? $o->{max_concurrency}
          : $actor eq 'admin'  ? $o->{write_clients}
          :                      1;
        my @clients = map { $self->_client( $actor, $_ ) } 0 .. $count - 1;
        $self->pools->{$actor} = \@clients;
        if ( $actor ne 'guest' ) {
            _await(
                Mojo::Promise->map(
                    { concurrency => $o->{workers} },
                    sub ($client) { return $client->login_p; },
                    @clients
                )
            );
        }
    }
    return undef;
}

sub _selected ( $self, $name ) {
    return !@{ $self->options->{scenario} }
      || any { $_ eq $name } @{ $self->options->{scenario} };
}

sub _repeat_p ( $count, $code ) {
    my $promise = Mojo::Promise->resolve;
    for ( 1 .. $count ) {
        $promise = $promise->then( sub { return $code->(); } );
    }
    return $promise;
}

sub _until_p ( $until, $code ) {
    return Mojo::Promise->resolve if monotonic() >= $until;
    return $code->()->then( sub { return _until_p( $until, $code ); } );
}

sub _cell ( $self, $name, $clients, $task, $repetition ) {
    if ( monotonic() >= $self->options->{expires} ) {
        push @{ $self->report->{skipped} },
          { scenario => $name, reason => 'global deadline' };
        return undef;
    }
    $self->samples( [] );
    $self->collecting(1);
    my @errors;
    my $started = monotonic();
    _await(
        Mojo::Promise->map(
            sub ($client) {
                return $task->($client)
                  ->catch(
                    sub ($error) { push @errors, "$error"; return undef; } );
            },
            @{$clients}
        )
    );
    my $elapsed = monotonic() - $started;
    $self->collecting(0);
    my $samples = $self->samples;
    my $metrics = _summary( $samples, $elapsed );
    push @{ $self->report->{cells} },
      {
        scenario        => $name,
        clients         => scalar @{$clients},
        repetition      => $repetition,
        status          => @errors ? 'fail' : 'ok',
        elapsed_seconds => $elapsed,
        metrics         => $metrics,
        errors          => \@errors
      };
    push @{ $self->all_samples },        @{$samples};
    push @{ $self->report->{failures} }, @errors;
    $self->_save;
    printf "%s c=%d rep=%d requests=%d p95=%.2fms errors=%d\n", $name,
      scalar @{$clients}, $repetition,
      scalar @{$samples}, $metrics->{latency}{p95_ms} // 0, scalar @errors;
    return undef;
}

sub _reads ($self) {
    my $o = $self->options;
    for my $spec ( @{ reads() } ) {
        next if !$self->_selected( $spec->{name} );
        if ( monotonic() >= $o->{expires} ) {
            push @{ $self->report->{skipped} },
              { scenario => $spec->{name}, reason => 'global deadline' };
            next;
        }
        my $pool = $self->pools->{ $spec->{actor} };
        my $iterations =
          $spec->{expensive}
          ? max( 1, int( $o->{iterations} / $ARCHIVE_DIVISOR ) )
          : $o->{iterations};
        for ( 1 .. $o->{warmup} ) { _await( $pool->[0]->request_p($spec) ); }
        for my $rep ( 1 .. $o->{repetitions} ) {
            $self->_cell(
                $spec->{name},
                [ $pool->[0] ],
                sub ($client) {
                    return _repeat_p( $iterations,
                        sub { return $client->request_p($spec); } );
                },
                $rep
            );
            next if !$spec->{hot};
            for my $concurrency ( grep { $_ > 1 } @{ $o->{concurrency} } ) {
                my @clients = @{$pool}[ 0 .. $concurrency - 1 ];
                my $until   = monotonic() + $o->{duration};
                $self->_cell(
                    $spec->{name},
                    \@clients,
                    sub ($client) {
                        return _until_p( $until,
                            sub { return $client->request_p($spec); } );
                    },
                    $rep
                );
            }
        }
    }
    return undef;
}

sub _journeys ($self) {
    my $o = $self->options;
    for my $journey ( @{ journeys() } ) {
        next if !$self->_selected( 'journey.' . $journey->{name} );
        my @clients = @{ $self->pools->{ $journey->{actor} } }
          [ 0 .. $o->{write_clients} - 1 ];
        for my $rep ( 1 .. $o->{repetitions} ) {
            $self->_cell(
                'journey.' . $journey->{name},
                \@clients,
                sub ($client) {
                    return _repeat_p( $o->{write_iterations},
                        sub { return $client->steps_p( $journey->{steps} ); } );
                },
                $rep
            );
        }
    }
    return undef;
}

sub _mixed ($self) {
    return undef if !$self->_selected('mixed');
    my $o = $self->options;
    return undef if monotonic() >= $o->{expires};
    my @clients = @{ $self->pools->{member} }[ 0 .. $o->{write_clients} - 1 ];
    _await(
        Mojo::Promise->map(
            sub ($client) { return $client->steps_p( publishing() ); },
            @clients
        )
    );
    my $thread   = seed_id( thread   => 1 );
    my $category = seed_id( category => 1 );
    my @steps    = (
        (
            map { { name => 'mixed.thread', path => "/t/$thread" } }
              1 .. $THREAD_WEIGHT
        ),
        ( map { { name => 'mixed.category', path => "/c/$category" } } 1 .. 2 ),
        (
            map { { name => 'mixed.search', path => '/search?q=performance' } }
              1 .. 2
        ),
        {
            name   => 'mixed.reply',
            method => 'POST',
            json   => 1,
            code   => 201,
            status => 'created',
            key    => 'post_id',
            path   => sub ($ctx) { return "/t/$ctx->{thread}/replies"; },
            form   => { body_source => 'Mixed HTTP benchmark reply' }
        },
        {
            name   => 'mixed.read',
            method => 'POST',
            json   => 1,
            status => 'ok',
            path   => sub ($ctx) { return "/t/$ctx->{thread}/read"; },
            form   => { last_read_position => 2 }
        },
    );

    for my $rep ( 1 .. $o->{repetitions} ) {
        my $until = monotonic() + $o->{duration};
        $self->_cell(
            'mixed',
            \@clients,
            sub ($client) {
                return _until_p( $until,
                    sub { return $client->steps_p( \@steps ); } );
            },
            $rep
        );
    }
    return undef;
}

sub _authentication ($self) {
    return undef if !$self->_selected('authentication');
    my $o = $self->options;
    for my $rep ( 1 .. $o->{repetitions} ) {
        my @clients =
          map { $self->_client( 'member', $_ ) } 0 .. $o->{write_clients} - 1;
        $self->_cell(
            'authentication',
            \@clients,
            sub ($client) {
                return $client->login_p->then(
                    sub {
                        return $client->request_p(
                            {
                                name   => 'logout',
                                method => 'POST',
                                path   => '/logout',
                                code   => 202
                            }
                        );
                    }
                );
            },
            $rep
        );
    }
    return undef;
}

sub _distribution ($values) {
    return undef if !@{$values};
    my @sorted = sort { $a <=> $b } @{$values};
    return {
        count   => scalar @sorted,
        mean_ms => sum0(@sorted) / @sorted,
        p50_ms  => percentile( \@sorted, $P50 ),
        p95_ms  => percentile( \@sorted, $P95 ),
        p99_ms  => percentile( \@sorted, $P99 ),
        max_ms  => $sorted[-1]
    };
}

sub _summary ( $samples, $elapsed ) {
    my %codes;
    for my $sample ( @{$samples} ) { $codes{ $sample->{status_code} }++; }
    return {
        latency    => _distribution( [ map { $_->{elapsed_ms} } @{$samples} ] ),
        server_app => _distribution(
            [ map { $_->{app_ms} } grep { defined $_->{app_ms} } @{$samples} ]
        ),
        server_db => _distribution(
            [ map { $_->{db_ms} } grep { defined $_->{db_ms} } @{$samples} ]
        ),
        outside_app => _distribution(
            [
                map  { max( 0, $_->{elapsed_ms} - $_->{app_ms} ) }
                grep { defined $_->{app_ms} } @{$samples}
            ]
        ),
        requests_per_second => defined $elapsed
          && $elapsed > 0 ? @{$samples} / $elapsed : undef,
        low_sample_count  => @{$samples} < $POSTS ? 1 : 0,
        requests          => scalar @{$samples},
        invalid_responses => scalar( grep { !$_->{valid} } @{$samples} ),
        status_codes      => \%codes,
    };
}

sub _save ($self) {
    write_json( $self->options->{output} . '/http-complete.json',
        $self->report );
    return undef;
}

sub _finish ( $self, $elapsed ) {
    my %groups;
    my %routes;
    for my $sample ( @{ $self->all_samples } ) {
        push @{ $groups{ join q{:}, @{$sample}{qw(actor operation)} } },
          $sample;
        if ( $sample->{valid} ) { $routes{ $sample->{route} } = 1; }
    }
    $self->report->{operations} = [
        map { { name => $_, %{ _summary( $groups{$_}, undef ) } } }
        sort keys %groups
    ];
    my $catalogue = inventory()->{http};
    $self->report->{coverage} = {
        total    => scalar @{$catalogue},
        observed => scalar( grep { $routes{$_} } @{$catalogue} ),
        missing  => [ grep { !$routes{$_} } @{$catalogue} ]
    };
    $self->report->{duration_seconds} = $elapsed;
    $self->report->{configuration} =
      { map { $_ => $self->options->{$_} }
          qw(profile workers concurrency iterations write_clients write_iterations repetitions duration warmup deadline scenario)
      };
    $self->report->{generator} =
'Mojo::UserAgent asynchronous HTTP clients; not interchangeable with wrk throughput';
    $self->report->{policy} =
'Real Hypnotoad TCP HTTP; separate real cookies per client; real login, CSRF and PostgreSQL command paths; admission quotas raised in benchmark entrypoint, PostgreSQL counters retained; background delivery disabled; outside_app includes queue/network/client overhead, not pure queue time.';
    $self->report->{status} =
        @{ $self->report->{failures} } || !@{ $self->report->{cells} } ? 'fail'
      : @{ $self->report->{skipped} } ? 'partial'
      :                                 'ok';
    $self->_save;
    write_report( $self->options->{output}, $self->report );
    return undef;
}
1;
