# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
## no critic (NamingConventions::Capitalization) -- Mojolicious generator namespace
package Mojolicious::Command::Author::generate::gpforum_service;
## use critic

use Mojo::Base 'Mojolicious::Command', -signatures;
use v5.40;

use Const::Fast;
use List::Util qw(any max);
use Perl::Tidy;
use Carp       qw(croak);
use Fcntl      qw(O_WRONLY O_CREAT O_EXCL);
use Mojo::File qw(path);

our $VERSION = '0.001';
const my $INITIAL_VERSION      => 999;
const my $MAXIMUM_ENTRY_LENGTH => 60;
has description =>
'Generate a GPForum service, SQL API migration, catalogue entry and integration test';
has usage =>
  "Usage: mojo generate gpforum-service Forum::Name [--root DIRECTORY]\n";

sub _plan ( $self, $name = undef, @arguments ) {
    croak $self->usage
      if !defined $name
      || $name !~
      /\A[[:upper:]][[:alnum:]]*(?:::[[:upper:]][[:alnum:]]*)+\z/amsx;
    my $root = path(q{.});
    if (@arguments) {
        croak $self->usage if @arguments != 2 || $arguments[0] ne '--root';
        $root = path( $arguments[1] );
    }
    my $catalogue =
      $root->child('lib/GPForum/Infrastructure/SqlFunctionCatalogue.pm');
    croak 'not a GPForum checkout' if !-f $catalogue;
    my $entry  = _entry_name($name);
    my $module = $name =~ s{::}{/}grmsx;
    my $source = $catalogue->slurp;
    croak 'catalogue entry already exists' if $source =~ /\b\Q$entry\E\s*=>/msx;
    croak 'catalogue anchor is missing'
      if $source !~ /const[ ]my[ ]%FUNCTION[ ]=>[ ][(]/msx;
    my @versions =
      map { $_->basename =~ /\A([[:digit:]]+)_/msx ? $1 : () }
      @{ $root->child('migrations')->list };
    my $version   = ( max(@versions) // $INITIAL_VERSION ) + 1;
    my $migration = $root->child("migrations/${version}_${entry}.sql");
    my $service   = $root->child("lib/GPForum/Service/$module.pm");
    my $test      = $root->child("t/integration/postgres-generated-$entry.t");
    croak 'generated file already exists'
      if any { -e } ( $service, $migration, $test );
    my %variables = ( NAME => $name, ENTRY => $entry );
    my @files     = (
        [ $service,   _service() ],
        [ $migration, _migration() ],
        [ $test,      _test() ],
    );
    return {
        catalogue    => $catalogue,
        source       => $source,
        files        => \@files,
        variables    => \%variables,
        tidy_profile => $root->child('.perltidyrc'),
        entry        => $entry
    };
}

sub run ( $self, $name = undef, @arguments ) {
    my $plan = $self->_plan( $name, @arguments );
    my ( $catalogue, $source, $files, $variables, $entry ) =
      @{$plan}{qw(catalogue source files variables entry)};
    my @made;
    try {
        for my $file ( @{$files} ) {
            my ( $target, $text ) = @{$file};
            $text =~ s/@@(NAME|ENTRY)@@/$variables->{$1}/gmsx;
            if ( $target =~ /[.](?:pm|t)\z/msx ) {
                $text = _tidied( $text, $plan->{tidy_profile} );
            }
            $target->dirname->make_path;
            sysopen my $handle, $target, O_WRONLY | O_CREAT | O_EXCL
              or croak "cannot create $target";
            push @made, $target;
            print {$handle} $text or croak "cannot write $target";
            close $handle         or croak "cannot close $target";
        }
        croak 'catalogue changed while generating'
          if $catalogue->slurp ne $source;
        my $addition =
"\n    $entry => { version => 2, parameters => [actor => 'uuid'], json => ['result'] },";
        $source =~ s/(const[ ]my[ ]%FUNCTION[ ]=>[ ][(])/$1$addition/msx;
        $catalogue->spew( _tidied( $source, $plan->{tidy_profile} ) );
    }
    catch ($error) {
        for my $file (@made) { $file->remove; }
        die $error;    ## no critic (ErrorHandling::RequireCarping) -- preserve the original failure after removing generated files
    };
    say "Created service, migration and test; registered $entry"
      or croak 'cannot print generated files';
    return;
}

sub _entry_name ($name) {
    my ($area) = split /::/msx, $name;
    $area = lc $area;
    if ( $area eq 'operations' ) {
        $area = 'ops';
    }
    my %areas = map { $_ => 1 }
      qw(admin attachment community forum identity moderation notification
      ops outbox partition portability privacy projection search session worker plugin);
    croak
'choose a service area from the SQL API (Forum, Identity, Operations, Admin, ...)'
      if !$areas{$area};
    my $entry = $name =~ s/::/_/grmsx;
    $entry =~ s/([[:lower:][:digit:]])([[:upper:]])/$1_$2/gmsx;
    $entry = lc $entry;
    $entry =~ s/\Aoperations_/ops_/msx;
    croak 'SQL function name is too long'
      if length($entry) > $MAXIMUM_ENTRY_LENGTH;
    return $entry;
}

sub _tidied ( $source, $profile ) {
    my ( $formatted, $diagnostic );
    my $status = Perl::Tidy::perltidy(
        source      => \$source,
        destination => \$formatted,
        stderr      => \$diagnostic,
        perltidyrc  => -f $profile ? "$profile" : \q{--maximum-line-length=80},
    );
    croak "cannot format generated Perl: $diagnostic" if $status;
    return $formatted;
}

sub _service {
    return <<'PERL';
# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Service::@@NAME@@;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use GPForum::Infrastructure::SqlFunction;
our $VERSION = '0.001';
__PACKAGE__->requires('schema');
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema($self->schema);
};
sub execute ($self, $actor) {
    return $self->functions->rows('@@ENTRY@@', {actor => $actor})->[0]{result};
}
1;
__END__
=head1 NAME

GPForum::Service::@@NAME@@ - SQL API service.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::@@NAME@@->new(schema => $schema);
    my $result = $service->execute($actor_id);

=head1 DESCRIPTION

Uses the versioned @@ENTRY@@ catalogue contract. Add authorization in SQL
before this API accesses application data.

=head1 SUBROUTINES/METHODS

=head2 execute

Takes the actor UUID and returns the decoded result document.

=head1 DIAGNOSTICS

SQL exceptions propagate to the caller.

=head1 CONFIGURATION AND ENVIRONMENT

Requires a PostgreSQL schema collaborator.

=head1 DEPENDENCIES

L<GPForum::Base> and L<GPForum::Infrastructure::SqlFunction>.

=head1 INCOMPATIBILITIES

Requires Perl 5.40 or newer.

=head1 BUGS AND LIMITATIONS

The initial contract accesses no data. Add domain behavior and authorization.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
PERL
}

sub _migration {
    return <<'SQL';
-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause
BEGIN;
SET LOCAL lock_timeout = '1s';
CREATE FUNCTION api.@@ENTRY@@_v1(p_actor uuid)
RETURNS TABLE(result jsonb)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    -- Add authorization before reading or changing application data.
    -- This initial contract returns an empty document and accesses no data.
    SELECT '{}'::jsonb
$$;
REVOKE EXECUTE ON FUNCTION api.@@ENTRY@@_v1(uuid) FROM PUBLIC;
CREATE FUNCTION api.@@ENTRY@@_v2(p_actor uuid)
RETURNS TABLE(result jsonb)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.@@ENTRY@@_v1(p_actor); $$;
REVOKE EXECUTE ON FUNCTION api.@@ENTRY@@_v2(uuid) FROM PUBLIC;
COMMIT;
SQL
}

sub _test {
    return <<'PERL';
# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use lib 'lib', 't/lib';
use GPForum::Test::PgDatabase;
use GPForum::Service::@@NAME@@;
our $VERSION = '0.001';
if (!GPForum::Test::PgDatabase->admin_dsn) {
    plan skip_all => 'run make integration for temporary PostgreSQL';
}
my $database = GPForum::Test::PgDatabase->fresh;
my $service = GPForum::Service::@@NAME@@->new(schema => $database->schema);
is_deeply($service->execute(undef), {}, 'SQL result is decoded through the catalogue');
done_testing();
1;
PERL
}

1;
