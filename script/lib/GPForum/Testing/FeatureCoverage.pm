# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Testing::FeatureCoverage;
use v5.40;
use File::Spec;
use Mojo::File                       qw(path);
use Mojo::JSON                       qw(decode_json);
use GPForum::Performance::Operations qw(inventory);
our $VERSION = '0.001';

sub report ( $class, $manifest, $directory, $tests_passed, $routes = undef ) {
    my $catalogue = decode_json( path($manifest)->slurp );
    my ( $assertions, $http ) = _evidence($directory);
    my ( %mapped, @features, @invalid );
    for my $feature ( @{ $catalogue->{features} } ) {
        for my $route ( @{ $feature->{routes} } ) { $mapped{$route}++; }
        push @invalid,  _validate($feature);
        push @features, _feature( $feature, $assertions, $http );
    }
    $routes //= inventory()->{http};
    my %actual   = map       { $_ => 1 } @{$routes};
    my @unmapped = grep      { !$mapped{$_} } @{$routes};
    my @stale    = sort grep { !$actual{$_} || $mapped{$_} != 1 } keys %mapped;
    my @missing  = grep      { $_->{status} ne 'covered' } @features;
    return {
        schema_version => 1,
        status         => $tests_passed
          && !@missing
          && !@unmapped
          && !@stale
          && !@invalid ? 'ok' : 'fail',
        tests_passed              => $tests_passed ? 1 : 0,
        total                     => scalar @features,
        covered                   => scalar(@features) - scalar(@missing),
        unmapped_routes           => \@unmapped,
        stale_or_duplicate_routes => \@stale,
        invalid_manifest          => \@invalid,
        features                  => \@features,
        scope                     =>
'Executed successful non-TODO assertions plus required HTTP outcomes; every test must pass. External providers use controlled local fixtures.'
    };
}

sub _evidence ($directory) {
    my ( %assertions, %http );
    for my $file (
        path($directory)->list->grep(qr{/assertion-[^/]+[.]json\z}msx)->each )
    {
        my $proof = decode_json( $file->slurp );
        $assertions{"$proof->{feature}:$proof->{proof}"}
          { File::Spec->rel2abs( $proof->{test} ) } = 1;
    }
    for my $file (
        path($directory)->list->grep(qr{/samples-[[:digit:]]+[.]jsonl\z}msx)
        ->each )
    {
        for my $line ( split /\n/msx, $file->slurp ) {
            my $sample = decode_json($line);
            next if $sample->{kind} ne 'http';
            $http{ $sample->{operation} }{ $sample->{outcome} }
              { $sample->{test} } = 1;
        }
    }
    return ( \%assertions, \%http );
}

sub _validate ($feature) {
    my ( %requests, %proofs, @invalid );
    for my $request ( @{ $feature->{http} } ) {
        $requests{ $request->{route} }++;
    }
    for my $route ( @{ $feature->{routes} } ) {
        if ( ( $requests{$route} // 0 ) != 1 ) {
            push @invalid, "$feature->{id}:missing-or-duplicate-http:$route";
        }
        delete $requests{$route};
    }
    for my $extra ( sort keys %requests ) {
        push @invalid, "$feature->{id}:foreign-http:$extra";
    }
    for my $proof ( @{ $feature->{proofs} } ) {
        if (   $proofs{ $proof->{id} }++
            || !length( $proof->{text} // q{} )
            || !length( $proof->{test} // q{} ) )
        {
            push @invalid, "$feature->{id}:invalid-proof:$proof->{id}";
        }
    }
    return @invalid;
}

sub _feature ( $feature, $assertions, $http ) {
    my @missing;
    if ( !@{ $feature->{proofs} } ) {
        push @missing, 'no behavioral postcondition declared';
    }
    for my $proof ( @{ $feature->{proofs} } ) {
        my $key = "$feature->{id}:$proof->{id}";
        if ( !$assertions->{$key}{ File::Spec->rel2abs( $proof->{test} ) } ) {
            push @missing, "assertion:$proof->{id}";
        }
    }
    for my $request ( @{ $feature->{http} } ) {
        if ( !_observed( $request, $http ) ) {
            push @missing, "http:$request->{route}";
        }
    }
    return {
        id      => $feature->{id},
        title   => $feature->{title},
        status  => @missing ? 'missing' : 'covered',
        missing => \@missing,
        proofs  => scalar @{ $feature->{proofs} },
        http    => scalar @{ $feature->{http} }
    };
}

sub _observed ( $request, $http ) {
    for my $status ( @{ $request->{statuses} } ) {
        my $tests = $http->{ $request->{route} }{$status} // {};
        return 1
          if $request->{test}
          ? $tests->{ $request->{test} }
          : scalar keys %{$tests};
    }
    return 0;
}
1;
