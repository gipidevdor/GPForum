# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Migration::Plan;

use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::File qw(path);

use GPForum::X::Config;

our $VERSION = '0.001';

has directory => sub { return path('migrations'); };

sub files ($self) {
    my $directory = path( $self->directory );

    if ( !-d $directory->to_string ) {
        GPForum::X::Config->throw(
            message => "migration directory not found: $directory" );
    }

    my @files = sort {
        _version_from_file($a) <=> _version_from_file($b)
          || $a->basename cmp $b->basename
    } grep { $_->basename =~ /\A [[:digit:]]+ [_] .+ [.] sql \z/msx }
      @{ $directory->list_tree->to_array };

    my %seen;
    for my $file (@files) {
        my $version = 0 + _version_from_file($file);
        if ( exists $seen{$version} ) {
            GPForum::X::Config->throw( message =>
                  "duplicate migration version: $seen{$version} and $file" );
        }
        $seen{$version} = $file;
    }

    return [ map { $_->to_string } @files ];
}

sub summary ($self) {
    my @summary;

    for my $migration_file ( @{ $self->files } ) {
        my $file = path($migration_file);
        push @summary,
          {
            file        => $file->to_string,
            version     => _version_from_file($file),
            description => _description_from_file($file),
          };
    }

    return \@summary;
}

sub _version_from_file ($file) {
    my ($version) = $file->basename =~ /\A ( [[:digit:]]+ ) [_] /msx;

    return $version;
}

sub _description_from_file ($file) {
    my $description = $file->basename;
    $description =~ s/\A [[:digit:]]+ [_]//msx;
    $description =~ s/[.] sql \z//msx;
    $description =~ s/[_]/ /gmsx;

    return $description;
}

1;

__END__

=head1 NAME

GPForum::Migration::Plan - Migration file discovery.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $summary = GPForum::Migration::Plan->new->summary;

=head1 DESCRIPTION

Discovers ordered SQL migration files for the GPForum PostgreSQL migration
framework.

=head1 SUBROUTINES/METHODS

=head2 files

Discovers SQL files recursively and returns paths in global numeric version
order, independent of their directory. Duplicate versions are refused.

=head2 summary

Returns version, description, and file metadata for migrations.

=head1 DIAGNOSTICS

Throws L<GPForum::X::Config> when the migration directory is missing or two
files claim the same numeric version.

=head1 CONFIGURATION AND ENVIRONMENT

No environment variables are read.

=head1 DEPENDENCIES

Uses L<Mojo::Base>, L<Mojo::File> and L<GPForum::X::Config>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Application is handled by L<GPForum::Migration::Runner>.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
