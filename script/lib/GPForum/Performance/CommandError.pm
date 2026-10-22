# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Performance::CommandError;

use v5.40;
use overload
  q{""}    => sub ( $self, @ignored ) { return $self->{message}; },
  fallback => 1;

our $VERSION = '0.001';

sub new ( $class, $message, $timed_out, $returncode ) {
    return bless {
        message    => $message,
        timed_out  => $timed_out,
        returncode => $returncode
    }, $class;
}

1;
