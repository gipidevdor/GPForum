# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::Embedding;

use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;
use English qw(-no_match_vars);
use File::Spec;
use IPC::Open3   qw(open3);
use Mojo::JSON   qw(encode_json decode_json);
use POSIX        qw(isfinite);
use Scalar::Util qw(looks_like_number);
use Symbol       qw(gensym);
use GPForum::X::Unavailable;

our $VERSION = '0.001';
const my $DIMENSIONS => 384;
const my $MAX_TEXT   => 2_000;
const my $MAX_OUTPUT => 32_768;
const my $READ_SIZE  => 4_096;

# No model download or remote code at runtime. Each invocation is a bounded
# local process; text travels on stdin, never in arguments or diagnostics.
const my $PROGRAM => <<'PYTHON';
import json, os, sys
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
os.environ["TOKENIZERS_PARALLELISM"] = "false"
from sentence_transformers import SentenceTransformer
import torch
torch.set_num_threads(1)
model = SentenceTransformer(sys.argv[1], device="cpu", local_files_only=True,
                            trust_remote_code=False)
text = json.load(sys.stdin)
vector = model.encode(text, normalize_embeddings=True, show_progress_bar=False)
json.dump(vector.tolist(), sys.stdout, allow_nan=False)
PYTHON

has model_path      => undef; # optional: semantic search is off without a model
has model_key       => 'multilingual-minilm-l12-v2';
has python          => 'python3';
has timeout_seconds => 5;
has command         => sub ($self) {
    return [ $self->python, '-c', $PROGRAM, $self->model_path ];
};

sub from_config ( $class, $config ) {
    return undef if !length( $config->search_embedding_model_path // q{} );
    return $class->new(
        model_path      => $config->search_embedding_model_path,
        model_key       => $config->search_embedding_model_key,
        python          => $config->search_embedding_python,
        timeout_seconds => $config->search_embedding_timeout_seconds,
    );
}

sub embed ( $self, $text ) {
    my $bounded = substr $text // q{}, 0, $MAX_TEXT;
    my $literal;
    try {
        my $input = encode_json($bounded);
        $literal =
          $self->vector_literal( decode_json( $self->_execute($input) ) );
    }
    catch ($error) {

        # Process launch and JSON failures can include executable paths or
        # model output. Keep the same public failure boundary for every case.
        _unavailable();
    };
    return $literal;
}

sub vector_literal ( $, $vector ) {
    if ( ref $vector ne 'ARRAY' || @{$vector} != $DIMENSIONS ) {
        _unavailable();
    }
    my $norm = 0;
    for my $value ( @{$vector} ) {
        if (   ref $value
            || !defined $value
            || !looks_like_number($value)
            || !isfinite($value)
            || abs($value) > 1 )
        {
            _unavailable();
        }
        $norm += $value * $value;
    }
    if ( !$norm ) { _unavailable(); }
    return q{[} . join( q{,}, map { 0 + $_ } @{$vector} ) . q{]};
}

sub _execute ( $self, $input_json ) {
    my $output = gensym;
    open my $errors, '>', File::Spec->devnull or _unavailable();

    # An opened glob is otherwise replaced with a pipe by open3; closing its
    # read end makes a model writing diagnostics fail with SIGPIPE.
    my $pid =
      open3( my $input, $output, '>&' . fileno($errors), @{ $self->command } );
    close $errors or _unavailable();
    my $read = q{};
    try {
        local $SIG{ALRM} = sub { _unavailable(); };
        local $SIG{PIPE} = 'IGNORE';
        alarm $self->timeout_seconds;
        print {$input} $input_json or _unavailable();
        close $input               or _unavailable();
        while (1) {
            my $chunk;
            my $size = read $output, $chunk, $READ_SIZE;
            if ( !defined $size ) { _unavailable(); }
            last if !$size;
            $read .= $chunk;
            if ( length($read) > $MAX_OUTPUT ) { _unavailable(); }
        }
        waitpid $pid, 0;
        if ($CHILD_ERROR) { _unavailable(); }
        alarm 0;
    }
    catch ($error) {
        alarm 0;
        kill 'KILL', $pid;
        waitpid $pid, 0;
        _unavailable();
    };
    return $read;
}

sub _unavailable {
    GPForum::X::Unavailable->throw( message => 'local embedding unavailable' );
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::Embedding - Bounded offline sentence embeddings.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $provider = GPForum::Infrastructure::Embedding->from_config($config);
    my $vector = $provider->embed('Come ridurre i consumi?');

=head1 DESCRIPTION

Runs Sentence Transformers locally, on CPU, with downloads and remote code
disabled. The model must produce 384 dimensions. Inputs are limited to 2000
characters; the model may truncate further at its token limit.

=head1 SUBROUTINES/METHODS

=head2 from_config

Returns a provider, or undef when no model directory is configured.

=head2 embed

Returns a validated pgvector literal, or throws on timeout or model failure.

=head2 vector_literal

Validates a finite, nonzero 384-dimensional vector with components in [-1,1].

=head1 DIAGNOSTICS

Failures say C<local embedding unavailable> and contain no input text.

=head1 CONFIGURATION AND ENVIRONMENT

C<GPFORUM_SEARCH_EMBEDDING_MODEL_PATH>, C<GPFORUM_SEARCH_EMBEDDING_MODEL_KEY>,
C<GPFORUM_SEARCH_EMBEDDING_PYTHON>, C<GPFORUM_SEARCH_EMBEDDING_TIMEOUT_SECONDS>.

=head1 DEPENDENCIES

Python with Sentence Transformers and a preinstalled local model.

=head1 INCOMPATIBILITIES

Models with dimensions other than 384 require a schema change.

=head1 BUGS AND LIMITATIONS

Model startup is included in each call's timeout and consumes local CPU/RAM.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause license.

=cut
