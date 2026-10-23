# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package Perl::Critic::Policy::GPForum::ServiceContext;
use v5.40;
use parent 'Perl::Critic::Policy';
use List::Util qw(any);
our $VERSION = '0.001';
sub default_severity { return 5; }
sub default_themes   { return qw(gpforum); }
sub applies_to       { return 'PPI::Statement::Sub'; }

sub violates ( $self, $element, $document ) {
    return if !any { /\AGPForum::Service\b/msx } $document->namespaces;
    my $head = $element->content;
    $head =~ s/[{].*\z//msx;
    my $receives_context = $head =~ /\$(?:c|controller)\b/msx;
    for
      my $declaration ( @{ $element->find('PPI::Statement::Variable') || [] } )
    {
        $receives_context ||= $declaration->content =~
          /\A\s*my\s*[(][^)]*\$(?:c|controller)\b[^)]*[)]\s*=\s*[@]_/msx;
        $receives_context ||= $declaration->content =~
          /\A\s*my\s+\$(?:c|controller)\s*=\s*shift\b/msx;
    }
    return if !$receives_context;
    return $self->violation( 'Services receive values, not controllers',
        'ADR 0154', $element );
}
1;
