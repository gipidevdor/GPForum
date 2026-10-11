# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Command::QueryPlanEvidence;

use Carp qw(croak);
use Const::Fast;
use Encode        ();
use English       qw(-no_match_vars);
use JSON::MaybeXS qw(decode_json encode_json);
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Benchmark::Measure   qw(list_text overall_status);
use GPForum::Benchmark::PlanRules qw(
  analyze_plan depth_evidence failure_rule small_table_scans_are_warnings
  unindexable
);
use GPForum::Benchmark::QueryPlanEndpoints qw(
  endpoint_definition endpoint_names function_endpoint_names read_deep_page
);
use GPForum::Command::PerformanceSeed;
use GPForum::Command::Usage;
use GPForum::Config;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Schema;
use GPForum::X::Usage;

our $VERSION = '0.001';

const my $EXIT_USAGE => 2;

# ADR 0126, section 9. A function's statements are planned inside it, where
# EXPLAIN does not reach: auto_explain logs the plan of each statement the
# call runs, nested ones included, and client_min_messages sends the log to
# this session. The plans judged are those of the sixth call, the plan the
# function's pinned plan mode caches. LOAD and these settings need a
# superuser unless the server preloads auto_explain; without them the
# endpoint is unmeasured, which fails the report rather than pass it.
const my $WARM_CALLS => 5;
const my @AUTO_EXPLAIN => (
    q{LOAD 'auto_explain'},
    'SET LOCAL auto_explain.log_min_duration = 0',
    'SET LOCAL auto_explain.log_nested_statements = on',
    'SET LOCAL auto_explain.log_format = json',
    'SET LOCAL auto_explain.log_level = log',
    'SET LOCAL auto_explain.log_parameter_max_length = 0',
    'SET LOCAL auto_explain.log_buffers = on',
    'SET LOCAL auto_explain.log_wal = on',
    'SET LOCAL auto_explain.log_timing = on',
    'SET LOCAL auto_explain.log_verbose = off',
    'SET LOCAL auto_explain.log_settings = off',
    'SET LOCAL auto_explain.sample_rate = 1',
    'SET LOCAL client_min_messages = log',
);
const my $NESTED_PLAN => qr/plan: \s* (?<plan> [{] .* [}] ) \s* \z/msx;
const my $CALL_TEXT   => qr/\A SELECT [ ] [*] [ ] FROM [ ] api [.]/msx;
const my %CAPTURE_REASON => map { $_ => 1 }
  qw(permission-denied no-nested-plan-observed plan-capture-failed);

const my %SWITCH_OPTION => (
    '--analyze'    => { analyze   => 1 },
    '--check'      => { check     => 1 },
    '--dry-run'    => { dry_run   => 1 },
    '--functions'  => { functions => 1 },
    '--help'       => { help      => 1 },
    '--json'       => { format    => 'json' },
    '--no-analyze' => { analyze   => 0 },
);

has dbh    => undef;    # optional: a test passes one; else the schema's
has schema => undef;    # optional: connected from the environment otherwise

# The deep pages the report being taken has read, by kind of list: two
# endpoints that page the same list page it at the same cursor.
has deep_pages => sub { return {}; };

# Misuse becomes the documented usage exit instead of an uncaught exception:
# same text, on stderr, status 2, without croak's " at FILE line N". Anything
# else is rethrown, so a real failure is not relabelled as misuse.
sub run ( $self, @arguments ) {
    my $status;
    try {
        $status = $self->_run(@arguments);
    }
    catch ($error) {
        my $text = GPForum::Command::Usage->trimmed($error);
        die "$text\n" if !GPForum::Command::Usage->is_usage($error);

        return GPForum::Command::Usage->error( undef, $text );
    };

    return $status;
}

sub _run ( $self, @arguments ) {
    my $options = _options(@arguments);
    if ( $options->{help} ) {
        print _usage(), "\n" or croak 'failed to write usage';
        return 0;
    }

    my $report;
    try {
        $report = $self->evidence_report($options);
    }
    catch ($error) {
        print {*STDERR}
          'script/query-plan-evidence: PostgreSQL query plan evidence failed. '
          . 'Run script/bootstrap-deps --postgres, apply migrations, '
          . "seed benchmark data, and ensure the database is reachable.\n"
          or croak 'failed to write the query plan error';
        return $EXIT_USAGE;
    };

    print $self->format_report( $report, $options->{format} )
      or croak 'failed to write query plan evidence report';

    return $options->{check} && $report->{status} ne 'ok' ? 1 : 0;
}

