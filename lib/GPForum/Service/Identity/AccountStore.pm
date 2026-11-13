# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::AccountStore;

use Mojo::Base 'GPForum::Service::Identity::Account::EmailVerify', -signatures;
use v5.40;

use GPForum::Infrastructure::SqlFunction;

use GPForum::Service::Clock;
use GPForum::Service::Identity::Support;

our $VERSION = '0.001';

__PACKAGE__->requires(
    qw(audit credential_store password schema session_store token_store));
has clock   => sub { return GPForum::Service::Clock->new; };
has support => sub { return GPForum::Service::Identity::Support->new; };

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each write is written once, as its promise method, METHOD_p, in the parts
# this class inherits: it takes the input, an optional query context and an
# optional call layer to write on (the transaction a command log holds), and
# runs its steps in one transaction of that layer. The blocking METHOD is
# its twin on the blocking layer (ADR 0177); there is no other path.

1;

__END__

=head1 NAME

GPForum::Service::Identity::AccountStore - Password and email account writes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = $store->change_password(
        {
            current_password => $current,
            new_password     => $new,
            user_id          => $user_id,
        }
    );

=head1 DESCRIPTION

Owns password reset, password change, and email change persistence. The
identity store facade delegates these commands so HTTP and workflow callers
keep a stable API. Credential, session, token, and audit stores keep their
row-level ownership. Issued tokens enqueue C<identity.mail.requested> on
the outbox in the same transaction; EventLog payloads keep C<kind> and
C<token_id> only.

=head1 SUBROUTINES/METHODS

This class adds no methods of its own. It inherits them from the parts it is
built from, each documented in its own file:

=over 4

=item L<GPForum::Service::Identity::Account::Passwords>

C<request_password_reset_p>, C<reset_password_p>, C<change_password_p> and their blocking twins.

=item L<GPForum::Service::Identity::Account::EmailChange>

C<request_email_change_p>, C<confirm_email_change_p> and their blocking twins.

=item L<GPForum::Service::Identity::Account::EmailVerify>

C<request_email_verification_p>, C<confirm_email_verification_p>, their blocking twins, and C<verification_calls>.

=item L<GPForum::Service::Identity::Account::Core>

The lookups and records the three share.

=back

=head1 DIAGNOSTICS

Missing users and invalid tokens return C<not_found> or C<invalid_token>.
Weak passwords return C<password_too_short>. Duplicate emails return
C<email_already_registered>. Password reset for unknown identifiers still
returns C<ok> without a token.

=head1 CONFIGURATION AND ENVIRONMENT

Requires the PostgreSQL function layer plus credential, session, token, and
audit collaborators supplied by the identity store facade; without the layer
a write raises L<GPForum::X::Unavailable>.

=head1 DEPENDENCIES

Uses L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict> and
L<GPForum::Service::Identity::Support>.

Extends L<GPForum::Base>: built without C<audit>, C<credential_store>,
C<password>, C<schema>, C<session_store> or C<token_store> it throws
L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Password reset remains non-enumerative: unknown identifiers succeed without
issuing a token.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
