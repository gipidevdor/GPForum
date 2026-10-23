# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package Perl::Critic::Policy::GPForum::ResultsetBoundary;
use v5.40;
use parent 'Perl::Critic::Policy';
use List::Util          qw(all);
use Perl::Critic::Utils qw(is_method_call);
our $VERSION = '0.001';
sub default_severity { return 5; }
sub default_themes   { return qw(gpforum); }
sub applies_to       { return 'PPI::Token::Word'; }

sub violates ( $self, $element, $document ) {
    my @namespaces = grep { $_ ne 'main' } $document->namespaces;
    return
      if @namespaces && all { /\AGPForum::Infrastructure\b/msx } @namespaces;
    return if $element ne 'resultset' || !is_method_call($element);
    return $self->violation( 'Resultsets belong in Infrastructure',
        'ADR 0154', $element );
}
1;
