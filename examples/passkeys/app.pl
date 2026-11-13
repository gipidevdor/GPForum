#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use FindBin qw($Bin);
use lib "$Bin/local/lib/perl5", "$Bin/lib";
use Mojo::Home;
use GPForum::Example::Passkeys::App;

our $VERSION = '0.001';

GPForum::Example::Passkeys::App->new( home => Mojo::Home->new($Bin) )->start;

1;
