# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use Cwd        qw(getcwd);
use English    qw(-no_match_vars);
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use Mojo::File qw(path);
use Test::More;

our $VERSION = '0.001';

const my $EXIT_SHIFT => 8;

# A service that reads a resultset, written here rather than copied from
# lib/: the services there move to the function layer one by one, and a
# copied one would stop having the violation this test needs.
const my $SAMPLE => <<'PERL';
package GPForum::Service::Example::Sample;

use Mojo::Base -base, -signatures;
use v5.40;

sub names ($self) {
    return [ map { $_->name } $self->schema->resultset('Example')->all ];
}

1;
PERL

# script/architecture-policies is a ratchet both ways: a violation its
# inventory does not hold fails, and so does a listed one no longer seen --
# which it never said, so edited subs left their old keys behind and the
# inventory only grew. On a scratch tree of one file with a known violation.

{
    my $checkout = getcwd();
    my $tree     = path( tempdir( CLEANUP => 1 ) );
    my $sample   = 'lib/GPForum/Service/Example/Sample.pm';
    $tree->child($sample)->dirname->make_path;
    $tree->child($sample)->spew($SAMPLE);
    $tree->child('etc')->make_path;
    my $inventory = $tree->child('etc/architecture-policy-baseline.json');

    $inventory->spew('{}');
    my $unlisted = _ratchet( $checkout, $tree );
    is( $unlisted->{status}, 1, 'a violation the inventory lacks fails' );
    like(
        $unlisted->{output},
        qr/outside [ ] the [ ] reviewed/msx,
        'saying it is outside the inventory'
    );

    my $listed = _ratchet( $checkout, $tree, '--inventory' );
    $inventory->spew( $listed->{output} );
    is( _ratchet( $checkout, $tree )->{status},
        0, 'the inventory it writes passes' );

    my $sample_file  = $tree->child($sample);
    my $original     = $sample_file->slurp;
    my $async_prefix = "async sub native_p { return 1; }\n";
    $sample_file->spew( $async_prefix . $original );
    is( _ratchet( $checkout, $tree )->{status},
        0, 'async declarations preserve existing boundary fingerprints' );
    $sample_file->spew(
            'async sub forbidden_p { $self->schema->resultset("Example"); }'
          . "\n"
          . $original );
    is( _ratchet( $checkout, $tree )->{status},
        1, 'a new boundary violation inside an async body is rejected' );
    $sample_file->spew($original);

    $inventory->spew(
        $listed->{output} =~ s/\A [{]/{"GPForum|gone|0": 1,/rmsx );
    my $stale = _ratchet( $checkout, $tree );
    is( $stale->{status}, 1, 'a listed violation no longer seen fails too' );
    like(
        $stale->{output},
        qr/no [ ] longer [ ] observed .* GPForum[|]gone[|]0/msx,
        'naming the entry to drop'
    );
}

done_testing();

sub _ratchet ( $checkout, $tree, @arguments ) {
    my $directory = getcwd();
    chdir "$tree" or croak "chdir $tree: $OS_ERROR";
    my $pid =
      open3( my $input, my $output, undef, $EXECUTABLE_NAME,
        "-I$checkout/lib", "$checkout/script/architecture-policies",
        @arguments );
    close $input or croak 'close the input';
    my $text = do { local $INPUT_RECORD_SEPARATOR = undef; <$output> };
    close $output or croak 'close the output';
    waitpid $pid, 0;
    chdir $directory or croak "chdir back: $OS_ERROR";

    return { output => $text // q{}, status => $CHILD_ERROR >> $EXIT_SHIFT };
}

1;
