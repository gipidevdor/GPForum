# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::PostingFunctions;

use Carp qw(croak);
use Const::Fast;
use Mojo::Base 'GPForum::Test::LoggedCalls', -signatures;
use v5.40;

use GPForum::Domain::Post;
use GPForum::Service::Forum::PostStore;
use GPForum::Service::Forum::PostingCommand;
use GPForum::Service::Forum::PostingWorkflow;
use GPForum::Service::Forum::ThreadStore;

our $VERSION = '0.001';

# The posting functions (ADR 0126) over in-memory services: the command log
# kept here by idempotency key -- the same request again replays its
# response, another one is a conflict -- and each write handed to the
# sink's store method, as api.forum_write_command and
# api.forum_create_reply hand theirs to the store steps. The post context
# comes from the reader's rows.
const my %WRITE => (
    'post.deleted'     => 'delete_post',
    'post.undeleted'   => 'restore_post',
    'post.updated'     => 'edit_post',
    'thread.created'   => 'create_thread',
    'thread.deleted'   => 'delete_thread',
    'thread.moved'     => 'move_thread',
    'thread.undeleted' => 'restore_thread',
    'thread.updated'   => 'edit_thread',
);
const my @REPLY_POST => qw(post_id thread_id author_user_id position
  visibility);

# The functions answered here, by name; any other dies naming its method.
const my %FUNCTION => (
    forum_create_reply  => \&_forum_create_reply,
    forum_post_context  => \&_forum_post_context,
    forum_write_command => \&_forum_write_command,
);

# The store step whose statements raise a sink's failure, by the noun of
# the write: PostgreSQL names it in the error's context, and the workflow
# tells a store failure from a command log failure by that name.
const my %STORE_STEP => (
    post   => 'api.core_forum_write_post_v1',
    reply  => 'api.core_forum_store_reply_v1',
    thread => 'api.core_forum_write_thread_v1',
);

has reader => undef;    # the rows a post's context is read from
has sink   => undef;    # the store methods each write is handed to
has codec  => sub { return GPForum::Service::Forum::PostingCommand->new; };

# The post and thread stores of a workflow whose writes these functions
# take: the real parameter builders, on this layer.
sub stores ( $class, %options ) {
    my $functions = $class->new(%options);
    return (
        post_store => GPForum::Service::Forum::PostStore->new(
            functions => $functions,
            schema    => {},
        ),
        thread_store => GPForum::Service::Forum::ThreadStore->new(
            functions => $functions,
            schema    => {},
        ),
    );
}

# Installs those stores as an application's gp_post_store and
# gp_thread_store, and a posting workflow on its collaborators without the
# automod and review stores, which are PostgreSQL's.
sub install ( $class, $app, %options ) {
    my %stores = $class->stores(%options);
    for my $name ( sort keys %stores ) {
        $app->helper( "gp_$name" => sub { return $stores{$name}; } );
    }
    $app->helper(
        gp_posting_workflow => sub ($controller) {
            return GPForum::Service::Forum::PostingWorkflow->new(
                logger => $controller->app->log,
                map { $_ => $controller->${ \"gp_$_" } }
                  qw(category_reader command_idempotency mention_store
                  post_composer post_store thread_composer
                  thread_detail_reader thread_store)
            );
        }
    );

    return \%stores;
}

sub rows ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, $values ];
    my $method = $FUNCTION{$name} // "_$name";
    return [ $self->$method($values) // () ];
}

sub _forum_post_context ( $self, $values ) {
    my $post = _hash( $self->reader->find_post( $values->{post_id} ) )
      or return { post => undef, thread => undef };
    return {
        post   => $post,
        thread => _hash( $self->reader->find_thread_row( $post->{thread_id} ) ),
    };
}

sub _forum_write_command ( $self, $values ) {
    my $log = $values->{log};
    return $self->logged(
        $log->{idempotency_key},
        $log->{request_hash},
        $values->{answer},
        sub {
            my $type   = $values->{store_type};
            my ($noun) = split /[.]/msx, $type;
            my $stored =
              $self->_store( $STORE_STEP{$noun}, $WRITE{$type},
                $values->{command} );
            return ( $self->_response( $log->{command_type}, $stored ),
                { stored => $stored } );
        }
    );
}

