# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::QrCode;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::X::Argument;

our $VERSION = '0.001';

# ADR 0142: the enrollment page draws the authenticator link as a QR code
# here, on the server, so the secret it carries never leaves the forum for a
# third-party image service. ISO/IEC 18004, the subset that link needs: byte
# mode, error correction level M, versions 1 to 10 (up to 213 bytes).

# Per version: the error correction codewords of each block, and the blocks
# as [ count, data codewords ] groups.
const my %BLOCKS => (
    1  => [ 10, [ [ 1, 16 ] ] ],
    2  => [ 16, [ [ 1, 28 ] ] ],
    3  => [ 26, [ [ 1, 44 ] ] ],
    4  => [ 18, [ [ 2, 32 ] ] ],
    5  => [ 24, [ [ 2, 43 ] ] ],
    6  => [ 16, [ [ 4, 27 ] ] ],
    7  => [ 18, [ [ 4, 31 ] ] ],
    8  => [ 22, [ [ 2, 38 ], [ 2, 39 ] ] ],
    9  => [ 22, [ [ 3, 36 ], [ 2, 37 ] ] ],
    10 => [ 26, [ [ 4, 43 ], [ 1, 44 ] ] ],
);
const my %ALIGNMENT => (
    1  => [],
    2  => [ 6, 18 ],
    3  => [ 6, 22 ],
    4  => [ 6, 26 ],
    5  => [ 6, 30 ],
    6  => [ 6, 34 ],
    7  => [ 6, 22, 38 ],
    8  => [ 6, 24, 42 ],
    9  => [ 6, 26, 46 ],
    10 => [ 6, 28, 50 ],
);
const my $LAST_VERSION      => 10;
const my $LONG_COUNT_FROM   => 10;
const my $SHORT_COUNT_BITS  => 8;
const my $LONG_COUNT_BITS   => 16;
const my $BYTE_MODE         => 4;
const my $MODE_BITS         => 4;
const my $BYTE_BITS         => 8;
const my $BYTE_MASK         => 0xFF;
const my $HIGH_BIT          => 7;
const my @PAD_BYTES         => ( 0xEC, 0x11 );
const my $FIELD_POLYNOMIAL  => 0x11D;
const my $SIZE_BASE         => 17;
const my $SIZE_STEP         => 4;
const my $TIMING            => 6;
const my $FINDER            => 7;
const my $FINDER_RING       => 3;
const my $ALIGNMENT_RING    => 2;
const my $FORMAT_POLYNOMIAL => 0x537;
const my $FORMAT_REMAINDER  => 10;
const my $FORMAT_TOP        => 9;
const my $FORMAT_MASK       => 0x54_12;
const my $FORMAT_BITS       => 15;
const my $FORMAT_LEVEL_M    => 0;
const my $MASK_BITS         => 3;
const my $FORMAT_FIRST_RUN  => 6;
const my $FORMAT_CORNER     => 8;
const my $FORMAT_SECOND_RUN => 7;
const my $VERSION_FROM      => 7;
const my $VERSION_POLY      => 0x1F25;
const my $VERSION_REMAINDER => 12;
const my $VERSION_TOP       => 11;
const my $VERSION_BITS      => 18;
const my $VERSION_OFFSET    => 11;
const my $VERSION_ROWS      => 3;
const my $DARK_ROW_OFFSET   => 9;
const my $MASKS             => 8;
const my $QUIET_ZONE        => 4;
const my $MODULE_PIXELS     => 4;

# The penalty rules of ISO/IEC 18004 section 7.8.3.
const my $RUN_PENALTY      => 3;
const my $RUN_FROM         => 5;
const my $BLOCK_PENALTY    => 3;
const my $FINDER_PENALTY   => 40;
const my $BALANCE_PENALTY  => 10;
const my $BALANCE_STEP     => 5;
const my $HALF_PERCENT     => 50;
const my $PERCENT          => 100;
const my $FINDER_LOOKALIKE => qr/ (?: 0000 1011101 | 1011101 0000 ) /msx;

