# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::LegacySchema;
use Mojo::Base 'DBIx::Class::Schema', -signatures;
use v5.40;
our $VERSION = '0.001';
__PACKAGE__->load_namespaces( result_namespace => '+GPForum::Schema::Result' );
1;
