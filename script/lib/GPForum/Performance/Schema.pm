# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Performance::Schema;
use v5.40;
use B        qw(svref_2object SVp_IOK SVp_NOK);
use Exporter qw(import);
use JSON::PP;
use List::Util qw(any);
use POSIX      qw(isfinite);

# Bootstrap validation cannot depend on a CPAN constants package.
use constant MAX_STRING_LENGTH => 1_000_000;    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
our $VERSION   = '0.001';
our @EXPORT_OK = qw(schema_validate secrets is_number);

sub is_number ($value) {
    return 0 if !defined $value || ref $value;
    return !!( svref_2object( \$value )->FLAGS & ( SVp_IOK | SVp_NOK ) );
}

sub _type ( $value, $type ) {
    return ref $value eq 'HASH'      if $type eq 'object';
    return ref $value eq 'ARRAY'     if $type eq 'array';
    return JSON::PP::is_bool($value) if $type eq 'boolean';
    return !defined $value           if $type eq 'null';
    return defined $value && !ref $value && !is_number($value)
      if $type eq 'string';
    return is_number($value) if $type eq 'number';
    return is_number($value) && isfinite($value) && int $value == $value
      if $type eq 'integer';
    die "Unsupported schema type: $type\n";
}

sub _equal ( $left, $right ) {
    my $json = JSON::PP->new->canonical->allow_nonref;
    return $json->encode($left) eq $json->encode($right);
}

sub _reference ( $schema, $top ) {
    my $reference = $top;
    my $pointer   = $schema->{q{$ref}};
    die "Unsupported external schema reference\n" if $pointer !~ s{\A\#/}{}msx;
    for my $name ( split m{/}msx, $pointer ) {
        $reference = $reference->{$name};
    }
    return $reference;
}

sub _variant_valid ( $value, $branch, $options ) {
    my $okay = 0;
    try { schema_validate( $value, $branch, $options ); $okay = 1; }
    catch ($error) { $okay = 0; };
    return $okay;
}

sub _variants ( $value, $branches, $options ) {
    for my $branch ( @{$branches} ) {
        return 1 if _variant_valid( $value, $branch, $options );
    }
    die "$options->{path}: no schema variant matches\n";
}

sub _constraints ( $value, $schema, $path ) {
    my $types = $schema->{type} // [];
    if ( !ref $types ) { $types = [$types]; }
    die "$path: unexpected type\n"
      if @{$types} && !any { _type( $value, $_ ) } @{$types};
    _value_constraints( $value, $schema, $path );
    if ( is_number($value) ) {
        die "$path: invalid number\n"
          if !isfinite($value)
          || exists $schema->{minimum} && $value < $schema->{minimum};
    }
    if ( defined $value && !ref $value && !is_number($value) ) {
        _string( $value, $schema, $path );
    }
    return 1;
}

sub _value_constraints ( $value, $schema, $path ) {
    die "$path: invalid value\n"
      if exists $schema->{const} && !_equal( $value, $schema->{const} );
    die "$path: invalid value\n"
      if $schema->{enum} && !any { _equal( $value, $_ ) } @{ $schema->{enum} };
    return 1;
}

sub _string ( $value, $schema, $path ) {

    # JSON Schema patterns retain their own whitespace and anchor semantics.
    ## no critic (RegularExpressions::RequireExtendedFormatting, RegularExpressions::RequireLineBoundaryMatching, RegularExpressions::RequireDotMatchAnything)
    die "$path: invalid string\n"
      if exists $schema->{pattern} && $value !~ /$schema->{pattern}/;
    ## use critic
    die "$path: excessive string\n"
      if length $value > ( $schema->{maxLength} // MAX_STRING_LENGTH );
    return 1;
}

sub schema_validate ( $value, $schema, $options = {} ) {
    my $top       = $options->{top}  // $schema;
    my $path      = $options->{path} // q{$};
    my %permitted = map { $_ => 1 }
      qw($schema $id $defs $ref title description type required properties additionalProperties items minItems enum const anyOf minimum pattern maxLength);
    my @unknown = grep { !$permitted{$_} } keys %{$schema};
    die 'unsupported schema keywords: ' . join( ', ', @unknown ) . "\n"
      if @unknown;
    my $context = { top => $top, path => $path };
    if ( exists $schema->{q{$ref}} ) {
        return schema_validate( $value, _reference( $schema, $top ), $context );
    }
    if ( $schema->{anyOf} ) {
        return _variants( $value, $schema->{anyOf}, $context );
    }
    _constraints( $value, $schema, $path );
    if ( ref $value eq 'HASH' )  { _object( $value, $schema, $context ); }
    if ( ref $value eq 'ARRAY' ) { _array( $value, $schema, $context ); }
    return 1;
}

sub _object ( $value, $schema, $options ) {
    my $path    = $options->{path};
    my @missing = grep { !exists $value->{$_} } @{ $schema->{required} // [] };
    die "$path: missing " . join( ', ', sort @missing ) . "\n" if @missing;
    my $properties = $schema->{properties} // {};
    for my $name ( keys %{$value} ) {
        my $rule =
          exists $properties->{$name}
          ? $properties->{$name}
          : $schema->{additionalProperties} // JSON::PP::true;
        die "$path: unexpected $name\n" if JSON::PP::is_bool($rule) && !$rule;
        if ( ref $rule eq 'HASH' ) {
            schema_validate( $value->{$name}, $rule,
                { top => $options->{top}, path => "$path.$name" } );
        }
    }
    return 1;
}

sub _array ( $value, $schema, $options ) {
    die "$options->{path}: insufficient items\n"
      if @{$value} < ( $schema->{minItems} // 0 );
    for my $index ( 0 .. $#{$value} ) {
        schema_validate(
            $value->[$index],
            $schema->{items} // {},
            { top => $options->{top}, path => "$options->{path}\[$index\]" }
        );
    }
    return 1;
}

sub _sensitive_value ($value) {
    my @patterns = (
        qr/BEGIN\x20(?:RSA\x20|OPENSSH\x20)?PRIVATE\x20KEY/imsx,
        qr/(?:gh[pousr]_|github_pat_)[[:alnum:]_]{20,}/aimsx,
        qr/(?:password|passwd)=(?!\[redacted\](?:[;\s]|\z))([^;\s]+)/imsx,
        qr{postgres(?:ql)?://[^/\@\s]+:[^/\@\s]+\@}imsx,
    );
    return any { $value =~ $_ } @patterns;
}

sub secrets ($value) {
    if ( ref $value eq 'HASH' ) {
        for my $name ( keys %{$value} ) {
            my $item        = $value->{$name};
            my $credentials = qr/(?:password|passwd|secret)/imsx;
            my $headers     = qr/(?:token|credential|authorization|cookie)/imsx;
            my $sensitive   = qr/(?:$credentials|$headers)/imsx;
            die "Sensitive field in performance evidence\n"
              if $name =~ /\A(?:.*_)?$sensitive\z/imsx
              && defined $item
              && ( ref $item || $item ne '[redacted]' );
            secrets($item);
        }
    }
    elsif ( ref $value eq 'ARRAY' ) {
        for my $item ( @{$value} ) { secrets($item); }
    }
    elsif ( defined $value && !ref $value ) {
        die "Sensitive value in performance evidence\n"
          if _sensitive_value($value);
    }
    return 1;
}
1;