# The finder-like pattern search overlaps: 00001011101 and 10111010000 share
# a run, so each match is counted by its start, one position at a time.
const my $FINDER_WIDTH => 11;

# The modules as rows of 0 (light) and 1 (dark), the quiet zone left out.
sub matrix ( $class, $text ) {
    my $bytes   = $class->_bytes($text);
    my $version = $class->_version_for( length $bytes )
      // GPForum::X::Argument->throw(
        message => 'qr code text is longer than version 10 holds' );
    my $codewords =
      _interleaved( $version, _data_codewords( $version, $bytes ) );
    my $symbol = _function_patterns($version);
    _place( $symbol, $codewords );

    my ( $best, $best_penalty );
    for my $mask ( 0 .. $MASKS - 1 ) {
        my $candidate = _masked( $symbol, $mask );
        _draw_format( $candidate, $mask );
        my $penalty = _penalty( $candidate->{modules} );
        if ( !defined $best_penalty || $penalty < $best_penalty ) {
            ( $best, $best_penalty ) = ( $candidate, $penalty );
        }
    }

    return $best->{modules};
}

# The symbol as an SVG image: dark modules on a light square with its quiet
# zone, whatever the page's theme, as a scanner needs them.
sub svg ( $class, $text, $label ) {
    my $modules = $class->matrix($text);
    my $size    = @{$modules} + 2 * $QUIET_ZONE;
    my $pixels  = $size * $MODULE_PIXELS;

    # Each run of dark modules in a row is one rectangle: a fifth of the
    # bytes one square a module takes.
    my @path;
    for my $row ( 0 .. $#{$modules} ) {
        my $cells = $modules->[$row];
        my $start;
        for my $column ( 0 .. @{$cells} ) {
            my $dark = $column < @{$cells} && $cells->[$column];
            if ( $dark && !defined $start ) {
                $start = $column;
            }
            elsif ( !$dark && defined $start ) {
                my $run = $column - $start;
                push @path, sprintf 'M%d %dh%dv1h-%dz', $start + $QUIET_ZONE,
                  $row + $QUIET_ZONE, $run, $run;
                $start = undef;
            }
        }
    }

    return
        qq{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size"}
      . qq{ width="$pixels" height="$pixels" role="img"}
      . q{ aria-label="}
      . _attribute($label) . q{"}
      . q{ shape-rendering="crispEdges">}
      . qq{<rect width="$size" height="$size" fill="#fff"/>}
      . q{<path fill="#000" d="}
      . join( q{}, @path )
      . q{"/></svg>};
}

sub _attribute ($text) {
    my %entity = (
        q{&} => '&amp;',
        q{<} => '&lt;',
        q{>} => '&gt;',
        q{"} => '&quot;',
        q{'} => '&#39;',
    );
    ( my $escaped = $text // q{} ) =~ s/([&<>"'])/$entity{$1}/gmsx;

    return $escaped;
}

sub _bytes ( $, $text ) {
    my $bytes = $text // q{};
    utf8::encode($bytes);

    return $bytes;
}

sub _count_bits ($version) {
    return $version < $LONG_COUNT_FROM ? $SHORT_COUNT_BITS : $LONG_COUNT_BITS;
}

sub _data_capacity ($version) {
    my ( undef, $groups ) = @{ $BLOCKS{$version} };
    my $total = 0;
    for my $group ( @{$groups} ) {
        $total += $group->[0] * $group->[1];
    }

    return $total;
}

# The smallest version whose data codewords hold the mode, the count and
# the bytes; undef when none does.
sub _version_for ( $, $length ) {
    for my $version ( 1 .. $LAST_VERSION ) {
        my $bits = $MODE_BITS + _count_bits($version) + $length * $BYTE_BITS;
        return $version if $bits <= _data_capacity($version) * $BYTE_BITS;
    }

    return undef;
}

# The mode, the count, the bytes, the terminator and the padding, as the
# version's data codewords.
sub _data_codewords ( $version, $bytes ) {
    my $bits = sprintf '%0*b%0*b', $MODE_BITS, $BYTE_MODE,
      _count_bits($version), length $bytes;
    $bits .= join q{}, map { sprintf '%08b', ord } split //msx, $bytes;
    my $capacity = _data_capacity($version) * $BYTE_BITS;
    my $space    = $capacity - length $bits;
    $bits .= '0' x ( $space < $MODE_BITS ? $space : $MODE_BITS );
    $bits .= '0' x ( ( $BYTE_BITS - length($bits) % $BYTE_BITS ) % $BYTE_BITS );

    my @codewords = map { oct "0b$_" } unpack '(A8)*', $bits;
    my $pad       = 0;
    while ( @codewords < _data_capacity($version) ) {
        push @codewords, $PAD_BYTES[ $pad++ % @PAD_BYTES ];
    }

    return \@codewords;
}

# The data split into its blocks, each followed by its Reed-Solomon
# codewords, read out column by column: the data first, then the
# correction.
sub _interleaved ( $version, $data ) {
    my ( $ec_length, $groups ) = @{ $BLOCKS{$version} };
    my $divisor = _divisor($ec_length);
    my ( @data_blocks, @ec_blocks );
    my $offset = 0;
    for my $group ( @{$groups} ) {
        my ( $count, $length ) = @{$group};
        for ( 1 .. $count ) {
            my @block = @{$data}[ $offset .. $offset + $length - 1 ];
            $offset += $length;
            push @data_blocks, \@block;
            push @ec_blocks,   _remainder( \@block, $divisor );
        }
    }

    my @result;
    my $longest = @{ $data_blocks[-1] };
    for my $index ( 0 .. $longest - 1 ) {
        push @result, map { $index < @{$_} ? $_->[$index] : () } @data_blocks;
    }
    for my $index ( 0 .. $ec_length - 1 ) {
        push @result, map { $_->[$index] } @ec_blocks;
    }

    return \@result;
}

# Multiplication in GF(2^8) modulo x^8 + x^4 + x^3 + x^2 + 1.
sub _multiply ( $left, $right ) {
    my $product = 0;
    for my $bit ( reverse 0 .. $HIGH_BIT ) {
        $product =
          ( $product << 1 ) ^ ( ( $product >> $HIGH_BIT ) * $FIELD_POLYNOMIAL );
        $product ^= ( ( $right >> $bit ) & 1 ) * $left;
    }

    return $product;
}

# The generator polynomial of the given degree, its leading term left out.
sub _divisor ($degree) {
    my @result = ( (0) x ( $degree - 1 ), 1 );
    my $root   = 1;
    for ( 1 .. $degree ) {
        for my $index ( 0 .. $degree - 1 ) {
            $result[$index] = _multiply( $result[$index], $root );
            if ( $index + 1 < $degree ) {
                $result[$index] ^= $result[ $index + 1 ];
            }
        }
        $root = _multiply( $root, 2 );
    }

    return \@result;
}

sub _remainder ( $data, $divisor ) {
    my @result = (0) x @{$divisor};
    for my $byte ( @{$data} ) {
        my $factor = $byte ^ shift @result;
        push @result, 0;
        for my $index ( 0 .. $#result ) {
            $result[$index] ^= _multiply( $divisor->[$index], $factor );
        }
    }

    return \@result;
}

# The empty symbol with its finders, separators, timing patterns, alignment
# patterns, version information and dark module drawn, each marked as a
# function module the data and the masks leave alone.
sub _function_patterns ($version) {
    my $size   = $SIZE_BASE + $SIZE_STEP * $version;
    my $symbol = {
        size     => $size,
        modules  => [ map { [ (0) x $size ] } 1 .. $size ],
        function => [ map { [ (0) x $size ] } 1 .. $size ],
    };
    for my $index ( 0 .. $size - 1 ) {
        my $dark = $index % 2 == 0 ? 1 : 0;
        _set( $symbol, $TIMING, $index,  $dark );
        _set( $symbol, $index,  $TIMING, $dark );
    }
    _finder( $symbol, $FINDER_RING,             $FINDER_RING );
    _finder( $symbol, $FINDER_RING,             $size - 1 - $FINDER_RING );
    _finder( $symbol, $size - 1 - $FINDER_RING, $FINDER_RING );
    _alignments( $symbol, $version );

    # The format areas are reserved now and drawn once the mask is chosen.
    _draw_format( $symbol, 0 );
    _draw_version( $symbol, $version );

    return $symbol;
}

sub _set ( $symbol, $row, $column, $dark ) {
    $symbol->{modules}[$row][$column]  = $dark ? 1 : 0;
    $symbol->{function}[$row][$column] = 1;

    return;
}

# A finder centred on the module given, with its light separator.
sub _finder ( $symbol, $center_row, $center_column ) {
    my $reach = $FINDER_RING + 1;
    for my $row_offset ( -$reach .. $reach ) {
        for my $column_offset ( -$reach .. $reach ) {
            my ( $row, $column ) =
              ( $center_row + $row_offset, $center_column + $column_offset );
            next
              if $row < 0
              || $column < 0
              || $row >= $symbol->{size}
              || $column >= $symbol->{size};
            my $distance = _max( abs $row_offset, abs $column_offset );
            _set( $symbol, $row, $column,
                $distance != 2 && $distance != $reach ? 1 : 0 );
        }
    }

    return;
}

sub _alignments ( $symbol, $version ) {
    my @positions = @{ $ALIGNMENT{$version} };
    my $final     = $#positions;
    for my $row_index ( 0 .. $final ) {
        for my $column_index ( 0 .. $final ) {

            # The three corners the finders hold.
            next
              if ( $row_index == 0 && $column_index == 0 )
              || ( $row_index == 0 && $column_index == $final )
              || ( $row_index == $final && $column_index == 0 );
            my ( $row, $column ) =
              ( $positions[$row_index], $positions[$column_index] );
            for my $row_offset ( -$ALIGNMENT_RING .. $ALIGNMENT_RING ) {
                for my $column_offset ( -$ALIGNMENT_RING .. $ALIGNMENT_RING ) {
                    my $distance = _max( abs $row_offset, abs $column_offset );
                    _set(
                        $symbol,
                        $row + $row_offset,
                        $column + $column_offset,
                        $distance != 1 ? 1 : 0
                    );
                }
            }
        }
    }

    return;
}

sub _max ( $left, $right ) {
    return $left > $right ? $left : $right;
}

sub _bit ( $value, $index ) {
    return ( $value >> $index ) & 1;
}

# The 15 format bits (level M and the mask, with their BCH code) in both of
# their places, and the dark module beside the lower one.
sub _draw_format ( $symbol, $mask ) {
    my $data      = ( $FORMAT_LEVEL_M << $MASK_BITS ) | $mask;
    my $remainder = $data;
    for ( 1 .. $FORMAT_REMAINDER ) {
        $remainder = ( $remainder << 1 ) ^
          ( ( $remainder >> $FORMAT_TOP ) * $FORMAT_POLYNOMIAL );
    }
    my $bits = ( ( $data << $FORMAT_REMAINDER ) | $remainder ) ^ $FORMAT_MASK;
    my $size = $symbol->{size};

    for my $index ( 0 .. $FORMAT_FIRST_RUN - 1 ) {
        _set( $symbol, $index, $FORMAT_CORNER, _bit( $bits, $index ) );
    }
    _set( $symbol, $FORMAT_SECOND_RUN, $FORMAT_CORNER,
        _bit( $bits, $FORMAT_FIRST_RUN ) );
    _set( $symbol, $FORMAT_CORNER, $FORMAT_CORNER,
        _bit( $bits, $FORMAT_SECOND_RUN ) );
    _set( $symbol, $FORMAT_CORNER, $FORMAT_SECOND_RUN,
        _bit( $bits, $FORMAT_CORNER ) );
    for my $index ( $FORMAT_TOP .. $FORMAT_BITS - 1 ) {
        _set(
            $symbol, $FORMAT_CORNER,
            $FORMAT_BITS - 1 - $index,
            _bit( $bits, $index )
        );
    }

    for my $index ( 0 .. $FORMAT_CORNER - 1 ) {
        _set(
            $symbol, $FORMAT_CORNER,
            $size - 1 - $index,
            _bit( $bits, $index )
        );
    }
    for my $index ( $FORMAT_CORNER .. $FORMAT_BITS - 1 ) {
        _set(
            $symbol,        $size - $FORMAT_BITS + $index,
            $FORMAT_CORNER, _bit( $bits, $index )
        );
    }
    _set( $symbol, $size - $FORMAT_CORNER, $FORMAT_CORNER, 1 );

    return;
}

# From version 7, the version number and its BCH code in two 6 by 3
# blocks, beside the upper right and the lower left finders.
sub _draw_version ( $symbol, $version ) {
    return if $version < $VERSION_FROM;

    my $remainder = $version;
    for ( 1 .. $VERSION_REMAINDER ) {
        $remainder = ( $remainder << 1 ) ^
          ( ( $remainder >> $VERSION_TOP ) * $VERSION_POLY );
    }
    my $bits = ( $version << $VERSION_REMAINDER ) | $remainder;
    for my $index ( 0 .. $VERSION_BITS - 1 ) {
        my $near = $symbol->{size} - $VERSION_OFFSET + $index % $VERSION_ROWS;
        my $far  = int( $index / $VERSION_ROWS );
        my $dark = _bit( $bits, $index );
        _set( $symbol, $far,  $near, $dark );
        _set( $symbol, $near, $far,  $dark );
    }

    return;
}

# The codewords' bits in the zigzag of two-module columns, from the lower
# right corner, upwards and downwards in turn, skipping the vertical timing
# pattern and every function module. Modules left over stay light.
sub _place ( $symbol, $codewords ) {
    my $size  = $symbol->{size};
    my $total = @{$codewords} * $BYTE_BITS;
    my $index = 0;
    my $edge  = $size - 1;
    while ( $edge >= 1 ) {
        if ( $edge == $TIMING ) {
            $edge--;
        }
        my $upward = ( ( $edge + 1 ) & 2 ) == 0;
        for my $step ( 0 .. $size - 1 ) {
            my $row = $upward ? $size - 1 - $step : $step;
            for my $column ( $edge, $edge - 1 ) {
                next if $symbol->{function}[$row][$column] || $index >= $total;
                $symbol->{modules}[$row][$column] = _bit(
                    $codewords->[ int( $index / $BYTE_BITS ) ],
                    $HIGH_BIT - ( $index % $BYTE_BITS )
                );
                $index++;
            }
        }
        $edge -= 2;
    }

    return;
}

const my %MASK => (
    0 => sub ( $row, $column ) { return ( $row + $column ) % 2 == 0 },
    1 => sub ( $row, $column ) { return $row % 2 == 0 },
    2 => sub ( $row, $column ) { return $column % 3 == 0 },
    3 => sub ( $row, $column ) { return ( $row + $column ) % 3 == 0 },
    4 => sub ( $row, $column ) {
        return ( int( $row / 2 ) + int( $column / 3 ) ) % 2 == 0;
    },
    5 => sub ( $row, $column ) {
        return ( $row * $column ) % 2 + ( $row * $column ) % 3 == 0;
    },
    6 => sub ( $row, $column ) {
        return ( ( $row * $column ) % 2 + ( $row * $column ) % 3 ) % 2 == 0;
    },
    7 => sub ( $row, $column ) {
        return ( ( $row + $column ) % 2 + ( $row * $column ) % 3 ) % 2 == 0;
    },
);

# A copy of the symbol with the mask applied to every data module.
sub _masked ( $symbol, $mask ) {
    my $flip = $MASK{$mask};
    my $size = $symbol->{size};
    my $copy = {
        size     => $size,
        function => $symbol->{function},
        modules  => [ map { [ @{$_} ] } @{ $symbol->{modules} } ],
    };
    for my $row ( 0 .. $size - 1 ) {
        for my $column ( 0 .. $size - 1 ) {
            next
              if $symbol->{function}[$row][$column]
              || !$flip->( $row, $column );
            $copy->{modules}[$row][$column] ^= 1;
        }
    }

    return $copy;
}

# The modules of a column, top to bottom, as one string.
sub _column ( $modules, $column ) {
    return join q{}, map { $_->[$column] } @{$modules};
}

# Runs of five or more modules of one colour, 2 by 2 blocks of one colour,
# finder-like patterns in a row or a column, and an imbalance of dark and
# light: the lowest total is the mask to use.
sub _penalty ($modules) {
    my $size    = @{$modules};
    my @columns = map { _column( $modules, $_ ) } 0 .. $size - 1;
    my @rows    = map { join q{}, @{$_} } @{$modules};

    my $penalty = 0;
    for my $line ( @rows, @columns ) {
        while ( $line =~ / ( 0{$RUN_FROM,} | 1{$RUN_FROM,} ) /gmsx ) {
            $penalty += $RUN_PENALTY + length($1) - $RUN_FROM;
        }
        for my $start ( 0 .. length($line) - $FINDER_WIDTH ) {
            if (
                substr( $line, $start, $FINDER_WIDTH ) =~
                m/\A $FINDER_LOOKALIKE \z/msx )
            {
                $penalty += $FINDER_PENALTY;
            }
        }
    }

    my $dark = 0;
    for my $row ( 0 .. $size - 1 ) {
        for my $column ( 0 .. $size - 1 ) {
            my $colour = $modules->[$row][$column];
            $dark += $colour;
            next if $row == $size - 1 || $column == $size - 1;
            if (   $colour == $modules->[$row][ $column + 1 ]
                && $colour == $modules->[ $row + 1 ][$column]
                && $colour == $modules->[ $row + 1 ][ $column + 1 ] )
            {
                $penalty += $BLOCK_PENALTY;
            }
        }
    }
    my $deviation = abs $dark * $PERCENT / ( $size * $size ) - $HALF_PERCENT;

    return $penalty + $BALANCE_PENALTY * int( $deviation / $BALANCE_STEP );
}

1;

__END__

=head1 NAME

GPForum::Web::QrCode - QR codes drawn on the server, as SVG.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $svg = GPForum::Web::QrCode->svg( $otpauth_uri, 'Scan with your app' );
    my $modules = GPForum::Web::QrCode->matrix('text');

=head1 DESCRIPTION

ADR 0142. The authenticator link of two-step sign-in carries the member's
secret, so its QR code is drawn here rather than by any outside service.
The encoder covers what that link needs from ISO/IEC 18004: byte mode,
error correction level M, versions 1 to 10 (up to 213 bytes of UTF-8),
with the mask chosen by the standard's penalty rules.

=head1 SUBROUTINES/METHODS

=head2 matrix

Takes the text and returns the symbol's modules, without the quiet zone,
as an array of rows of C<0> (light) and C<1> (dark).

=head2 svg

Takes the text and the image's accessible label and returns an inline SVG
image: dark modules on a light square with a four-module quiet zone, four
pixels a module.

=head1 DIAGNOSTICS

Text longer than version 10 holds throws L<GPForum::X::Argument>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Const::Fast>, L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Only byte mode and level M are written, and nothing past version 10.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
