# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Discovery::Gemini;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;
use Encode qw(encode decode FB_CROAK);
use Mojo::URL;
use Mojo::File qw(path);
use Mojo::Template;
use GPForum::Infrastructure::Id;
use GPForum::Service::Forum::Viewer;

our $VERSION = '0.001';

const my $DEFAULT_PORT      => 1965;
const my $MAX_REQUEST_BYTES => 1026;
const my $PAGE_SIZE         => 50;
__PACKAGE__->requires(
    qw(hostname category_reader thread_reader thread_detail_reader));
has port      => $DEFAULT_PORT;
has templates => sub {
    return path(__FILE__)
      ->to_abs->dirname->dirname->dirname->dirname->dirname->child(
        'templates/gemini');
};

sub response ( $self, $request ) {
    return "59 Bad request\r\n"
      if length($request) > $MAX_REQUEST_BYTES
      || $request !~ /\A [^\r\n]+\r\n \z/msx;
    my $response;
    try {
        my $text =
          decode( 'UTF-8', substr( $request, 0, -length("\r\n") ), FB_CROAK );
        my $url = Mojo::URL->new($text);
        return "59 Bad request\r\n"
          if ( $url->scheme // q{} ) ne 'gemini'
          || defined $url->userinfo
          || defined $url->fragment
          || $text =~ /[\x00-\x20\x7f]/msx;
        return "53 Proxy request refused\r\n"
          if lc( $url->host // q{} ) ne lc( $self->hostname )
          || ( $url->port // $DEFAULT_PORT ) != $self->port;
        $response = $self->_page($url);
    }
    catch ($error) { return "40 Temporarily unavailable\r\n"; };
    return $response;
}

sub _page ( $self, $url ) {
    my $route  = $url->path->to_string || q{/};
    my $viewer = GPForum::Service::Forum::Viewer->anonymous;
    my ( $template, $values );
    if ( $route eq q{/} || $route eq '/categories' ) {
        my $rows = $self->category_reader->list_categories( { limit => 200 } );
        $template = 'index';
        $values   = {
            title => 'GPForum',
            next  => undef,
            items => [
                map {
                    {
                        url   => '/c/' . $_->get_column('category_id'),
                        title => _line( $_->get_column('title') )
                    }
                } @{$rows}
            ]
        };
    }
    elsif ( $route =~ m{\A /c/([^/]+) \z}msx ) {
        my $id = $1;
        return "51 Not found\r\n" if !GPForum::Infrastructure::Id->is_uuid($id);
        my $category = $self->category_reader->find_category( $id, $viewer );
        return "51 Not found\r\n" if !$category;
        my $page = $self->thread_reader->list_category_threads(
            {
                category_id  => $id,
                viewer_scope => $viewer,
                limit        => $PAGE_SIZE,
                after        => $url->query->param('after')
            }
        );
        $template = 'index';
        $values   = {
            title => _line( $category->get_column('title') ),
            items => [
                map {
                    {
                        url   => '/t/' . $_->get_column('thread_id'),
                        title => _line( $_->get_column('title') )
                    }
                } @{ $page->{items} }
            ],
            next => _next( $url, $page )
        };
    }
    elsif ( $route =~ m{\A /t/([^/]+) \z}msx ) {
        my $id = $1;
        return "51 Not found\r\n" if !GPForum::Infrastructure::Id->is_uuid($id);
        my $page = $self->thread_detail_reader->thread_page(
            {
                thread_id => $id,
                viewer    => $viewer,
                limit     => $PAGE_SIZE,
                after     => $url->query->param('after')
            }
        );
        return "51 Not found\r\n" if !$page->{ok};
        $template = 'thread';
        $values   = {
            title => _line( $page->{thread}->get_column('title') ),
            posts => [ map { _post($_) } @{ $page->{posts}{items} } ],
            next  => _next( $url, $page->{posts} )
        };
    }
    else { return "51 Not found\r\n"; }
    my $body =
      Mojo::Template->new( vars => 1 )
      ->render_file( $self->templates->child("$template.gmi")->to_string,
        $values );
    die $body if ref $body;    ## no critic (ErrorHandling::RequireCarping) -- template diagnostics are caught at the protocol boundary
    return "20 text/gemini; charset=utf-8\r\n" . encode( 'UTF-8', $body );
}

sub _post ($row) {
    my $body = $row->get_column('body_source') // q{};
    $body =~ s/^```/ ```/gmsx;
    return {
        author => _line(
                 $row->get_column('author_display_name')
              || $row->get_column('author_username')
        ),
        body => $body
    };
}

sub _next ( $url, $page ) {
    return undef if !$page->{has_next};
    return $url->clone->query( after => $page->{next_cursor} )->to_string;
}

sub _line ($value) { return ( $value // q{} ) =~ s/[\r\n\x00-\x1f]+/ /grmsx; }

1;

__END__

=head1 NAME

GPForum::Service::Discovery::Gemini - Public, paginated Gemtext through the forum readers.

=head1 DESCRIPTION

Accepts one UTF-8 Gemini URL of at most 1024 bytes followed by CRLF.
Rejects credentials, fragments, other hosts and ports. Index, categories
and threads are read anonymously using the same visibility rules as HTTP.
User post text is fenced as literal Gemtext, including embedded fences.
Private and removed content is never served. Read failures answer 40.

=head1 SUBROUTINES/METHODS

=head2 response

Returns the complete Gemini status line and optional UTF-8 Gemtext for one request line.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $response = $reader->response("gemini://forum.example/\r\n");

=head1 DIAGNOSTICS

Malformed requests return 59; unavailable storage returns 40; inaccessible resources return 51.

=head1 CONFIGURATION AND ENVIRONMENT

Inject hostname, port, public readers and the Gemtext template directory.

=head1 DEPENDENCIES

Mojo::URL, Mojo::Template, Encode and the forum readers.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Anonymous reads only; a separate command owns TLS and connection limits.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
