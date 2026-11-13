# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::FeatureProbe;
use v5.40;
use Carp    qw(croak);
use English qw(-no_match_vars);
use File::Spec;
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json encode_json);
use Test::Builder;
our $VERSION = '0.001';
my $installed;

sub import ($class) {
    return if $installed++;
    my $manifest = $ENV{GPFORUM_FEATURE_MANIFEST}
      or croak 'FeatureProbe needs a manifest';
    my $directory = $ENV{GPFORUM_FEATURE_TRACE_DIR}
      or croak 'FeatureProbe needs an evidence directory';
    my @rules = _rules($manifest);
    return if !@rules;
    my $original = Test::Builder->can('ok');
    my %recorded;
    no warnings 'redefine';    ## no critic (TestingAndDebugging::ProhibitNoWarnings) -- opt-in test evidence; production never loads this probe
    *Test::Builder::ok = sub ( $builder, $passed, $description = undef ) {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        my $actual = $passed ? 1 : 0;
        my $result = $original->( $builder, $actual, $description );
        if ( $actual && !$builder->in_todo && defined $description ) {
            _record( $directory, \@rules, \%recorded, $description );
        }
        return $result;
    };
    return;
}

sub _rules ($manifest) {
    my $catalogue = decode_json( path($manifest)->slurp );
    my $test      = File::Spec->rel2abs($PROGRAM_NAME);
    my @rules;
    for my $feature ( @{ $catalogue->{features} } ) {
        for my $proof ( @{ $feature->{proofs} } ) {
            next if File::Spec->rel2abs( $proof->{test} ) ne $test;
            push @rules,
              {
                feature => $feature->{id},
                proof   => $proof->{id},
                text    => $proof->{text}
              };
        }
    }
    return @rules;
}

sub _record ( $directory, $rules, $recorded, $description ) {
    for my $rule ( @{$rules} ) {
        next if index( $description, $rule->{text} ) < 0;
        my $key = "$rule->{feature}:$rule->{proof}";
        next if $recorded->{$key}++;
        path( $directory,
            'assertion-'
              . $PROCESS_ID . q{-}
              . scalar( keys %{$recorded} )
              . '.json' )->spew(
            encode_json(
                {
                    feature => $rule->{feature},
                    proof   => $rule->{proof},
                    test    => $PROGRAM_NAME
                }
            )
              );
    }
    return;
}
1;
