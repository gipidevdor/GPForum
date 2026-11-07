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

# In-memory collaborators have no external I/O and retain their state in
# this process. Persistent services run their entire transaction in one
# child: no transaction or database handle crosses an asynchronous yield.
sub service_p (
    $self, $service, $method, $input,
    $context = undef,
    $cancelled = undef
  )
{
    return $self->_call_p( $service, sub { return $service->$method($input); },
        $context, $cancelled );
}

sub service_args_p (
    $self, $service, $method, $arguments,
    $context = undef,
    $cancelled = undef
  )
{
    return $self->_call_p( $service,
        sub { return $service->$method( @{$arguments} ); },
        $context, $cancelled );
}

sub service_result_p (
    $self, $service, $method, $arguments,
    $context = undef,
    $cancelled = undef
  )
{
    my $primary = $service;
    if ( $service->isa('GPForum::Service::Notification::Workflow') ) {
        $primary =
            $method =~ /\Amark/msx
          ? $service->dispatcher
          : $service->preference_store;
    }
    elsif ( $service->isa('GPForum::Service::Admin::Workflow') ) {
        my $name =
            $method =~ /category/msx          ? 'category_store'
          : $method =~ /announcement/msx      ? 'announcement_store'
          : $method =~ /binding|bind_role/msx ? 'binding_store'
          : $method =~ /replay/msx            ? 'dead_letter_replay'
          : $method =~ /maintenance/msx       ? 'maintenance'
          :                                     'role_catalog';
        $primary = $service->$name // $service;
    }
    my $schema = _schema_in( $primary, {}, 0 );
    return $self->_call_p( $service,
        sub { return $service->$method( @{$arguments} ); },
        $context, $cancelled, $schema, 1 )->then(
        sub ( $result = undef ) {
            _load_rows($result);
            return $result;
        }
        );
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

=head2 shared, run_p, service_p, service_args_p, service_result_p

Run blocking services in bounded Mojolicious subprocesses.

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
