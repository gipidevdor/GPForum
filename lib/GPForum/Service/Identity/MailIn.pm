# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::MailIn;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;
use Carp qw(croak);
use Email::MIME;
use Email::Address::XS;
use Digest::SHA qw(sha256_hex);
use Encode      qw(encode);
use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

const my $MAX_MAIL_BYTES         => 1_048_576;
const my $MAX_MESSAGE_ID_BYTES   => 250;
const my $MAX_MIME_DEPTH         => 8;
const my $MAX_MIME_PARTS         => 50;
const my $NEW_MEMBER_WRITE_LIMIT => 20;
const my $RATE_WINDOW_SECONDS    => 60;
const my %AUTOMATIC_PRECEDENCE   => ( bulk => 1, junk => 1, list => 1 );
__PACKAGE__->requires(
    qw(tokens schema viewer_resolver suspension_store rate_limiter reputation_rate workflow)
);
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

sub receive ( $self, $raw ) {
    croak 'email exceeds one MiB' if length($raw) > $MAX_MAIL_BYTES;
    my $mail = Email::MIME->new($raw);
    my ( $user, $viewer, $target ) = $self->_authenticate($mail);
    my $decision = $self->rate_limiter->check(
        {
            scope          => 'forum_http',
            action         => 'reply.create',
            actor_id       => $user->{id},
            window_seconds => $RATE_WINDOW_SECONDS,
            limit          => $NEW_MEMBER_WRITE_LIMIT *
              ( 2**$self->reputation_rate->level( $user->{id} ) )
        }
    );
    croak 'email reply rate limit exceeded' if !$decision->{ok};
    my ( $body, $message_id ) = _content($mail);
    return $self->workflow->create_reply(
        {
            thread_id      => $target->{thread_id},
            author_user_id => $user->{id},
            viewer         => $viewer,
            body_source    => $body,
            command_id     => 'mail-in:'
              . sha256_hex( encode( 'UTF-8', "$user->{id}:$message_id" ) ),
        }
    );
}

sub _authenticate ( $self, $mail ) {
    croak 'automatic email is not a forum reply'
      if ( $mail->header_raw('Auto-Submitted') // 'no' ) ne 'no'
      || exists $AUTOMATIC_PRECEDENCE{
        lc( $mail->header_raw('Precedence') // q{} ) };
    my @parents = $mail->header_raw('In-Reply-To');
    my $target  = @parents == 1 ? $self->tokens->verify( $parents[0] ) : undef;
    croak 'email has no valid reply capability' if !$target;
    my $sender = _sender($mail);
    my $user   = $self->functions->row( 'forum_protocol_member',
        { user_id => $target->{user_id}, email => undef } );
    croak 'sender does not match a verified active recipient'
      if !$user
      || !defined $user->{email_verified_at}
      || lc($sender) ne $user->{email_normalized};
    my $viewer = $self->viewer_resolver->resolve( $user->{id} );
    croak 'sender cannot participate'
      if !$viewer->member
      || !$self->suspension_store->can_participate( $user->{id} )->{ok};
    return ( $user, $viewer, $target );
}

sub _sender ($mail) {
    my @from_headers = $mail->header_str('From');
    my @from =
      @from_headers == 1 ? Email::Address::XS->parse( $from_headers[0] ) : ();
    croak 'email needs one sender' if @from != 1 || !$from[0]->is_valid;
    return $from[0]->address;
}

sub _content ($mail) {
    my @ids = $mail->header_raw('Message-ID');
    croak 'email needs one valid Message-ID'
      if @ids != 1
      || length( $ids[0] ) > $MAX_MESSAGE_ID_BYTES
      || $ids[0] !~ /\A <[^<>\s]+\@[^<>\s]+> \z/msx;
    my $parts = 0;
    my $body  = _plain( $mail, 0, \$parts );
    croak 'email has no inline plain-text reply' if !defined $body;
    $body =~ s/\r\n/\n/gmsx;
    $body =~ s/\n--[ ]\n.*\z//msx;
    $body =~ s/\nOn[^\n]*wrote:\n.*\z//msx;
    $body =~ s/^>[^\n]*(?:\n|\z)//gmsx;
    $body =~ s/\A\s+|\s+\z//gmsx;
    croak 'email reply is empty' if !length $body;
    return ( $body, $ids[0] );
}

sub _plain ( $part, $depth, $count ) {
    croak 'email MIME structure exceeds the limit'
      if $depth > $MAX_MIME_DEPTH || ++${$count} > $MAX_MIME_PARTS;
    return undef
      if ( $part->header_raw('Content-Disposition') // q{} ) =~
      /\A attachment/imsx;
    my $type = $part->content_type // 'text/plain';
    return undef if $type =~ /\A message\//imsx;
    my @children = $part->subparts;
    if (@children) {
        for my $child (@children) {
            my $plain = _plain( $child, $depth + 1, $count );
            return $plain if defined $plain;
        }
        return undef;
    }
    return $type =~ /\A text\/plain(?:;|\z)/imsx ? $part->body_str : undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::MailIn - Authenticated MIME replies through the posting workflow.

=head1 DESCRIPTION

C<receive> accepts at most one MiB, a recipient-bound reply capability,
one verified From address and a Message-ID. It rejects automatic messages,
HTML-only mail, attachments and excessive MIME depth. Plain text uses the
declared charset and transfer encoding. Common quotes and signatures are
removed. Posting uses the web workflow's visibility, locked-thread,
moderation, screening and idempotency rules. Replayed message ids cannot
create duplicate posts, and changed content under one id is a conflict.

=head1 SUBROUTINES/METHODS

=head2 receive

Parses bounded MIME, authenticates the recipient capability and verified sender, and submits one idempotent reply to the posting workflow.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = $inbox->receive($mime_bytes);

=head1 DIAGNOSTICS

Throws on malformed or unauthenticated mail; normal posting refusals are returned by the workflow.

=head1 CONFIGURATION AND ENVIRONMENT

Inject token validation, account storage, viewer resolution, suspension checks and posting services.

=head1 DEPENDENCIES

Email::MIME, Email::Address::XS, Encode and the forum posting workflow.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Accepts plain text only; common quoted replies are stripped heuristically.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
