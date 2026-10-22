# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::BodyLength;

use Const::Fast;
use Mojo::Base -strict, -signatures;
use v5.40;

our $VERSION = '0.001';

# ADR 0140: the one limit on a post body, in characters. A thread, a reply,
# an edit, a preview and a draft all hold at most this much; the database
# checks the same number on every table that keeps a body.
const my $MAXIMUM  => 50_000;
const my $REQUIRED => 'body is required';
const my $TOO_LONG => 'body is too long';

sub maximum ($class) {
    return $MAXIMUM;
}

sub too_long ( $class, $source ) {
    return length( $source // q{} ) > $MAXIMUM;
}

# undef when a body of $source may be published, or why it may not.
sub error ( $class, $source ) {
    return $REQUIRED if !length( $source // q{} );
    return $TOO_LONG if $class->too_long($source);

    return undef;
}

sub too_long_error ($class) {
    return $TOO_LONG;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::BodyLength - The one maximum length of a post body.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    use GPForum::Service::Forum::BodyLength;

    my $error = GPForum::Service::Forum::BodyLength->error($source);
    return { ok => 0, errors => { body_source => $error } } if $error;

=head1 DESCRIPTION

A body is rendered to HTML on every write and on reads, so its length bounds
what one post can cost. One number holds for a new thread, a reply, an edit,
a preview and a draft (ADR 0140), and the database checks the same number on
C<post_bodies>, C<held_posts> and C<forum_drafts>. Lengths are characters,
as PostgreSQL's C<char_length> counts them.

=head1 SUBROUTINES/METHODS

=head2 maximum

The most characters a body may hold: 50,000.

=head2 too_long

True when the given source holds more than L</maximum> characters.

=head2 error

C<body is required> for an empty or undefined source, C<body is too long>
past L</maximum>, otherwise undef.

=head2 too_long_error

The message L</error> gives for a body past L</maximum>, which a controller
replaces with the reader's language.

=head1 DIAGNOSTICS

Nothing is thrown.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Const::Fast>, L<Mojo::Base>.

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
