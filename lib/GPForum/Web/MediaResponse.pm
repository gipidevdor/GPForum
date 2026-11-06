# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::MediaResponse;

use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;
use List::Util qw(any min);
use Mojo::Date;
use Carp qw(croak);
use Mojo::IOLoop;

our $VERSION = '0.001';
const my $HTTP_OK            => 200;
const my $HTTP_PARTIAL       => 206;
const my $HTTP_NOT_MODIFIED  => 304;
const my $HTTP_UNSATISFIABLE => 416;

# Authorization precedes this helper, including for HEAD and conditional
# requests. It never allocates a response-sized scalar or an open SQL cursor.
sub render ( $self, $controller, $asset, $checksum ) {
    my $request = $controller->req->headers;
    my $headers = $controller->res->headers;
    my $etag    = qq{"$checksum"};
    my $size    = $asset->size;
    $headers->accept_ranges('bytes')->etag($etag);
    if ( !defined $headers->cache_control ) {
        $headers->cache_control('private, no-store');
    }
    $headers->last_modified( Mojo::Date->new( $asset->mtime )->to_string );
    return $controller->rendered($HTTP_NOT_MODIFIED)
      if _matches( $request->if_none_match // q{}, $etag );
    my $bounds =
      _bounds( _usable_range( $request, $etag, $asset->mtime ), $size );

    if ( !$bounds ) {
        $headers->content_range("bytes */$size")->content_length(0);
        return $controller->rendered($HTTP_UNSATISFIABLE);
    }
    my ( $start, $end, $code ) = @{$bounds};
    if ( $code == $HTTP_PARTIAL ) {
        $headers->content_range("bytes $start-$end/$size");
    }
    $asset->start_range($start)->end_range($end);
    $headers->content_length( $end - $start + 1 );
    return $self->_stream( $controller, $asset, $end - $start + 1, $code )
      if $asset->can('get_chunk_p');
    $controller->res->content->asset($asset);
    return $controller->rendered($code);
}

sub _stream ( $self, $controller, $asset, $length, $code ) {
    if ( $asset->can('query_context') ) {
        $asset->query_context( $controller->stash('gp_db_query_stats_token') );
    }
    $controller->res->code($code);
    return $controller->rendered($code) if $controller->req->method eq 'HEAD';
    $controller->render_later;
    my ( $offset, $finished ) = ( 0, 0 );
    my $pump;
    $controller->on( finish => sub { $finished = 1; undef $pump; return; } );
    $pump = sub {
        return if $finished;
        if ( $offset >= $length ) {
            $controller->finish;
            return;
        }
        $asset->get_chunk_p($offset)->then(
            sub ($bytes) {
                return                         if $finished;
                croak 'media read ended early' if !length $bytes;
                $offset += length $bytes;

                # Fetch another bounded chunk only after this one drains.
                $controller->write(
                    $bytes,
                    sub {
                        if ($pump) { $pump->(); }
                        return;
                    }
                );
                return;
            }
        )->catch(
            sub ($error) {
                return if $finished;
                $controller->log->error('asynchronous media read failed');
                $finished = 1;
                undef $pump;
                if ( !$controller->stash('mojo.finished') ) {
                    $controller->res->headers->remove('Content-Length');
                    $controller->render(
                        text   => 'Media unavailable',
                        status => 503
                    );
                }
                else {
                    Mojo::IOLoop->remove( $controller->tx->connection );
                }
                return;
            }
        );
    };
    $pump->();
    return;
}

sub _matches ( $match, $etag ) {
    return any { $_ eq $etag || $_ eq "W/$etag" || $_ eq q{*} }
      split /\s*,\s*/msx, $match;
}

sub _usable_range ( $request, $etag, $mtime ) {
    my $condition = $request->header('If-Range');
    return $request->range if !defined $condition || $condition eq $etag;
    my $date = Mojo::Date->new($condition)->epoch;
    return defined $date && $date >= int $mtime ? $request->range : undef;
}

sub _bounds ( $range, $size ) {
    my @parts = defined $range ? $range =~ /\A bytes=(\d*)-(\d*) \z/msx : ();
    return [ 0, $size - 1, $HTTP_OK ] if !@parts;
    my ( $first, $final ) = @parts;
    my ( $start, $end )   = ( 0, $size - 1 );
    if ( $first eq q{} ) {
        $start =
          $final ne q{} && $final > 0 ? $size - min( $final, $size ) : $size;
    }
    else {
        $start = 0 + $first;
        if ( $final ne q{} ) { $end = min( $final, $end ); }
    }
    return undef if $start > $end || $size == 0;
    return [ $start, $end, $HTTP_PARTIAL ];
}

1;

__END__

=head1 NAME

GPForum::Web::MediaResponse - Authorized seekable media responses.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Web::MediaResponse->new->render($controller, $asset, $checksum);

=head1 DESCRIPTION

Streams an asset with a content hash ETag and bounded memory. Supports HEAD,
closed, open and suffix byte ranges, If-Range, conditional requests and 416.
Unsupported range syntax is ignored and receives the complete representation.

=head1 SUBROUTINES/METHODS

=head2 render

Takes an authorized controller, an asset and its SHA-256 checksum. Attaches
the asset to the response without reading its bytes or holding a transaction.

=head1 DIAGNOSTICS

Returns HTTP 200, 206, 304 or 416; a later asset read failure terminates delivery.

=head1 CONFIGURATION AND ENVIRONMENT

The composition layer supplies the schema, storage and source policy.

=head1 DEPENDENCIES

L<Mojo::Base> and the composed Good Phorum services.

=head1 INCOMPATIBILITIES

One byte range is supported. Multiple ranges are ignored, yielding the complete representation.

=head1 BUGS AND LIMITATIONS

One byte range is supported. Multiple ranges are ignored, yielding the complete representation.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
