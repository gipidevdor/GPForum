# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::QueryPlanEvidence;
use Mojo::Base 'GPForum::Command::QueryPlanEvidence', -signatures;
use v5.40;
use GPForum::Test::LegacySchema;
our $VERSION = '0.001';
has schema => sub {
    return GPForum::Test::LegacySchema->connect(
        'dbi:Pg:dbname=gpforum_sql_shape_only');
};
1;
