# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::AsyncWork;

use Mojo::Base -base, -signatures;
use v5.40;
use Carp qw(croak);
use Const::Fast;
use GPForum::Infrastructure::Subprocess;
use Mojo::Promise;
use Scalar::Util qw(blessed reftype refaddr);
use Mojo::Loader qw(load_class);
use GPForum::Infrastructure::ResultRow;
use Storable      qw(nfreeze thaw);
use JSON::MaybeXS ();
use GPForum::Infrastructure::AsyncGate;
use GPForum::Log;

our $VERSION = '0.001';
const my $MAX_SCHEMA_DEPTH => 8;
our $IS_CHILD;

# True while cpu_p starts its child, so an observer of run_p (a test) can
# tell the CPU lane from any other child.
our $CPU_LANE;
has gate =>
  sub { return GPForum::Infrastructure::AsyncGate->new( concurrency => 1 ); };

sub shared ($class) {
    state $worker = $class->new;
    return $worker;
}

# CPU-bound page rendering must not wait behind a password check, a remote
# integration, or an archive operation. Each lane admits one child per worker.
sub rendering ($class) {
    state $renderer = $class->new;
    return $renderer;
}

sub run_p (
    $self, $work,
    $cancelled     = undef,
    $preserve_rows = 0,
    $context       = undef
  )
{
    my $log_context = GPForum::Log->request_context;
    return $self->gate->run_p(
        sub {
            croak 'asynchronous request closed before work started'
              if $cancelled && $cancelled->();

            # Private parent/child IPC must preserve the UTF-8 flag: JSON turns
            # arbitrary file bytes into characters. Only plain data is returned,
            # and exceptions are serialized as text, never with database handles.
            my $child = GPForum::Infrastructure::Subprocess->new(
                serialize => sub ($values) {
                    if ( ref $values->[0] ) { $values->[0] = "$values->[0]"; }
                    return nfreeze($values);
                },
                deserialize => \&thaw,
            );
            return $child->run_p(
                sub {
                    local $IS_CHILD = 1;    ## no critic (Variables::ProhibitLocalVars) -- child ownership lasts only for this subprocess callback
                    return GPForum::Log->in_context(
                        $log_context,
                        sub {
                            return _plain( scalar $work->(), $preserve_rows );
                        }
                    );
                }
            );
        },
        $context
    );
}

# CPU-bound or blocking system work (password hashing, image decoding,
# rendering, name resolution, OS snapshots) runs in a child so the event
# loop keeps serving. The child never touches
# PostgreSQL: its input is plain data and so is its answer. Database work
# belongs on the pooled asynchronous connections (SqlFunction rows_p,
# row_p, transaction_p), never in a child.
sub cpu_p (
    $self, $work,
    $cancelled     = undef,
    $preserve_rows = 0,
    $context       = undef
  )
{
    local $CPU_LANE = 1;    ## no critic (Variables::ProhibitLocalVars) -- marks only the synchronous start of this child
    return $self->run_p(
        sub {
            local $GPForum::Infrastructure::PgStorage::NO_DATABASE = 1;
            return $work->();
        },
        $cancelled,
        $preserve_rows,
        $context
    );
}

# The command-line job runner's lanes (GPForum::Service::Outbox::Dispatcher):
# a batch of claimed outbox rows is handed to a bounded number of children,
# each running its lane's handlers on its own connection. It is a process
# model for a background runner, not a request path: a web request never
# calls it (t/885-no-database-in-children.t holds that), and its children
# are per batch, never per query.
sub job_p ( $self, $service, $method, $arguments, $context = undef ) {
    my $schema = _schema_in( $service, {}, 0 );
    return $self->_call_p( $service,
        sub { return $service->$method( @{$arguments} ); },
        $context, undef, $schema, 1 )->then(
        sub ( $result = undef ) {
            _load_rows($result);
            return $result;
        }
        );
}

# Whether a service reaches PostgreSQL: its schema, or its store's, is a
# GPForum::Schema. call_p refuses such a service without a METHOD_p twin;
# in-memory doubles answer in process.
sub holds_database ( $class, $service ) {
    my $store = $service->can('store') ? $service->store : $service;
    my $schema =
      blessed($store) && $store->can('schema') ? $store->schema : undef;
    return blessed($schema) && $schema->isa('GPForum::Schema') ? 1 : 0;
}

sub _schema_in ( $value, $seen, $depth ) {
    return        if !ref $value || $depth > $MAX_SCHEMA_DEPTH;
    return        if $seen->{ refaddr($value) }++;
    return $value if blessed($value) && $value->isa('GPForum::Schema');

    return _service_schema( $value, $seen, $depth );
}

sub _service_schema( $value, $seen, $depth ) {

    # The service's primary persistence dependency decides isolation. Other
    # collaborators may contain unrelated application schemas (audit, mail,
    # command logging); scanning their entire object graphs changes ownership
    # of in-memory stores and loses their mutations in a child.
    if ( blessed($value) && $value->can('functions') ) {
        my $functions = $value->functions;
        return $functions->schema if $functions && $functions->can('schema');
    }
    if ( blessed($value) && $value->can('schema') ) {
        return $value->schema;
    }
    if ( blessed($value) ) {
        for my $name (
            qw(store inner post_store bookmark_store preference_store dispatcher workflow permission_engine)
          )
        {
            next if !$value->can($name);
            my $child = $value->$name;
            return _schema_in( $child, $seen, $depth + 1 ) if $child;
        }
    }
    return;
}

