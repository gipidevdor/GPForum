# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use JSON::MaybeXS;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Identity::Registration;
use GPForum::Service::Identity::Store;
use GPForum::Service::Identity::Workflow;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::FixedClock;
use GPForum::Test::FixedPassword;
use GPForum::Test::LogLines;
use GPForum::Test::SequenceId;
use GPForum::Test::SessionToken;
use GPForum::Test::SqlFunctionHandle;

our $VERSION = '0.001';

# A registration with a call layer and a command log is one call: what it
# sends -- the command log's row, the user and the credential, the
# registration's event and audit, the verification token with its audit and
# its mail, and the answers to record -- on a handle that records the call
# and answers what the test gives; and what the outcome answers.

const my $NOW    => '2026-10-14T10:00:00Z';
const my $EPOCH  => 1_791_972_000;               # 2026-10-14T10:00:00Z
const my $PREFIX => '018f0011-0000-7000-8000';
const my $DAY    => 86_400;
const my $IDS_DRAWN =>
  14;    # the command log, the account, its records, the token, its records

my $json    = JSON::MaybeXS->new( canonical => 1 );
my %account = (
    command_id   => ' reg-1 ',
    display_name => 'Unit Registrant',
    email        => 'unit@example.invalid',
    password     => 'A long enough password 2026',
    username     => 'unit_registrant',
);

sub fixture ( $rows = [] ) {
    my $handle = GPForum::Test::SqlFunctionHandle->new( rows => $rows );
    my $functions =
      GPForum::Infrastructure::SqlFunction->new( schema => $handle );
    my $ids = GPForum::Test::SequenceId->new( prefix => $PREFIX );
    my $clock =
      GPForum::Test::FixedClock->new( iso8601 => $NOW, epoch => $EPOCH );
    my $password = GPForum::Test::FixedPassword->new;
    my $workflow = GPForum::Service::Identity::Workflow->new(
        command_idempotency =>
          GPForum::Service::Operations::CommandIdempotency->new(
            clock      => $clock,
            functions  => $functions,
            id_service => $ids,
            schema     => $handle,
          ),
        logger       => GPForum::Test::LogLines->new,
        registration => GPForum::Service::Identity::Registration->new(
            id_service       => $ids,
            password_service => $password,
        ),
        store => GPForum::Service::Identity::Store->new(
            clock          => $clock,
            functions      => $functions,
            id_service     => $ids,
            password       => $password,
            schema         => $handle,
            session_tokens => GPForum::Test::SessionToken->new,
        ),
    );
    return ( $handle, $workflow );
}

sub expected_ids ($count) {
    my $ids = GPForum::Test::SequenceId->new( prefix => $PREFIX );
    return map { $ids->uuid } 1 .. $count;
}

