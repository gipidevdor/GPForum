# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::DigestResolver;

use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Service::Forum::Viewer;

our $VERSION = '0.001';

# A viewer resolver for the email digest (ADR 0078): every member is a
# member granted the one private category given.
has category_id => '0190a5f2-0000-7000-8000-0000000000c1';

sub resolve ( $self, $user_id ) {
    return GPForum::Service::Forum::Viewer->new(
        user_id      => $user_id,
        member       => 1,
        category_ids => [ $self->category_id ],
    );
}

1;
