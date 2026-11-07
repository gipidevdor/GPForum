# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::Validator;

use Const::Fast;
use List::Util qw(any);
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';
const my $ISO_WORD_BYTES   => 4;
const my $ISO_HEADER_BYTES => 8;
const my $FTYP_MIN_BYTES   => 16;

const my $MAX_BYTES          => 25 * 1_024 * 1_024;
const my $MEDIA_MAX_BYTES    => 250 * 1_024 * 1_024;
const my $TEXT_SAMPLE_LENGTH => 512;
has media_max_bytes => $MEDIA_MAX_BYTES;

my %ALLOWED_MEDIA = map { $_ => 1 } qw(
  image/gif
  image/jpeg
  image/png
  image/webp
  application/pdf
  text/plain
  video/mp4
  audio/mpeg
  audio/mp4
  audio/ogg
  audio/wav
);

# The largest upload accepted, so a scanner can be checked against it.
sub max_bytes ($class) {
    return $MEDIA_MAX_BYTES;
}

sub validate_upload ( $self, $input ) {
    my %errors;
    my $media_type = _server_media_type($input);

    _require_text( \%errors, $input, 'owner_user_id' );
    _require_text( \%errors, $input, 'original_filename' );
    _require_text( \%errors, { media_type => $media_type }, 'media_type' );
    _require_text( \%errors, $input,                        'checksum' );
    $self->_validate_size( \%errors, $input->{byte_size}, $media_type );
    _validate_media_type( \%errors, $media_type );
    _validate_filename( \%errors, $input->{original_filename} );

    return { ok => 0, errors => \%errors } if keys %errors;

    return { ok => 1, values => _normalized( $input, $media_type ) };
}

sub sniff_media_type ( $self, $content ) {
    return undef        if !defined $content;
    return 'image/png'  if $content =~ /\A \x89 PNG \x0d \x0a \x1a \x0a/msx;
    return 'image/jpeg' if $content =~ /\A \xff \xd8 \xff/msx;
    return 'image/gif'  if $content =~ /\A GIF (?: 87a | 89a )/msx;
    return 'application/pdf' if $content =~ /\A %PDF-/msx;
    return 'image/webp'      if $content =~ /\A RIFF .{4} WEBP/msx;
    my $audio = _audio_type($content);
    return $audio if defined $audio;
    my $mp4 = _mp4_type($content);
    return $mp4 if defined $mp4;

    return 'text/plain' if _looks_like_text($content);

    return 'application/octet-stream';
}

sub _audio_type ($content) {
    return 'audio/wav' if $content =~ /\A RIFF .{4} WAVE/msx;
    return 'audio/ogg'
      if $content =~ /\A OggS/msx
      && $content =~ /(?:OpusHead|\x01vorbis)/msx;
    return 'audio/mpeg'
      if $content =~ /\A ID3[\x02-\x04]\x00[\x00-\xff].{4}/msx
      || $content =~ /\A \xff [\xe2-\xe7\xf2-\xf7\xfa-\xff] [\x10-\xef]/msx;
    return undef;
}

sub _mp4_type ($content) {
    return undef
      if length $content < $FTYP_MIN_BYTES
      || substr( $content, $ISO_WORD_BYTES, $ISO_WORD_BYTES ) ne 'ftyp';
    my $size_bytes = substr $content, 0, $ISO_WORD_BYTES;
    my $size       = unpack 'N', $size_bytes;
    return 'application/octet-stream'
      if $size < $FTYP_MIN_BYTES
      || $size > length $content
      || $size % $ISO_WORD_BYTES;
    my $major      = substr $content, $ISO_HEADER_BYTES, $ISO_WORD_BYTES;
    my $compatible = substr $content, $FTYP_MIN_BYTES, $size - $FTYP_MIN_BYTES;
    my @brands     = ( $major, unpack '(a4)*', $compatible, );
    return 'audio/mp4' if any { $_ eq 'M4A ' || $_ eq 'M4B ' } @brands;
    my %video = map { $_ => 1 } (
        qw(isom iso2 iso3 iso4 iso5 iso6 iso7 iso8 iso9 mp41 mp42 avc1), 'M4V '
    );
    return 'video/mp4' if any { $video{$_} } @brands;
    return 'application/octet-stream';
}

sub _require_text ( $errors, $input, $field ) {
    if ( !defined $input->{$field} || !length $input->{$field} ) {
        $errors->{$field} = "$field is required";
    }

    return;
}

