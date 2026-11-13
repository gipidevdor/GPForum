# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::FileOutboxTransport;
use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;
use Carp          qw(croak);
use English       qw(-no_match_vars);
use Fcntl         qw(O_WRONLY O_CREAT O_APPEND);
use JSON::MaybeXS qw(encode_json);
use GPForum::Jobs::EventPayload;
our $VERSION = '0.001';
const my $PRIVATE_MODE => 0o600;

has path => undef;

sub dispatch ( $self, $message ) {
    my $event =
      GPForum::Jobs::EventPayload->normalize( $message->get_column('payload') );
    sysopen my $file, $self->path, O_WRONLY | O_CREAT | O_APPEND, $PRIVATE_MODE
      or croak $OS_ERROR;
    print {$file} encode_json(
        {
            outbox_id => $message->get_column('outbox_id'),
            aggregate => $event->{aggregate_id},
            sequence  => $event->{domain_payload}{sequence},
            pid       => $PROCESS_ID
        }
      ),
      "\n"
      or croak $OS_ERROR;
    close $file or croak $OS_ERROR;
    return;
}
1;
