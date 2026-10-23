# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Discovery::Mbox;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;
use Carp qw(croak);
use DateTime;
use Email::Simple;
use Encode qw(encode);
use JSON::MaybeXS;
use MIME::Base64      qw(encode_base64url);
use MIME::QuotedPrint qw(encode_qp);
use Mojo::URL;

our $VERSION = '0.001';

const my $SHORT_ZONE_LENGTH => 3;
__PACKAGE__->requires('base_url');

sub domain ($self) { return Mojo::URL->new( $self->base_url )->host; }

sub message_id ( $self, $post_id ) {
    return '<gpforum-post.' . $post_id . q{@} . $self->domain . '>';
}

sub message ( $self, $thread, $post, $signature = undef, $root_id = undef ) {
    my $date = _date( $post->{created_at} );
    my $name =
      _line( $post->{author_display_name}
          || $post->{author_username}
          || 'member' );
    my $title   = _line( $thread->{title} );
    my @headers = (
        From => encode( 'MIME-Header', $name )
          . ' <member-'
          . $post->{author_user_id} . q{@}
          . $self->domain . '>',
        To => '<category-'
          . $thread->{category_id} . q{@}
          . $self->domain . '>',
        Subject =>
          encode( 'MIME-Header', ( $root_id ? 'Re: ' : q{} ) . $title ),
        Date         => $date->strftime('%a, %d %b %Y %H:%M:%S +0000'),
        'Message-ID' => $self->message_id( $post->{post_id} ),
        'List-ID'    => '<category-'
          . $thread->{category_id} . q{.}
          . $self->domain . '>',
        'Archived-At' => '<'
          . $self->base_url . '/t/'
          . $thread->{thread_id}
          . '#post-'
          . $post->{post_id} . '>',
        'MIME-Version'               => '1.0',
        'Content-Type'               => 'text/plain; charset=UTF-8',
        'Content-Transfer-Encoding'  => 'quoted-printable',
        'X-GPForum-Signature-Status' => $signature ? 'signed' : 'unsigned',
        (
            $root_id
            ? (
                'In-Reply-To' => $self->message_id($root_id),
                References    => $self->message_id($root_id)
              )
            : ()
        ),
        (
            $signature
            ? (
                'X-GPForum-Signature' => encode_base64url(
                    JSON::MaybeXS->new( canonical => 1, utf8 => 1 )
                      ->encode($signature)
                )
              )
            : ()
        ),
    );
    my $body =
      encode_qp( encode( 'UTF-8', $post->{body_source} // q{} ), "\n" );
    my $mail =
      Email::Simple->create( header => \@headers, body => $body )->as_string;
    $mail =~ s/\r\n/\n/gmsx;
    $mail =~
      s/^(>*From[ ])/>$1/gmsx;    # mboxrd, including already quoted From lines
    return
        'From gpforum@'
      . $self->domain . q{ }
      . $date->strftime('%a %b %d %H:%M:%S %Y') . "\n"
      . $mail
      . ( $mail =~ /\n\z/msx ? "\n" : "\n\n" );
}

sub _line ($value) {
    return ( $value // q{} ) =~ s/[\r\n]+/ /grmsx;
}

sub _date ($value) {
    my ( $year, $month, $day, $hour, $minute, $second_of_minute ) =
      ( $value // q{} ) =~
      /\A (\d{4})-(\d\d)-(\d\d)[T ](\d\d):(\d\d):(\d\d)/msx;
    croak 'post has no creation date' if !defined $year;
    my ($zone) = $value =~ /([+-]\d\d(?::?\d\d)?)\z/msx;
    if ( defined $zone && length $zone == $SHORT_ZONE_LENGTH ) {
        $zone .= '00';
    }
    my $date = DateTime->new(
        year      => $year,
        month     => $month,
        day       => $day,
        hour      => $hour,
        minute    => $minute,
        second    => $second_of_minute,
        time_zone => $zone // 'UTC'
    );
    return $date->set_time_zone('UTC');
}

1;

__END__

=head1 NAME

GPForum::Service::Discovery::Mbox - Portable mboxrd records without private email addresses.

=head1 DESCRIPTION

C<message> writes one UTF-8 quoted-printable message with stable post
Message-ID, List-ID per category, reply References and server signature
envelope when present. Real member email addresses are never included.
All mbox From lines are escaped, including previously quoted lines.

=head1 SUBROUTINES/METHODS

=head2 domain

Returns the host used for stable mailing-list and post identifiers.

=head2 message_id

Returns the stable Message-ID for a post UUID.

=head2 message

Returns one mboxrd record for thread and post hashes, optionally carrying a verified signature and root Message-ID.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $record = $mbox->message($thread, $post, $signature);

=head1 DIAGNOSTICS

Throws if a post has no usable creation date.

=head1 CONFIGURATION AND ENVIRONMENT

The public base URL supplies stable message and mailing-list domains.

=head1 DEPENDENCIES

Email::Simple, DateTime, MIME::QuotedPrint, JSON::MaybeXS and Encode.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Attachments are represented by the post source; upload binaries are not embedded.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
