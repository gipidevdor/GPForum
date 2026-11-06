# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::OSTinyLinux;

use Mojo::Base 'GPForum::OS::Linux';
use v5.40;

our $VERSION = '0.001';

sub cpu_count {
    return 1;
}

1;