sub _validate_size ( $self, $errors, $byte_size, $media_type ) {
    if ( !defined $byte_size || $byte_size <= 0 ) {
        $errors->{byte_size} = 'byte_size is required';
        return;
    }

    my $limit =
      ( $media_type // q{} ) =~ m{\A (?:video|audio)/}msx
      ? $self->media_max_bytes
      : $MAX_BYTES;
    if ( $byte_size > $limit ) {
        $errors->{byte_size} = 'byte_size exceeds limit';
    }

    return;
}

sub _validate_media_type ( $errors, $media_type ) {
    return if !defined $media_type || !length $media_type;

    if ( !$ALLOWED_MEDIA{ lc $media_type } ) {
        $errors->{media_type} = 'media_type is not allowed';
    }

    return;
}

sub _validate_filename ( $errors, $filename ) {
    return if !defined $filename || !length $filename;

    if ( $filename =~ /[.] (?: cgi | exe | pl | pm | php | sh ) \z/imsx ) {
        $errors->{original_filename} = 'executable uploads are not allowed';
    }

    return;
}

sub _server_media_type ($input) {
    return $input->{sniffed_media_type}
      if defined $input->{sniffed_media_type}
      && length $input->{sniffed_media_type};
    return GPForum::Service::Attachment::Validator->new->sniff_media_type(
        $input->{content} )
      if defined $input->{content};

    return $input->{media_type};
}

sub _looks_like_text ($content) {
    my $sample = substr $content, 0, $TEXT_SAMPLE_LENGTH;
    return if $sample =~ /[\x00-\x08\x0b\x0c\x0e-\x1f]/msx;

    return 1;
}

sub _normalized ( $input, $media_type ) {
    return {
        owner_user_id     => $input->{owner_user_id},
        original_filename => $input->{original_filename},
        media_type        => lc $media_type,
        byte_size         => int $input->{byte_size},
        checksum          => lc $input->{checksum},
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Attachment::Validator - Check an upload's metadata and tell its media type from its bytes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $validator = GPForum::Service::Attachment::Validator->new;

    my $result = $validator->validate_upload(
        {
            byte_size         => length $content,
            checksum          => $sha256_hex,
            content           => $content,
            original_filename => 'diagram.png',
            owner_user_id     => $user_id,
        }
    );
    return $result->{errors} if !$result->{ok};
    my $values = $result->{values};

    my $limit = GPForum::Service::Attachment::Validator->max_bytes;

=head1 DESCRIPTION

The first check an upload passes. The media type is decided on the server:
a C<sniffed_media_type> given by the caller wins, then the type sniffed from
C<content>, and only without either the client's C<media_type>. That type
must be C<image/gif>, C<image/jpeg>, C<image/png>, C<image/webp>,
C<application/pdf>, C<text/plain>, MP4 video, or MPEG/MP4/Ogg/WAV audio;
the size must be positive and at most 25 MiB for documents and images,
or C<media_max_bytes> (250 MiB by default) for audio and video.
A filename ending in C<.cgi>, C<.exe>, C<.pl>, C<.pm>, C<.php>
or C<.sh> is refused whatever its type.

Sniffing reads the magic numbers of PNG, JPEG, GIF, PDF and WebP. Other
content is C<text/plain> when its first 512 bytes hold no control character
other than tab, line feed and carriage return, and
C<application/octet-stream> otherwise.

=head1 SUBROUTINES/METHODS

=head2 max_bytes

Class method. Returns the largest upload accepted, in bytes (250 MiB), so a
scanner's own limit can be checked against it.

=head2 validate_upload

Takes a hash reference with C<owner_user_id>, C<original_filename>,
C<checksum>, C<byte_size>, and C<media_type>, C<content> or
C<sniffed_media_type>. Returns C<< { ok => 0, errors => \%errors } >> with
every problem found, keyed by field, or
C<< { ok => 1, values => \%values } >> where the values are
C<owner_user_id>, C<original_filename>, C<media_type> and C<checksum>
(both lower-cased) and C<byte_size> (an integer).

=head2 sniff_media_type

Takes the uploaded bytes. Returns the media type they show,
C<application/octet-stream> when none is recognized, or undef for undef
content.

=head1 DIAGNOSTICS

Nothing is thrown. The errors C<validate_upload> returns are
C<FIELD is required> for C<owner_user_id>, C<original_filename>,
C<media_type> and C<checksum>; C<byte_size is required> or
C<byte_size exceeds limit>; C<media_type is not allowed>; and
C<executable uploads are not allowed> for C<original_filename>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

None beyond L<Mojo::Base> and L<Const::Fast>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