sub evidence_report ( $self, $options ) {
    $options->{profile} ||= 'small';
    my @endpoints =
        @{ $options->{endpoints} } ? @{ $options->{endpoints} }
      : $options->{functions}      ? function_endpoint_names()
      :                              endpoint_names();
    if ( $options->{dry_run} ) {
        return _dry_run_report( \@endpoints, $options );
    }

    my $dbh = $self->dbh || $self->_schema->storage->dbh;
    $self->deep_pages( {} );
    my @reports;
    for my $endpoint (@endpoints) {
        push @reports, $self->_endpoint_report( $dbh, $endpoint, $options );
    }

    my $dsn = GPForum::Config->from_environment->database_dsn;
    $dsn =~ s/(password=)[^;]+/${1}<redacted>/gmsx;

    return {
        status       => overall_status( \@reports ),
        mode         => 'postgres',
        analyze      => $options->{analyze} ? 1 : 0,
        dsn          => $dsn,
        endpoints    => \@reports,
        checked_at   => 'runtime',
        dataset      => { profile => $options->{profile} },
        failure_rule => failure_rule(),
    };
}

sub format_report ( $self, $report, $format ) {
    return encode_json($report) . "\n" if $format eq 'json';

    return _text_report($report);
}

# A deep endpoint EXPLAINs two pages of the same list: the first, and one
# halfway down it. The deep page's plan is judged like any other; the first
# page's is the baseline the deep page's filtering is compared with.
sub _endpoint_report ( $self, $dbh, $endpoint, $options ) {
    my $definition = _endpoint_definition($endpoint);
    if ( $definition->{call} ) {
        return $self->_function_report( $dbh, $endpoint, $definition,
            $options );
    }

    # A deep endpoint's page is read once per report for each kind of list,
    # and the first page of that list is planned beside it.
    my $kind = $definition->{deep};
    my $page =
      defined $kind
      ? ( $self->deep_pages->{$kind} //= read_deep_page( $dbh, $kind ) )
      : undef;
    my $statement = $self->_statement( $definition, $page );
    my $first =
        $page && defined $page->{after}
      ? $self->_statement( $definition, { %{$page}, after => undef } )
      : undef;
    my $explained = _explain( $dbh, $statement, $options, $first );
    my $plan      = decode_json( $explained->{plan} )->[0];
    my $analysis  = analyze_plan( $definition, $statement, $plan );
    small_table_scans_are_warnings( $dbh, $analysis, $definition );
    push @{ $analysis->{violations} },
      unindexable( $definition, decode_json( $explained->{forced} )->[0] );
    my $depth =
      $page
      ? depth_evidence( $dbh, $analysis, $page,
        { deep => $plan, _first_page_plan( $explained, $first, $statement ) } )
      : undef;
    $analysis->{status} = @{ $analysis->{violations} } ? 'fail' : 'ok';

    return {
        endpoint   => $endpoint,
        status     => $analysis->{status},
        purpose    => $definition->{purpose},
        sql_label  => $definition->{sql_label},
        violations => $analysis->{violations},
        warnings   => $analysis->{warnings},
        summary    => {
            root_node      => $plan->{Plan}{'Node Type'},
            plan_rows      => $plan->{Plan}{'Plan Rows'} || 0,
            actual_rows    => $plan->{Plan}{'Actual Rows'},
            total_cost     => $plan->{Plan}{'Total Cost'} || 0,
            actual_time_ms => $plan->{Plan}{'Actual Total Time'},
            shared_hit     => $plan->{Plan}{'Shared Hit Blocks'},
            shared_read    => $plan->{Plan}{'Shared Read Blocks'},
            ( $depth ? ( depth => $depth ) : () ),
        },
    };
}

# A function endpoint: the plans of the statements the reader's call runs
# inside its function, each judged as an endpoint's statement is, and a deep
# page's filtering against its first page's.
sub _function_report ( $self, $dbh, $endpoint, $definition, $options ) {
    my $kind = $definition->{deep};
    my $page =
      defined $kind
      ? ( $self->deep_pages->{$kind} //= read_deep_page( $dbh, $kind ) )
      : undef;
    my $statement = $self->_call_statement( $definition, $page );
    my $first =
        $page && defined $page->{after}
      ? $self->_call_statement( $definition, { %{$page}, after => undef } )
      : undef;

    my $explained;
    try {
        $explained = _explain_nested( $dbh, $statement, $options, $first );
    }
    catch ($error) {
        return _unmeasured( $endpoint, $definition, $error );
    };

    my $analysis = _judged_nested( $dbh, $definition, $explained );
    my ( $plan, $first_plan ) =
      ( $explained->{plan}[0] // {}, $explained->{first}[0] // {} );
    my $depth =
      $page
      ? depth_evidence(
        $dbh,
        $analysis,
        $page,
        {
            deep           => $plan,
            first          => $first_plan,
            same_statement => (
                ( $plan->{'Query Text'}         // q{} ) eq
                  ( $first_plan->{'Query Text'} // q{} ) ? 1 : 0
            ),
        }
      )
      : undef;
    $analysis->{status} = @{ $analysis->{violations} } ? 'fail' : 'ok';

    return {
        endpoint   => $endpoint,
        status     => $analysis->{status},
        purpose    => $definition->{purpose},
        sql_label  => $definition->{sql_label},
        violations => $analysis->{violations},
        warnings   => $analysis->{warnings},
        summary    => {
            nested_statements => scalar @{ $explained->{plan} },
            root_node         => $plan->{Plan}{'Node Type'},
            plan_rows         => $plan->{Plan}{'Plan Rows'} || 0,
            actual_rows       => $plan->{Plan}{'Actual Rows'},
            total_cost        => $plan->{Plan}{'Total Cost'} || 0,
            actual_time_ms    => $plan->{Plan}{'Actual Total Time'},
            statements        => _statement_metrics( $explained->{plan} ),
            ( $depth ? ( depth => $depth ) : () ),
        },
    };
}

# Only numeric observations leave the nested plans. Query text, parameters
# and predicates can contain application data, even with parameter logging
# disabled. Each root includes its children; enclosing function statements
# can also include a nested helper's work, so these rows are never summed.
# auto_explain does not measure planning time: its absent field stays null.
sub _statement_metrics ($plans) {
    my $index = 0;
    my @metrics;

    for my $plan ( @{$plans} ) {
        my $node = $plan->{Plan};
        push @metrics,
          {
            statement_index   => ++$index,
            plan_rows         => $node->{'Plan Rows'},
            total_cost        => $node->{'Total Cost'},
            actual_rows       => $node->{'Actual Rows'},
            actual_loops      => $node->{'Actual Loops'},
            actual_time_ms    => $node->{'Actual Total Time'},
            planning_time_ms  => $plan->{'Planning Time'},
            execution_time_ms => $plan->{'Execution Time'},
            shared_hit        => $node->{'Shared Hit Blocks'},
            shared_read       => $node->{'Shared Read Blocks'},
            shared_dirtied    => $node->{'Shared Dirtied Blocks'},
            shared_written    => $node->{'Shared Written Blocks'},
            local_hit         => $node->{'Local Hit Blocks'},
            local_read        => $node->{'Local Read Blocks'},
            temp_read         => $node->{'Temp Read Blocks'},
            temp_written      => $node->{'Temp Written Blocks'},
            wal_records       => $node->{'WAL Records'},
            wal_fpi           => $node->{'WAL FPI'},
            wal_bytes         => $node->{'WAL Bytes'},
          };
    }

    return \@metrics;
}

# Every nested plan judged as an endpoint's statement is, and the forced
# plans asked whether an index answers them.
sub _judged_nested ( $dbh, $definition, $explained ) {
    my $analysis = { violations => [], warnings => [] };
    for my $plan ( @{ $explained->{plan} } ) {
        my $judged =
          analyze_plan( $definition, [ $plan->{'Query Text'} // q{} ], $plan );
        push @{ $analysis->{violations} }, @{ $judged->{violations} };
        push @{ $analysis->{warnings} },   @{ $judged->{warnings} };
    }
    small_table_scans_are_warnings( $dbh, $analysis, $definition );
    push @{ $analysis->{violations} },
      map { unindexable( $definition, $_ ) } @{ $explained->{forced} };

    return $analysis;
}

# An endpoint whose plans could not be read: not a pass.
sub _unmeasured ( $endpoint, $definition, $error ) {

    # Only the capture protocol's constant reasons reach public evidence.
    # A driver's exception may include the SQL, binds or connection secrets.
    my ($message) = split /\s/msx, "$error", 2;
    my $reason =
      $CAPTURE_REASON{ $message // q{} } ? $message : 'plan-capture-failed';

    return {
        endpoint   => $endpoint,
        status     => 'unmeasured',
        purpose    => $definition->{purpose},
        sql_label  => $definition->{sql_label},
        violations => [],
        warnings   => ["auto_explain_unavailable: $reason"],
    };
}

# The statement and values the reader's call sends, through the layer's own
# binding, so this explains what the application runs.
sub _call_statement ( $self, $definition, $page = undef ) {
    my ( $name, $values ) =
      @{ $definition->{call}->( $self->_schema, ( $page ? ($page) : () ) ) };

    return GPForum::Infrastructure::SqlFunction->new( schema => $self->_schema )
      ->statement( $name, $values );
}

# The nested plans of the call, the first page's, and with sequential scans
# disabled the plans no index can do without. All in one transaction that is
# rolled back, as _explain takes its plans; DISCARD PLANS makes the forced
# call plan again, where the function would reuse the plan it cached.
sub _explain_nested ( $dbh, $statement, $options, $first = undef ) {
    my @log;
    local $SIG{__WARN__} = sub ($message) { push @log, $message; return; };

    $dbh->begin_work;
    my ( %plans, $error );
    try {
        for my $setting ( @AUTO_EXPLAIN,
            'SET LOCAL auto_explain.log_analyze = '
            . ( $options->{analyze} ? 'on' : 'off' ) )
        {
            $dbh->do($setting);
        }
        if ($first) {
            $plans{first} = _nested_plans( $dbh, $first, \@log );
        }
        $plans{plan} = _nested_plans( $dbh, $statement, \@log );
        croak 'auto_explain returned no nested plans'
          if !@{ $plans{plan} };
        $dbh->do('SET LOCAL auto_explain.log_analyze = off');
        $dbh->do('SET LOCAL enable_seqscan = off');
        $dbh->do('DISCARD PLANS');
        $plans{forced} = _nested_plans( $dbh, $statement, \@log );
    }
    catch ($caught) {
        $error =
          ( $dbh->state // q{} ) eq '42501' ? 'permission-denied'
          : "$caught" =~
          /\A auto_explain [ ] returned [ ] no [ ] nested [ ] plans \b/msx
          ? 'no-nested-plan-observed'
          : 'plan-capture-failed';
    };
    $dbh->rollback;
    croak $error if defined $error;

    return \%plans;
}

# The plans auto_explain logged for the statements the last of six calls ran
# inside its function: the call's own plan is left out.
sub _nested_plans ( $dbh, $statement, $log ) {
    my ( $sql, @bind ) = @{$statement};
    for ( 1 .. $WARM_CALLS ) {
        $dbh->selectall_arrayref( $sql, undef, @bind );
    }
    @{$log} = ();
    $dbh->selectall_arrayref( $sql, undef, @bind );

    my @plans;
    for my $message ( @{$log} ) {
        next if $message !~ $NESTED_PLAN;
        my $plan =
          decode_json( Encode::encode_utf8( $LAST_PAREN_MATCH{plan} ) );
        next if ( $plan->{'Query Text'} // q{} ) =~ $CALL_TEXT;
        push @plans, $plan;
    }
    @{$log} = ();

    return \@plans;
}

# The first page's plan, and whether the reader made the two pages one
# statement.
sub _first_page_plan ( $explained, $first, $statement ) {
    return if !$first;

    return (
        first          => decode_json( $explained->{first} )->[0],
        same_statement => (
            join( "\0", map { $_ // q{} } @{$first} ) eq
              join( "\0", map { $_ // q{} } @{$statement} ) ? 1 : 0
        ),
    );
}

# Rendering a resultset's SQL needs the schema but not a connection, so a
# report run against an injected handle still EXPLAINs the application's SQL.
sub _schema ($self) {
    if ( !$self->schema ) {
        $self->schema(
            GPForum::Schema->connect_from_config(
                GPForum::Config->from_environment
            )
        );
    }

    return $self->schema;
}

# What the application executes for the endpoint: the resultset lib/ builds,
# as DBIx::Class renders it, or -- where lib/ issues raw SQL -- lib/'s own
# statement. Nothing is transcribed, so changing a reader's query changes what
# this gate EXPLAINs. A deep endpoint's resultset takes the page it is
# asked for. Returns [ $sql, @bind ].
sub _statement ( $self, $definition, $page = undef ) {
    return $definition->{statement}->() if $definition->{statement};

    my ( $sql, @bind ) = @{
        ${
            $definition->{resultset}
              ->( $self->_schema, ( $page ? ($page) : () ) )->as_query
        }
    };

    return [ $sql, map { ref $_ eq 'ARRAY' ? $_->[1] : $_ } @bind ];
}

# Two plans of the same statement. The first is the planner's own choice,
# which carries the timings and row counts. The second is taken with
# sequential scans disabled: a sequential scan that survives that means no
# index can answer the query at all -- a fact about the schema, true on a
# ten-row test database and on a production one alike, where the first plan's
# row thresholds only notice once the table is already large.
#
# EXPLAIN ANALYZE executes the statement, and the outbox claim is an UPDATE.
# Every plan is taken inside a transaction that is rolled back, so gathering
# evidence never changes the data it measures, and SET LOCAL ends with it. A
# deep endpoint's first page is planned there too, before the forced plan.
sub _explain ( $dbh, $statement, $options, $first = undef ) {
    my $flags =
      $options->{analyze}
      ? 'ANALYZE, BUFFERS, WAL, FORMAT JSON'
      : 'BUFFERS, FORMAT JSON';
    my ( $sql, @bind ) = @{$statement};

    $dbh->begin_work;
    my ( %plans, $error );
    try {
        if ($first) {
            my ( $first_sql, @first_bind ) = @{$first};
            $plans{first} =
              $dbh->selectrow_array( "EXPLAIN ($flags) $first_sql",
                undef, @first_bind );
        }
        $plans{plan} =
          $dbh->selectrow_array( "EXPLAIN ($flags) $sql", undef, @bind );
        $dbh->do('SET LOCAL enable_seqscan = off');
        $plans{forced} =
          $dbh->selectrow_array( "EXPLAIN (FORMAT JSON) $sql", undef, @bind );
    }
    catch ($caught) {
        $error = $caught;
    };
    $dbh->rollback;
    croak $error if defined $error;

    return \%plans;
}

sub _dry_run_report ( $endpoints, $options ) {
    my @reports;
    for my $endpoint ( @{$endpoints} ) {
        my $definition = _endpoint_definition($endpoint);
        push @reports,
          {
            endpoint   => $endpoint,
            status     => 'ok',
            purpose    => $definition->{purpose},
            sql_label  => $definition->{sql_label},
            violations => [],
            warnings   => [],
          };
    }

    return {
        status    => 'ok',
        mode      => 'dry-run',
        analyze   => $options->{analyze} ? 1 : 0,
        dataset   => { profile => $options->{profile} },
        endpoints => \@reports,
    };
}

sub _endpoint_definition ($endpoint) {
    return endpoint_definition($endpoint)
      // GPForum::X::Usage->throw( message => _usage() );
}

sub _text_report ($report) {
    my $text =
        'query_plan_evidence status='
      . $report->{status}
      . ' mode='
      . $report->{mode}
      . ' analyze='
      . $report->{analyze}
      . ' dataset_profile='
      . $report->{dataset}{profile} . "\n";

    for my $endpoint ( @{ $report->{endpoints} } ) {
        $text .= join q{ },
          'endpoint=' . $endpoint->{endpoint},
          'status=' . $endpoint->{status},
          'sql_label=' . $endpoint->{sql_label},
          'violations=' . list_text( $endpoint->{violations} ),
          'warnings=' . list_text( $endpoint->{warnings} ),
          _depth_text( $endpoint->{summary} ),
          "\n";
    }

    return $text;
}

# How deep a deep endpoint paged and what each page filtered, so a CI log
# shows whether the deep-page rule had anything to measure.
sub _depth_text ($summary) {
    my $depth = $summary ? $summary->{depth} : undef;
    return if !$depth;

    my @text = ( 'depth=' . $depth->{rows_before_cursor} );
    if ( defined $depth->{rows_removed_deep_page} ) {
        push @text, sprintf 'rows_removed=%.0f/%.0f',
          @{$depth}{qw(rows_removed_first_page rows_removed_deep_page)};
    }

    return @text;
}

sub _options (@arguments) {
    my $usage = _usage();

    return GPForum::Command::Usage->parse_options(
        \@arguments,
        {
            analyze   => 1,
            check     => 0,
            dry_run   => 0,
            endpoints => [],
            format    => 'text',
            functions => 0,
            help      => 0,
            profile   => 'small',
        },
        {
            usage    => $usage,
            switches => \%SWITCH_OPTION,
            values   => {
                '--endpoint' => sub ( $options, $value ) {
                    push @{ $options->{endpoints} },
                      GPForum::Command::Usage->option_choice( $value,
                        [ endpoint_names(), function_endpoint_names() ],
                        $usage );
                },
                '--profile' => sub ( $options, $value ) {
                    $options->{profile} =
                      GPForum::Command::Usage->option_choice( $value,
                        [ GPForum::Command::PerformanceSeed->profiles ],
                        $usage );
                },
            },
        },
    );
}

# Public so the Mojolicious command adapter in GPForum::CLI can show the same
# text `--help` prints, instead of a second copy that drifts.
sub usage_text ($class) {
    return _usage();
}

sub _usage {
    return
        'Usage: '
      . GPForum::Command::Usage->program
      . ' [--dry-run] [--json] [--check] [--analyze] [--no-analyze] [--functions] [--profile small|medium|hot-thread] [--endpoint NAME] ...';
}

1;
