# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::FeedParser;

use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;
use Mojo::DOM;
use Mojo::URL;
use Digest::SHA qw(sha256_hex);
use Mojo::Util  qw(encode);
use GPForum::Service::Integration::HttpClient;
use GPForum::X::Argument;
our $VERSION = '0.001';
const my $MAX_FEED_BYTES => 1_048_576;
const my $MAX_ENTRIES    => 100;
const my $TITLE_LENGTH   => 300;
has client => sub { return GPForum::Service::Integration::HttpClient->new; };

sub parse ( $self, $xml ) {
    if ( length( encode( 'UTF-8', $xml ) ) > $MAX_FEED_BYTES
        || $xml =~ /<!\s*(?:DOCTYPE|ENTITY)/imsx )
    {
        GPForum::X::Argument->throw(
            message => 'invalid or oversized syndication document' );
    }
    my $document = Mojo::DOM->new->xml(1)->parse($xml);
    my $root     = $document->children->first;
    if ( !$root ) {
        GPForum::X::Argument->throw(
            message => 'RSS 2 or Atom 1 document required' );
    }
    my $kind = _local($root);
    my $container =
        $kind eq 'rss'  ? _child( $root, 'channel' )
      : $kind eq 'feed' ? $root
      :                   undef;
    if ( !$container ) {
        GPForum::X::Argument->throw(
            message => 'RSS 2 or Atom 1 document required' );
    }
    my @entries;
    for my $entry ( $container->children->each ) {
        next if _local($entry) ne ( $kind eq 'rss' ? 'item' : 'entry' );
        last if @entries >= $MAX_ENTRIES;
        my $candidate = $self->_entry( $entry, $kind );
        if ($candidate) { push @entries, $candidate; }
    }
    return \@entries;
}

sub _entry ( $self, $entry, $kind ) {
    my $title_node = _child( $entry, 'title' );
    my $title      = $title_node ? $title_node->all_text : q{};
    $title =~ s/[\x00-\x1f\x7f]/ /gmsx;
    $title =~ s/\A\s+|\s+\z//gmsx;
    return undef if !length $title;
    my $link = _link( $entry, $kind );
    return undef if !defined $link;
    $link =~ s/\A\s+|\s+\z//gmsx;
    my $url;
    try { $url = $self->client->https_url($link); }
    catch ($error) { return undef; };
    $url->host( lc $url->host )->port(undef);
    my $id_node  = _child( $entry, $kind eq 'rss' ? 'guid' : 'id' );
    my $identity = $id_node ? $id_node->all_text : "$url";
    if ( !length $identity ) { $identity = "$url"; }
    return {
        title         => substr( $title, 0, $TITLE_LENGTH ),
        url           => "$url",
        identity_hash => sha256_hex( encode( 'UTF-8', $identity ) ),
        url_hash      => sha256_hex( encode( 'UTF-8', "$url" ) )
    };
}

sub _link ( $entry, $kind ) {
    for my $node ( $entry->children->each ) {
        next if _local($node) ne 'link';
        next
          if $kind ne 'rss'
          && ( $node->attr('rel') // 'alternate' ) ne 'alternate';
        my $link = $kind eq 'rss' ? $node->all_text : $node->attr('href');
        return $link if defined $link;
    }
    return undef;
}

sub _local ($node) {
    my $name = $node->tag;
    $name =~ s/\A .*://msx;
    return $name;
}

sub _child ( $node, $name ) {
    for my $child ( $node->children->each ) {
        return $child if _local($child) eq $name;
    }
    return undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::FeedParser - Parse bounded RSS/Atom title/link candidates without importing HTML.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Integration::FeedParser->new;

=head1 DESCRIPTION

Parse bounded RSS/Atom title/link candidates without importing HTML. Core owns configuration, authorization and presentation.

=head1 SUBROUTINES/METHODS

=head2 parse

Accepts RSS 2 or Atom 1, rejects document types/entities and returns at most 100 bounded candidates.

=head1 DIAGNOSTICS

Invalid configuration and transport failures raise typed exceptions.

=head1 CONFIGURATION AND ENVIRONMENT

The composition layer supplies validated settings and dependencies.

=head1 DEPENDENCIES

The Good Phorum runtime and the modules named above.

=head1 INCOMPATIBILITIES

Network capabilities are independent of the frozen local Plugin API v1.

=head1 BUGS AND LIMITATIONS

External operations depend on the configured provider and its availability.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
