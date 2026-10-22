# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use JSON::MaybeXS;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Identity::MailToken;
use GPForum::Service::Identity::Registration;
use GPForum::Service::Identity::Store;
use GPForum::Service::Identity::Workflow;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::FixedClock;
use GPForum::Test::FixedPassword;
use GPForum::Test::LogLines;
use GPForum::Test::PgDatabase;
use GPForum::Test::SequenceId;
use GPForum::Test::SessionToken;

our $VERSION = '0.001';

# ADR 0126, section 10: a registration as one call (migration 106) against
# the Perl path that kept the command log, a transaction and savepoints
# around seven calls. On two databases seeded alike, with the ids, the
# clock, the password hash and the tokens scripted, each command's answer
# and every row it writes are the same on both paths: the user and the
# credential, the registration's event, outbox row and audit, the
# verification token with its audit and mail, the command log with its
# response and hash.

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all =>
      'set GPFORUM_TEST_DSN for identity command differential tests';
}

const my $NOW   => '2026-10-14T10:00:00Z';
const my $EPOCH => 1_791_972_000;            # 2026-10-14T10:00:00Z

my $json = JSON::MaybeXS->new( canonical => 1 );
my %pair =
  map { $_ => GPForum::Test::PgDatabase->fresh( seed => 1 ) } qw(function perl);
my $serial = 0;

my %account = (
    display_name => 'Differential Registrant',
    email        => 'registrant@example.invalid',
    password     => 'A long enough password 2026',
    username     => 'registrant',
);
same( 'register', { %account, command_id => 'reg-1' }, 'ok', 'first run' );
same( 'register', { %account, command_id => 'reg-1' }, 'ok', 'replayed' );
same( 'register',
    { %account, command_id => 'reg-1', email => 'other@example.invalid' },
    'conflict', 'another request under the same command id' );
same( 'register',
    { %account, command_id => 'reg-2', email => 'second@example.invalid' },
    'invalid', 'a username already registered' );
same(
    'register',
    {
        %account,
        command_id => 'reg-3',
        email      => 'not an address',
        username   => 'registrant_two'
    },
    'invalid',
    'an input the composer refuses'
);
done_testing();

sub same ( $method, $input, $expected, $label ) {
    ++$serial;
    my %result;
    for my $path (qw(function perl)) {
        my $workflow = workflow($path);
        $result{$path} = $workflow->$method( { %{$input} } );
        if ( ( $result{$path}{status} // q{} ) eq 'failed' ) {
            diag explain $workflow->logger->lines;
        }
    }
    is_deeply(
        public( $result{function} ),
        public( $result{perl} ),
        "$serial $method, $label: the answer is the Perl path's"
    );
    is( $result{function}{status},
        $expected, "$serial $method, $label: $expected" );
    for my $table (
        qw(users credentials identity_tokens event_log outbox_messages audit_log command_log)
      )
    {
        is_deeply(
            snapshot( $pair{function}->dbh, $table ),
            snapshot( $pair{perl}->dbh,     $table ),
            "$serial $method, $label: same $table"
        );
    }
    return;
}

# A registration's answer carries the user as a row object: compared by
# its columns.
sub public ($result) {
    my %copy = %{$result};
    if ( ref $copy{stored} eq 'HASH' && ref $copy{stored}{user} ) {
        my $user = $copy{stored}{user};
        $copy{stored} = {
            %{ $copy{stored} },
            user => {
                map { $_ => $user->get_column($_) }
                  qw(id username email_normalized status)
            },
        };
    }
    return \%copy;
}

sub workflow ($path) {
    my $schema = $pair{$path}->schema;
    my %old    = $path eq 'perl' ? ( functions => undef ) : ();
    my $ids    = GPForum::Test::SequenceId->new(
        prefix => ( sprintf '018f%04x-0000-7000-8000', $serial ) );
    my $clock =
      GPForum::Test::FixedClock->new( iso8601 => $NOW, epoch => $EPOCH );
    my $password = GPForum::Test::FixedPassword->new;
    return GPForum::Service::Identity::Workflow->new(
        command_idempotency =>
          GPForum::Service::Operations::CommandIdempotency->new(
            clock      => $clock,
            id_service => $ids,
            schema     => $schema,
            %old
          ),
        logger       => GPForum::Test::LogLines->new,
        registration => GPForum::Service::Identity::Registration->new(
            id_service       => $ids,
            password_service => $password,
        ),
        store => GPForum::Service::Identity::Store->new(
            clock          => $clock,
            id_service     => $ids,
            password       => $password,
            schema         => $schema,
            session_tokens => GPForum::Test::SessionToken->new,
            %old
        ),
    );
}

sub snapshot ( $dbh, $table ) {
    my $rows =
      $dbh->selectall_arrayref( "SELECT * FROM $table", { Slice => {} } );
    for my $row ( @{$rows} ) {
        if (   $table ne 'audit_log'
            && $table ne 'command_log'
            && $table ne 'event_log' )
        {
            delete @{$row}
              {qw(created_at updated_at available_at next_attempt_at)};
        }
        for my $column (qw(payload metadata)) {
            if ( defined $row->{$column} ) {
                $row->{$column} = $json->decode( $row->{$column} );
            }
        }

        # A mail's token is sealed under a fresh nonce on each path: the
        # token it opens to is what the two must agree on.
        my $mail =
          ref $row->{payload} eq 'HASH' ? $row->{payload}{mail} : undef;
        if ( ref $mail eq 'HASH' && defined $mail->{sealed_token} ) {
            $mail->{sealed_token} =
              GPForum::Service::Identity::MailToken->new->unseal(
                $mail->{sealed_token}, $mail->{token_id} );
        }
    }
    return [ sort { $json->encode($a) cmp $json->encode($b) } @{$rows} ];
}

1;
