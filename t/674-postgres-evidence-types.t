# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use File::Temp    qw(tempdir);
use JSON::MaybeXS qw(encode_json);
use Mojo::File    qw(path);
use Test::More;

use lib 'lib';

use GPForum::Service::Operations::EvidenceValidate;

our $VERSION = '0.001';

my $directory = tempdir( CLEANUP => 1 );
my $validator = GPForum::Service::Operations::EvidenceValidate->new;

for my $type (qw(postgres_diagnostics pitr_drill)) {
    my $complete = {
        check                => $type,
        status               => 'degraded',
        secrets_redacted     => \1,
        private_beta_claimed => 0,
        residual_gaps        =>
          ['An isolated CI drill does not prove production readiness.'],
    };
    my $report = _validated( "$type-complete", $complete );
    is( $report->{files}[0]{detected_type},
        $type, "$type is recognized as an operational report" );
    is( $report->{status}, 'pass', "$type metadata passes strict validation" );
    is_deeply( $report->{files}[0]{findings},
        [], "$type has no false unknown-type warning" );
    is( $complete->{status}, 'degraded',
        "$type schema validation preserves the report's measurement status" );

    my $missing =
      _validated( "$type-incomplete", { check => $type, status => 'ok' } );
    is( $missing->{status}, 'fail',
        "$type cannot omit required reporting metadata" );
    like(
        join( q{,}, map { $_->{code} } @{ $missing->{files}[0]{findings} } ),
        qr/missing_secrets_redacted/msx,
        "$type requires explicit redaction evidence"
    );

    my $unsafe = _validated( "$type-unsafe",
        { %{$complete}, password => 'unsafe-fixture' } );
    is( $unsafe->{status}, 'fail', "$type rejects secret-bearing output" );

    my $claim =
      _validated( "$type-claim", { %{$complete}, private_beta_claimed => 1 } );
    is( $claim->{status}, 'fail', "$type rejects a readiness claim" );
}

done_testing();

sub _validated ( $name, $value ) {
    my $file = path( $directory, "$name.json" );
    $file->spew( encode_json($value) );

    return $validator->run( { paths => [ $file->to_string ], strict => 1 } );
}

1;
