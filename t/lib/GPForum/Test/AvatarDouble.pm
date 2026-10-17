# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::AvatarDouble;

use Carp qw(croak);
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

has packaging => sub { return {}; };
has calls     => sub { return []; };
has variants  => sub { return []; };
has size      => 0;
has answer    => undef;                # optional: what process answers

# An operating system profile.
sub image_tool_packaging ($self) { return $self->packaging; }

# An upload pipeline that refuses everything it is given.
sub upload_and_link ( $self, $input ) {
    push @{ $self->calls }, $input;

    return { ok => 0, errors => {} };
}

# An upload over the limit, whose bytes must never be read.
sub asset ($self) {
    croak 'a file over the limit is never read';
}

# The profile pictures, answering the media pipeline.
sub process ( $self, $attachment_id ) {
    push @{ $self->calls }, $attachment_id;

    return $self->answer;
}

# A storage.
sub read_object ( $self, $key ) { return 'bytes'; }

sub exists_object ( $self, $key ) { return 0; }

sub write_object ( $self, $key, $content ) { return; }

# An attachment store holding one available image.
sub find_attachment ( $self, $attachment_id ) {
    return {
        attachment_id => $attachment_id,
        media_type    => 'image/png',
        object_key    => 'key',
        state         => 'available',
    };
}

sub find_variant ( $self, $input ) { return undef; }

sub add_variant ( $self, $input ) {
    push @{ $self->variants }, $input;

    return $input;
}

1;

__END__

=head1 NAME

GPForum::Test::AvatarDouble - The collaborators of the profile pictures, for unit tests.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $pipeline = GPForum::Test::AvatarDouble->new;
    my $os = GPForum::Test::AvatarDouble->new(
        packaging => { vips => ['/nonexistent'] } );

=head1 DESCRIPTION

One double playing each role L<GPForum::Service::Community::Avatars> and
L<GPForum::Infrastructure::ImageTool> are given (ADR 0144): an operating
system profile, an upload pipeline that refuses, an upload too large to
read, the avatars answering the media pipeline, a storage and an attachment
store holding one available image.

=head1 SUBROUTINES/METHODS

=head2 packaging

What L</image_tool_packaging> answers.

=head2 calls

What the pipeline and L</process> were given.

=head2 variants

The variants added.

=head2 size

The upload's size in bytes.

=head2 answer

What L</process> answers.

=head2 image_tool_packaging

L</packaging>.

=head2 upload_and_link

Records the input and refuses it.

=head2 asset

Croaks: an upload over the limit is never read.

=head2 process

Records the id and returns L</answer>.

=head2 read_object

C<bytes>.

=head2 exists_object

False.

=head2 write_object

Nothing.

=head2 find_attachment

An available PNG attachment with that id.

=head2 find_variant

None.

=head2 add_variant

Records the variant and returns it.

=head1 DIAGNOSTICS

L</asset> croaks.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
