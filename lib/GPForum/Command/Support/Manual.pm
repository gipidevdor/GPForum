# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Command::Support::Manual;

use Mojo::Base -base, -signatures;
use v5.40;
use Carp       qw(croak);
use Mojo::File qw(path);
use Pod::Usage ();
use Pod::Man;

our $VERSION = '0.001';

sub pod ( $, $verb, $class ) {
    my $module = ( $class =~ s{::}{/}grmsx ) . '.pm';
    my $file   = $INC{$module};
    my $source = defined $file ? path($file)->slurp : q{};

    # CLI adapters delegate to Command::*; that module's POD explains the
    # operation. Commands implemented directly in CLI keep their own POD.
    my @delegated = $source =~ /^use[ ](GPForum::Command::[[:word:]:]+);/gmsx;
    my ($implementation) = grep {
        $_ ne 'GPForum::Command::Usage'
          && index( $_, 'GPForum::Command::Support::' ) != 0
    } @delegated;
    if ($implementation) {
        my $key = ( $implementation =~ s{::}{/}grmsx ) . '.pm';
        if ( defined $INC{$key} ) { $source = path( $INC{$key} )->slurp; }
    }
    my ($details) = $source =~ /^=head1[ ]DESCRIPTION\s*\n(.*)/msx;
    $details //= q{};
    $details =~ s/^=cut\s*\z//msx;
    my $usage = $class->new->usage =~ s/\bAPPLICATION\b/gpforum/grmsx;
    $usage =~ s/^/    /gmsx;
    my $description = $class->new->description;
    return
"=head1 NAME\n\ngpforum-$verb - $description\n\n=head1 SYNOPSIS\n\n$usage\n\n=head1 DESCRIPTION\n\n$details\n\n=cut\n";
}

sub text ( $self, $verb, $class ) {
    my $pod    = $self->pod( $verb, $class );
    my $text   = q{};
    my $parser = Pod::Usage->new( USAGE_OPTIONS => { -verbose => 2 } );
    $parser->select(q{.*});
    $parser->output_string( \$text );
    $parser->parse_string_document($pod);
    return $text;
}

sub man ( $self, $verb, $class, $destination ) {
    my $pod = $self->pod( $verb, $class );
    open my $input, '<', \$pod or croak 'cannot read command POD';
    Pod::Man->new(
        name    => "gpforum-$verb",
        section => 1,
        release => 'GPForum',
        date    => q{}
    )->parse_from_file( $input, $destination );
    close $input or croak 'cannot close command POD';
    return;
}

1;

__END__

=head1 NAME

GPForum::Command::Support::Manual - CLI help and man pages from executable usage and module POD.

=head1 DESCRIPTION

C<text> uses Pod::Usage without an external perldoc. C<man> uses Pod::Man,
the renderer behind pod2man. Both combine the CLI adapter's actual usage
with its Command module's embedded POD, so there is no separately maintained
copy of options. Commands implemented directly in CLI use their own POD.

=head1 VERSION

Version 0.001.

=head1 DIAGNOSTICS

Throws on unreadable source or output failure.

=head1 CONFIGURATION AND ENVIRONMENT

Reads loaded CLI adapters and their delegated Command module POD; no settings file is needed.

=head1 DEPENDENCIES

Pod::Usage, Pod::Man and Mojo::File.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Actual usage is available for every adapter; explanatory prose requires embedded module POD.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=head1 SYNOPSIS

    my $text = $manual->text( backup => $command_class );

=head1 SUBROUTINES/METHODS

=head2 pod

Returns synthesized command POD from executable usage and embedded prose.

=head2 text

Renders that POD with Pod::Usage without changing selected output handles.

=head2 man

Writes a man page with Pod::Man, the renderer used by pod2man.

=cut
