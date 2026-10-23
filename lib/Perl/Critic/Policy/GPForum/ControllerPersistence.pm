# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package Perl::Critic::Policy::GPForum::ControllerPersistence;
use v5.40;
use parent 'Perl::Critic::Policy';
use List::Util qw(any);
our $VERSION = '0.001';
sub default_severity { return 5; }
sub default_themes   { return qw(gpforum); }
sub applies_to       { return 'PPI::Statement::Include'; }

sub violates ( $self, $element, $document ) {
    return if !any { /\AGPForum::Controller\b/msx } $document->namespaces;
    return
      if ( $element->module // q{} ) !~
      /\A(?:DBIx::Class|GPForum::Schema)\b/msx;
    return $self->violation( 'Controllers cannot import persistence',
        'ADR 0154', $element );
}
1;