sub _forum_create_reply ( $self, $values ) {
    return $self->logged(
        $values->{idempotency_key},
        $values->{request_hash},
        $values->{answer},
        sub {
            my $stored = $self->_store(
                $STORE_STEP{reply},
                'create_post',
                {
                    idempotency_key => $values->{idempotency_key},
                    post => { map { $_ => $values->{$_} } @REPLY_POST },
                }
            );
            return (
                $self->_response( 'reply.create', $stored ),
                $stored->{ok} ? $stored->{post} : {}
            );
        }
    );
}

# The sink's answer to a write; a sink that dies fails the call as a
# failure of the store step would, naming that step.
sub _store ( $self, $step, $method, $command ) {
    my $answer;
    try { $answer = $self->sink->$method($command); }
    catch ($error) { croak "$step: $error"; };

    return _stored($answer);
}

sub _response ( $self, $type, $stored ) {
    return {
        ok     => 0,
        status => GPForum::Domain::Post->status_of( $stored->{error} )
          // 'failed',
        error => $stored->{error},
      }
      if !$stored->{ok};

    return $self->codec->response( $type,
        { ok => 1, status => 'ok', stored => $stored } );
}

sub _stored ($answer) {
    return { ok => 0, error => 'store failed' } if ref $answer ne 'HASH';
    return { %{$answer},
        map { $_ => _hash( $answer->{$_} ) }
        grep { ref $answer->{$_} } qw(post thread) };
}

sub _hash ($row) {
    return undef       if !$row;
    return { %{$row} } if ref $row eq 'HASH';

    return { $row->get_columns };
}

1;

__END__

=head1 NAME

GPForum::Test::PostingFunctions - The posting functions over in-memory services.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $services = GPForum::Test::ForumWebServices->new;
    my %stores   = GPForum::Test::PostingFunctions->stores(
        reader => $services,
        sink   => $services,
    );
    $app->helper( gp_post_store   => sub { return $stores{post_store}; } );
    $app->helper( gp_thread_store => sub { return $stores{thread_store}; } );

    # or, the same:
    GPForum::Test::PostingFunctions->install( $app, reader => $services,
        sink => $services );

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::SqlFunction> under a posting
workflow whose collaborators are in-memory doubles, so the workflow's own
Perl -- its checks, its composers, its plan and its answers -- runs as it
runs on PostgreSQL. It answers C<forum_post_context> from the C<reader>'s
rows, and C<forum_write_command> and C<forum_create_reply> by keeping the
command log here, by idempotency key, and handing each write to the
C<sink>'s store method (C<create_thread>, C<create_post>, C<edit_post>...).
Its promises are settled (L<GPForum::Test::LoggedCalls>).

=head1 SUBROUTINES/METHODS

=head2 stores

Class method taking C<reader> and C<sink>: a
L<GPForum::Service::Forum::PostStore> and a
L<GPForum::Service::Forum::ThreadStore> on a new layer of these functions,
as C<post_store> and C<thread_store>.

=head2 install

Class method taking an application and the options of L</stores>: installs
those stores as its C<gp_post_store> and C<gp_thread_store> helpers, and a
C<gp_posting_workflow> on the application's collaborators without the
automod and review stores, and answers the stores.

=head2 rows

Takes a function's name and values; answers its rows.

=head2 reader

The double whose C<find_post> and C<find_thread_row> rows a post's context
is read from.

=head2 sink

The double whose store methods each write is handed to. Its answer is the
stored answer or the refusal; when it dies, see L</DIAGNOSTICS>.

=head2 codec

The L<GPForum::Service::Forum::PostingCommand> the responses are made with.

=head1 DIAGNOSTICS

A function it does not know dies naming its method. A sink that dies fails
the call with its error prefixed by the store step whose failure that is
(C<api.core_forum_write_post_v1>, C<api.core_forum_write_thread_v1> or
C<api.core_forum_store_reply_v1>), as PostgreSQL names it, so the workflow
answers C<post store failed> or C<thread store failed>; nothing is then
kept in the command log.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Carp>, L<GPForum::Test::LoggedCalls>, L<GPForum::Domain::Post>,
L<GPForum::Service::Forum::PostStore>,
L<GPForum::Service::Forum::PostingCommand>,
L<GPForum::Service::Forum::ThreadStore>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The store steps' own checks under their locks are the sink's to make.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
