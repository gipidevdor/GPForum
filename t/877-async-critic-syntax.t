# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use lib 'script/lib';
use GPForum::Quality::AsyncSyntax;
use PPI::Document;
use Perl::Critic;
our $VERSION = '0.001';
my $source = <<'PERL';
package Example;
use v5.40;
# async sub comment {}
my $string = 'async sub quoted {}';
my $heredoc = <<'TEXT';
async sub quoted_in_heredoc {}
TEXT
async
sub checked ($self) {
    $self->run if $self;
    return $self;
}
1;
PERL
my $document = PPI::Document->new( \$source );
is( $document->serialize, $source,
    'format and source policies inspect the exact original source' );
my $subs = $document->find('PPI::Statement::Sub');
is( scalar @{$subs}, 1, 'only the real async declaration is classified' );
is( $subs->[0]->name, 'checked',
    'the async body is checked as a named subroutine' );
my $critic = Perl::Critic->new(
    -profile  => q{},
    -only     => 1,
    -severity => 1,
    -include  => [
        qw(ControlStructures::ProhibitPostfixControls Modules::RequireEndWithOne CodeLayout::ProhibitTrailingWhitespace)
    ]
);
my @violations = $critic->critique($document);
ok(
    scalar( grep { $_->policy =~ /ProhibitPostfixControls/msx } @violations ),
    'a real violation inside an async body is still rejected'
);
ok(
    !scalar( grep { $_->policy =~ /RequireEndWithOne/msx } @violations ),
    'the final module value is recognized after the async body'
);
ok(
    !scalar(
        grep { $_->policy =~ /ProhibitTrailingWhitespace/msx } @violations
    ),
    'a modifier on its own line does not manufacture trailing whitespace'
);
done_testing();
1;
