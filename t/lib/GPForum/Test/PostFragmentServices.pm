# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::PostFragmentServices;

use Mojo::Base 'GPForum::Test::ForumWebServices', -signatures;
use v5.40;

our $VERSION = '0.001';

has allowed => 1;
has source  => 'First post';
has author  => 'GPForum Contributors';

sub thread_page ( $self, $request ) {
    return { ok => 0, error => 'not_found' } if !$self->allowed;
    my $page = $self->SUPER::thread_page($request);
    if ( $page->{ok} ) {
        my $post = $page->{posts}{items}[0];
        $post->{body_source}         = $self->source;
        $post->{author_display_name} = $self->author;
    }
    return $page;
}

1;