# The bound values by the catalogue's parameter names, json decoded.
sub sent ($handle) {
    my @names =
      qw(log answer accepted refused user credential event event_outbox_id audit token token_audit mail_event mail_outbox_id mail_outbox_extras);
    my @values = @{ $handle->executed->[-1] };
    my %sent;
    for my $index ( 0 .. $#names ) {
        my $value = $values[$index];
        $sent{ $names[$index] } =
          defined $value && $value =~ /\A [\[{]/msx
          ? $json->decode($value)
          : $value;
    }
    return \%sent;
}

subtest 'a registration is one call' => sub {
    my (
        $command_id,               $correlation_id,
        $user_id,                  $credential_id,
        $registration_correlation, $event_id,
        $outbox_id,                $audit_id,
        $token_id,                 $action_audit_id,
        $action_correlation,       $mail_correlation,
        $mail_event_id,            $mail_outbox_id
    ) = expected_ids($IDS_DRAWN);
    my $stored_user = {
        id               => $user_id,
        username         => 'unit_registrant',
        email_normalized => 'unit@example.invalid',
        status           => 'pending',
    };
    my ( $handle, $workflow ) = fixture(
        [
            {
                outcome     => 'recorded',
                response    => $json->encode( { ok => 1, status => 'ok' } ),
                stored_user => $json->encode($stored_user),
            }
        ]
    );
    my $result = $workflow->register( {%account} );
    is( $result->{status}, 'ok', 'the registration is accepted' );
    is( $result->{stored}{user}->get_column('id'),
        $user_id, 'with the user the call stored' );
    is( scalar @{ $handle->executed }, 1, 'in one call' );
    like(
        $handle->prepared->[0],
        qr/api[.]identity_register_command_v2/msx,
        'to the registration command'
    );
    my $sent = sent($handle);
    is_deeply(
        $sent->{log},
        {
            actor_id               => undef,
            command_at             => $NOW,
            command_correlation_id => $correlation_id,
            command_id             => $command_id,
            command_type           => 'identity.register',
            idempotency_key        => 'reg-1',
            request_hash           =>
              GPForum::Service::Operations::CommandIdempotency->request_hash(
                {
                    email    => 'unit@example.invalid',
                    username => 'unit_registrant'
                }
              ),
        },
        'the command log row, its ids drawn first'
    );
    is( $sent->{answer}, undef, 'no answer decided before the call' );
    is_deeply(
        $sent->{user},
        {
            display_name      => 'Unit Registrant',
            email_normalized  => 'unit@example.invalid',
            email_verified_at => undef,
            id                => $user_id,
            password_hash     => 'fixed:' . $account{password},
            status            => 'pending',
            trust_level       => 0,
            username          => 'unit_registrant',
        },
        'the user row as the composer prepared it'
    );
    is_deeply(
        $sent->{credential},
        {
            created_at  => $NOW,
            id          => $credential_id,
            secret_hash => 'fixed:' . $account{password},
            type        => 'password',
            user_id     => $user_id,
        },
        'the password credential'
    );
    is( $sent->{event}{event_type},
        'user.registered', 'the registration event' );
    is( $sent->{event}{event_id}, $event_id, 'with its id' );
    is( $sent->{event}{correlation_id},
        $registration_correlation, 'and the registration correlation id' );
    is( $sent->{event_outbox_id}, $outbox_id,        'and its outbox row id' );
    is( $sent->{audit}{action},   'user.registered', 'the registration audit' );
    is( $sent->{audit}{audit_id}, $audit_id,         'with its id' );
    is_deeply(
        [
            @{ $sent->{token} }
              {qw(token_id token_type token_hash user_id expires_at)}
        ],
        [
            $token_id,      'email_verification',
            'hash:token-1', $user_id,
            '2026-10-15T10:00:00Z'
        ],
        'the verification token, a day long'
    );
    is(
        $sent->{token_audit}{action},
        'identity.email_verification.requested',
        'the audit of the request'
    );
    is( $sent->{token_audit}{audit_id}, $action_audit_id, 'with its id' );
    is( $sent->{mail_event}{event_type},
        'identity.mail.requested', 'the mail event' );
    is( $sent->{mail_event}{event_id}, $mail_event_id, 'with its id' );
    is( $sent->{mail_outbox_id}, $mail_outbox_id, 'and its outbox row id' );
    is_deeply(
        $sent->{mail_outbox_extras},
        {
            mail => {
                kind  => 'email_verification',
                to    => 'unit@example.invalid',
                token => 'token-1',
            }
        },
        'the mail with the raw token, for the outbox alone'
    );
    is( $sent->{accepted}{stored}{user_id},
        $user_id, 'the accepted answer names the user' );
    ok( !exists $sent->{accepted}{stored}{user}, 'and carries no row object' );
    is(
        $sent->{refused}{errors}{registration},
        'registration request could not be accepted',
        'the refused answer, for a taken username or email'
    );
};

subtest 'an input the composer refuses is recorded without a write' => sub {
    my $refusal = {
        error  => undef,
        errors => { email => 'email must be a valid address' },
        ok     => 0,
        status => 'invalid',
        stored => { values => {} },
    };
    my ( $handle, $workflow ) = fixture(
        [ { outcome => 'recorded', response => $json->encode($refusal) } ] );
    my $result = $workflow->register( { %account, email => 'not an address' } );
    is( $result->{status}, 'invalid', 'the answer is invalid' );
    ok( $result->{errors}{email}, 'with the composer\'s words' );
    is( scalar @{ $handle->executed }, 1, 'one call' );
    my $sent = sent($handle);
    is( $sent->{answer}{status}, 'invalid', 'sends the refusal to record' );
    is( $sent->{user},           undef,     'and no user row' );
    is( $sent->{token},          undef,     'nor a token' );
};

subtest 'a replay answers the stored response, a conflict its words' => sub {
    for my $case (
        [
            replayed =>
              { ok => 1, status => 'ok', stored => { user_id => 'x' } }
        ],
        [ conflict    => undef ],
        [ in_progress => undef ],
      )
    {
        my ( $outcome, $response ) = @{$case};
        my ( $handle,  $workflow ) = fixture(
            [
                {
                    outcome  => $outcome,
                    response => $response ? $json->encode($response) : undef
                }
            ]
        );
        my $result = $workflow->register( {%account} );
        if ($response) {
            is_deeply( $result, $response, "$outcome: the stored response" );
        }
        else {
            is( $result->{status}, 'conflict', "$outcome: a conflict" );
            is(
                $result->{error},
                GPForum::Service::Operations::CommandIdempotency->refusal_error(
                    $outcome),
                "$outcome: in the log's words"
            );
        }
    }
};

done_testing();

1;