sub _load_rows ( $value, $seen = undef ) {
    return if !ref $value;
    $seen //= {};
    return if $seen->{ refaddr($value) }++;
    if ( blessed($value)
        && ref($value) =~
        /\AGPForum::Infrastructure::ResultRow(?:::\w+)*\z/msx )
    {
        my $error = load_class( ref $value );
        croak "$error" if $error;
    }
    return
      if blessed($value) && !$value->isa('GPForum::Infrastructure::ResultRow');
    my $kind = reftype($value);
    if ( $kind eq 'HASH' ) {
        for my $child ( values %{$value} ) { _load_rows( $child, $seen ); }
    }
    elsif ( $kind eq 'ARRAY' ) {
        for my $child ( @{$value} ) { _load_rows( $child, $seen ); }
    }
    return;
}

sub _call_p (
    $self, $service, $work, $context, $cancelled,
    $schema_hint = undef,
    $preserve_rows = 0
  )
{
    my $store  = $service->can('store') ? $service->store : $service;
    my $schema = $schema_hint
      // ( $store && $store->can('schema') ? $store->schema : undef );
    if ( blessed($schema) && $schema->isa('GPForum::Schema') ) {
        my $stats =
          $schema->storage->debug ? $schema->storage->debugobj : undef;
        if ($stats) { $context //= $stats->request_context; }
        return $self->run_p(
            sub {
                my $run = sub {
                    return _capture_work( $stats, $context, $work );
                };
                return $stats ? $stats->in_context( $context, $run ) : $run->();
            },
            $cancelled,
            $preserve_rows,
            $context
        )->then(
            sub ($result) {
                if ($stats) {
                    $stats->merge_work( $context, $result->{delta} );
                }
                _raise_result_error($result);
                return $result->{value};
            }
        );
    }
    return Mojo::Promise->resolve->then($work);
}

sub _raise_result_error($result) {
    if ( exists $result->{error} ) {
        my $error = $result->{error};
        if ( $result->{error_class} ) {
            my $class = $result->{error_class};
            croak 'invalid subprocess error class'
              if $class !~ /\AGPForum::X(?:::\w+)*\z/msx;
            my $loading = load_class($class);
            croak "$loading" if $loading;
            $class->throw( message => $error );
        }
        croak $error;
    }
    return;
}

sub _capture_work ( $stats, $context, $work ) {
    my $before = $stats ? $stats->work_snapshot($context) : {};
    my ( $value, $error, $error_class );
    try { $value = $work->(); }
    catch ($caught) {
        $error = "$caught";
        if ( blessed($caught) && $caught->isa('GPForum::X') ) {
            $error_class = ref $caught;
        }
    };
    my $after = $stats ? $stats->work_snapshot($context) : {};
    return {
        value => $value,
        defined($error)       ? ( error       => $error )       : (),
        defined($error_class) ? ( error_class => $error_class ) : (),
        delta => {
            map { $_ => $after->{$_} - $before->{$_} }
              keys %{$after}
        }
    };
}

sub _plain ( $value, $preserve_rows = 0 ) {
    return $value if !ref $value;
    return $value if JSON::MaybeXS::is_bool($value);
    if (   $preserve_rows
        && blessed($value)
        && $value->isa('GPForum::Infrastructure::ResultRow') )
    {
        # Native rows are data-only hashes. Their constructors may consume
        # flat columns or manufacture prefetched relationships; replaying them
        # would lose those relationships and overwrite the original values.
        return bless {
            map { $_ => _plain( $value->{$_}, $preserve_rows ) }
              keys %{$value}
          },
          ref $value;
    }
    if ( blessed($value) ) {
        croak 'subprocess result must contain data only'
          if !$value->can('get_columns');
        my %columns = $value->get_columns;
        my $columns = {
            map { $_ => _plain( $columns{$_}, $preserve_rows ) }
              keys %columns
        };
        $value = $columns;
    }
    return [ map { _plain( $_, $preserve_rows ) } @{$value} ]
      if reftype($value) eq 'ARRAY';
    return {
        map { $_ => _plain( $value->{$_}, $preserve_rows ) }
          keys %{$value}
      }
      if reftype($value) eq 'HASH';
    croak 'subprocess result must contain data only';
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::AsyncWork - Run blocking services in bounded Mojolicious subprocesses.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Infrastructure::AsyncWork->shared
      ->run_p(sub { return blocking_work(); });

=head1 DESCRIPTION

The per-worker shared executor allows one active child and a bounded queue. Persistent service transactions stay in one child; in-memory collaborators run on the next loop turn. Private trusted IPC preserves byte and character strings using Storable. Queued disconnected requests are skipped; active mutations finish normally.

=head1 SUBROUTINES/METHODS

=head2 cpu_p

Runs CPU-bound work in a child process that may not open a PostgreSQL
connection; any attempt croaks.

=head2 shared, rendering

The per-worker lanes: each admits one child at a time.

=head2 run_p

Runs a callback in a bounded child and resolves with its plain-data answer.
Modules use C<cpu_p>, which adds the no-database guard.

=head2 holds_database

Takes a service and answers whether it reaches PostgreSQL (its schema, or
its store's, is a L<GPForum::Schema>).

=head2 job_p

Runs a service method in a child for the command-line outbox runner's
lanes, one child per lane and batch. Web requests never use it.

=head1 DIAGNOSTICS

Failures reject promises. HTTP callers finish or reject their response through the controller's request context.

=head1 CONFIGURATION AND ENVIRONMENT

Runtime limits have safe built-in defaults. No environment setting is required.

=head1 DEPENDENCIES

Mojolicious and the modules named in the source.

=head1 INCOMPATIBILITIES

HTTP callers consume promises without starting a nested event loop.

=head1 BUGS AND LIMITATIONS

Admission is bounded per web worker, not across multiple hosts. CLI workflows keep their synchronous interfaces.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
