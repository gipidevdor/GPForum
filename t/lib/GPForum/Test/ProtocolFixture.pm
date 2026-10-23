# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::ProtocolFixture;

use v5.40;
use Const::Fast;
use Mojo::Transaction::HTTP;
use Mojo::Promise;

our $VERSION = '0.001';
const my $HTTP_ACCEPTED => 202;

sub post ( $self, $url, @arguments ) {
    $self->{posted_url}       = $url;
    $self->{posted_arguments} = \@arguments;
    my $tx = Mojo::Transaction::HTTP->new;
    $tx->res->code( $self->{hub_status} // $HTTP_ACCEPTED );
    return $tx;
}

sub post_p ( $self, @arguments ) {
    return Mojo::Promise->resolve( $self->post(@arguments) );
}

sub new ( $class, %args ) { return bless \%args, $class; }

sub row ( $self, @args ) {
    return {
        id                => $self->{user},
        email_normalized  => 'alice@example.net',
        email_verified_at => '2026-10-23',
        trust_level       => 0
    };
}

sub resolve ( $self, $user ) {
    return GPForum::Service::Forum::Viewer->new(
        user_id => $user,
        member  => 1
    );
}
sub can_participate ( $self, $id )    { return { ok => !$self->{suspended} }; }
sub check           ( $self, $input ) { return { ok => 1 }; }
sub level           ( $self, $id )    { return 0; }

sub create_reply ( $self, $input ) {
    $self->{command} = $input;
    return { ok => 1, status => 'post_created' };
}

sub list_categories ( $self, $input ) {
    return [
        GPForum::Infrastructure::ResultRow->from(
            { category_id => $self->{thread}, title => 'Community' }
        )
    ];
}

sub thread_page ( $self, $input ) {
    return {
        ok     => 1,
        thread =>
          GPForum::Infrastructure::ResultRow->from( { title => 'Hello' } ),
        posts => {
            items => [
                GPForum::Infrastructure::ResultRow->from(
                    {
                        body_source     => $self->{body},
                        author_username => 'alice'
                    }
                )
            ]
        }
    };
}

1;
