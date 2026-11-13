# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Quality::AsyncSyntax;
use v5.40;
use Carp       qw(croak);
use Mojo::Util qw(monkey_patch);
use PPI::Document;
use Scalar::Util qw(refaddr);
our $VERSION = '0.001';

# PPI 1.291 needs a syntax adapter for async modifiers. Only the modifier
# is insignificant in the analysis tree; all original source and locations
# survive for diagnostics, formatting and policy checks. Heredoc bodies are
# not part of token content, so restore relative to the following sub token.
sub import ($class) {
    my $constructor = PPI::Document->can('new');
    monkey_patch 'PPI::Document', new => sub ( $document_class, @arguments ) {
        my $document = $constructor->( $document_class, @arguments );
        return $document if !$document;
        my $tokens = _modifiers($document);
        return $document if !$tokens;
        my $original = $document->serialize;
        my %modifiers;
        for my $token ( @{$tokens} ) {
            my $sub = $token->snext_sibling;
            $modifiers{ _position($sub) } = _suffix_length( $token, $sub );
            $token->set_content(q{     });
        }
        my $source     = $document->serialize;
        my $normalized = $constructor->(
            'PPI::Document', \$source, filename => $document->filename
        );
        croak 'cannot classify async declarations' if !$normalized;
        for my $token ( $normalized->tokens ) {
            next
              if !$token->isa('PPI::Token::Word') || $token->content ne 'sub';
            my $key = _position($token);
            next if !exists $modifiers{$key};
            _restore_modifier( $token, delete $modifiers{$key} );
        }
        croak 'async analysis changed source text'
          if keys(%modifiers) || $normalized->serialize ne $original;
        return $normalized;
    };
    return;
}

sub _modifiers($document) {
    return $document->find(
        sub ( $top, $token ) {
            return
                 $token->isa('PPI::Token::Word')
              && $token->content eq 'async'
              && $token->snext_sibling
              && $token->snext_sibling->content eq 'sub';
        }
    );
}

sub _position($token) {
    my $location = $token->location;
    return join q{:}, @{$location}[ 0, 1 ];
}

sub _suffix_length( $modifier, $sub ) {
    my $length = 0;
    my $next   = $modifier->next_token;
    while ($next) {
        return $length if refaddr($next) == refaddr($sub);
        $length += length $next->content;
        $next = $next->next_token;
    }
    croak 'async declaration has no sub token';
}

sub _restore_modifier( $sub, $suffix_length ) {
    my $token = $sub->previous_token;
    while ($token) {
        my $content = $token->content;
        my $length  = length $content;
        if ( $length >= $suffix_length + length q{async} ) {
            my $offset = $length - $suffix_length - length q{async};
            croak 'async modifier lost its whitespace node'
              if !$token->isa('PPI::Token::Whitespace')
              || substr( $content, $offset, length q{async} ) ne q{     };
            substr $content, $offset, length(q{async}), q{async};
            $token->set_content($content);
            return;
        }
        $suffix_length -= $length;
        $token = $token->previous_token;
    }
    croak 'async modifier could not be restored';
}
1;
