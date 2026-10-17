# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::ViewModel::Community::Messages;

use Mojo::Base 'GPForum::ViewModel::Base', -signatures;
use v5.40;

our $VERSION = '0.001';

# ADR 0139: the member's conversations, each with whom it is held, how many
# messages wait and the start of the latest one.
sub inbox_page ( $self, %input ) {
    my $page = $input{page} || {};
    my @conversations;
    for my $row ( @{ $page->{items} || [] } ) {
        my $other = $self->_member(
            $row->{other_username},
            $row->{other_display_name},
            $row->{other_gone}
        );
        push @conversations,
          {
            conversation_id => $row->{conversation_id},
            other           => $other,
            last_message_at => $row->{last_message_at},
            unread_count    => 0 + ( $row->{unread_count} // 0 ),
            last_excerpt    => $self->_excerpt( $row->{last_excerpt} ),
            last_is_own     => defined $row->{last_author_user_id}
              && defined $input{user_id}
              && $row->{last_author_user_id} eq $input{user_id} ? 1 : 0,
            ui => {
                heading_id =>
                  $self->stable_id( 'conversation', $row->{conversation_id} ),
            },
          };
    }

    return {
        conversations => \@conversations,
        next_cursor   => $page->{next_cursor},
    };
}

# One conversation: its messages oldest first (the page holds the newest),
# each with its author and its lines, the form that answers and, for the
# other member's messages, the report form's command id.
sub conversation_page ( $self, %input ) {
    my $head = $input{conversation} || {};
    my $page = $input{page}         || {};
    my $ids  = $input{command_ids} // sub { return q{} };
    my @messages;
    for my $row ( reverse @{ $page->{items} || [] } ) {
        my $own =
          defined $input{user_id} && $row->{author_user_id} eq $input{user_id}
          ? 1
          : 0;
        my $body = $self->string( $row->{body} );
        push @messages,
          {
            message_id => $row->{message_id},
            author     => $self->_member(
                $row->{author_username},
                $row->{author_display_name}
            ),
            own               => $own,
            body              => $body,
            body_lines        => [ split /\n/msx, $body ],
            created_at        => $row->{created_at},
            report_command_id => $own ? q{} : $ids->(),
            ui                => {
                anchor => $self->stable_id( 'message', $row->{message_id} ),
                report_sheet =>
                  $self->stable_id( 'message-report', $row->{message_id} ),
            },
          };
    }

    return {
        conversation => {
            conversation_id => $head->{conversation_id},
            created_at      => $head->{created_at},
            other           => $self->_member(
                $head->{other_username}, $head->{other_display_name},
                $head->{other_gone}
            ),
            reader_blocks => $head->{reader_blocks} ? 1 : 0,
        },
        messages         => \@messages,
        older_cursor     => $page->{next_cursor},
        reply_command_id => $self->string( $input{reply_command_id} ),
        draft            => $self->string( $input{draft} ),
        error            => $input{error},
        maximum_body     => $input{maximum_body},
    };
}

# The form that writes to a member the reader holds no conversation with.
sub compose_page ( $self, %input ) {
    my $recipient = $input{recipient} || {};

    return {
        recipient => $self->_member(
            $recipient->{other_username},
            $recipient->{other_display_name}
        ),
        command_id   => $self->string( $input{command_id} ),
        draft        => $self->string( $input{draft} ),
        error        => $input{error},
        maximum_body => $input{maximum_body},
    };
}

# A member as a conversation names them: an erased account is named by
# none of its old names.
sub _member ( $self, $username, $display_name, $gone = 0 ) {
    return {
        gone         => 1,
        username     => undef,
        display_name => undef,
        initial      => q{?},
        tint         => $self->tint(q{}),
      }
      if $gone || !defined $username;

    my $name = length( $display_name // q{} ) ? $display_name : $username;

    return {
        gone         => 0,
        username     => $username,
        display_name => $name,
        initial      => $self->initial($name),
        tint         => $self->tint($username),
    };
}

# The start of the latest message, on one line.
sub _excerpt ( $self, $text ) {
    my $excerpt = $self->string($text);
    $excerpt =~ s/\s+/ /gmsx;

    return $excerpt;
}

1;

__END__

=head1 NAME

GPForum::ViewModel::Community::Messages - The pages of direct messages.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $messages = GPForum::ViewModel::Community::Messages->new;
    my $payload  = $messages->inbox_page( page => $page, user_id => $id );

=head1 DESCRIPTION

ADR 0139. Shapes the store's rows into what the inbox, a conversation and
the compose form render, for HTML and JSON alike. A member whose account
was erased is named by none of its old names.

=head1 SUBROUTINES/METHODS

=head2 inbox_page

Takes C<page> (the store's inbox page) and C<user_id>; answers
C<conversations> and C<next_cursor>.

=head2 conversation_page

Takes C<conversation> (the store's head), C<page> (its messages, newest
first), C<user_id>, C<command_ids> (a code reference minting the report
forms' ids), C<reply_command_id>, C<draft>, C<error> and C<maximum_body>;
answers the messages oldest first.

=head2 compose_page

Takes C<recipient>, C<command_id>, C<draft>, C<error> and C<maximum_body>.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::ViewModel::Base>.

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
