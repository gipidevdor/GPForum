# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::FeatureBootstrap;
use v5.40;
use English qw(-no_match_vars);
our $VERSION = '0.001';

sub import ($class) {
    if ( $PROGRAM_NAME =~ m{(?:\A|/)t/integration/}msx ) {
        require GPForum::Test::TemporaryPostgres;
        GPForum::Test::TemporaryPostgres->import;
    }
    require GPForum::Performance::OperationProbe;
    GPForum::Performance::OperationProbe->import;
    require GPForum::Test::FeatureProbe;
    GPForum::Test::FeatureProbe->import;
    return;
}
1;
