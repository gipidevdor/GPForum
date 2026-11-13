# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Schema::Result::ThreadCounter;

use Mojo::Base 'DBIx::Class::Core', -signatures;
use v5.40;

our $VERSION = '0.001';

__PACKAGE__->table('thread_counters');

__PACKAGE__->add_columns(
    thread_id => {
        data_type   => 'uuid',
        is_nullable => 0,
    },
    reply_count => {
        data_type     => 'bigint',
        default_value => 0,
        is_nullable   => 0,
    },
);

__PACKAGE__->set_primary_key('thread_id');
__PACKAGE__->belongs_to(
    thread => 'GPForum::Schema::Result::Thread',
    'thread_id'
);

1;
