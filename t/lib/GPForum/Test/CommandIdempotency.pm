# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::CommandIdempotency;

use v5.40;

use parent 'GPForum::Service::Operations::CommandIdempotency';

use Mojo::Promise;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Text qw(trimmed);

our $VERSION = '0.001';

# Overrides run_p() only: result_of_p() is the real class's, so workflows
# are tested through the code that shapes their answers.

sub new {
    my ( $class, %arguments ) = @_;

    return bless {
        conflict        => $arguments{conflict},
        last_input      => undef,
        replay_response => $arguments{replay_response},
        response        => undef,
    }, $class;
}

sub last_input {
    my ( $self, $value ) = @_;

    if ( @_ > 1 ) {
        $self->{last_input} = $value;
    }

    return $self->{last_input};
}

sub response {
    my ( $self, $value ) = @_;

    if ( @_ > 1 ) {
        $self->{response} = $value;
    }

    return $self->{response};
}

# What run_p answers: invalid without a command id, as the real one is; a
# conflict or a replay when the double was made to answer one; else the
# command run and its response kept.
sub _answer {
    my ( $self, $input, $code, $response_builder ) = @_;

    if ( !length trimmed( $input->{command_id} ) ) {
        return { error => 'command_id is required', invalid => 1 };
    }
    $self->last_input($input);

    if ( $self->{conflict} ) {
        return _conflict_result();
    }
    if ( $self->{replay_response} ) {
        return _replay_result( $self->{replay_response} );
    }

    my $result   = $code->();
    my $response = $response_builder->($result);
    $self->response($response);

    return {
        recorded => 1,
        response => $response,
        result   => $result,
    };
}

# _answer's answer as a settled promise, the command's run_p settled in
# turn: the double holds no call layer for the command to write on.
sub run_p {
    my ( $self, $input ) = @_;

    my $promise;
    try {
        $promise = Mojo::Promise->resolve(
            $self->_answer(
                {
                    map { $_ => $input->{$_} }
                      qw(actor_id command_id command_type request refusal)
                },
                sub {
                    return GPForum::Infrastructure::SqlFunction->settled(
                        $input->{run_p}->() );
                },
                $input->{response} // sub { return $_[0]; },
            )
        );
    }
    catch ($error) { $promise = Mojo::Promise->reject($error); };

    return $promise;
}

sub _conflict_result {
    return {
        conflict => 1,
        error    => 'idempotency key was already used for another request',
    };
}

sub _replay_result {
    my ($response) = @_;

    return {
        replayed => 1,
        response => $response,
    };
}

1;
