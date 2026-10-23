# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::Admission;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Mojo::JSON qw(true false);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Id;
use GPForum::Service::SessionToken;

our $VERSION = '0.001';

__PACKAGE__->requires('schema');
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};
has tokens => sub { return GPForum::Service::SessionToken->new; };

sub overview ( $self, $actor ) {
    my $row =
      $self->functions->row( 'admin_registration_state', { actor => $actor } );
    return $row ? $row->{result} : { status => 'forbidden' };
}

sub change ( $self, $input ) {
    return { status => 'invalid' }
      if !GPForum::Infrastructure::Id->is_uuid( $input->{command} );
    my $operation = $input->{operation} // q{};
    my $field =
      { revoke => 'invitation_id', approve => 'user_id', reject => 'user_id' }
      ->{$operation};
    return { status => 'invalid' }
      if $field && !GPForum::Infrastructure::Id->is_uuid( $input->{$field} );
    my $prepared = $self->_prepare($input);
    my $row      = $self->functions->row(
        'admin_registration_change',
        {
            actor     => $input->{actor},
            command   => $input->{command},
            operation => $operation,
            values    => $prepared->{values},
        }
    );
    my $result = $row ? $row->{result} : { status => 'invalid' };
    if (   $operation eq 'invite'
        && $result->{status} eq 'ok'
        && !$result->{replayed} )
    {
        $result->{invitation} = $prepared->{token};
    }
    return $result;
}

sub _prepare ( $self, $input ) {
    my $operation = $input->{operation} // q{};
    if ( $operation eq 'invite' ) {
        my $token = $self->tokens->issue_token;
        return {
            token  => $token,
            values => {
                email      => lc( $input->{email} // q{} ),
                token_hash => $self->tokens->hash_token($token)
            }
        };
    }
    if ( $operation eq 'policy' ) {
        return {
            values => {
                mode              => $input->{mode},
                approval_required => $input->{approval_required} ? true : false
            }
        };
    }
    my $field = $operation eq 'revoke' ? 'invitation_id' : 'user_id';
    return { values => { $field => $input->{$field} } };
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::Admission - Registration invitations and staff approval.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $admission->overview($staff_id);
    $admission->change({actor => $staff_id, command => $id, operation => 'approve', user_id => $member_id});

=head1 DESCRIPTION

Only PostgreSQL functions read or change admission state. Single-use
invitations are bound to an email address and expire in seven days. Their
random secret is returned once; only its hash is stored. Replaying creation
returns the invitation id without a secret: revoke and issue another if lost.

=head1 SUBROUTINES/METHODS

=head2 overview

Reads policy, up to 100 waiting accounts and 100 recent invitations for staff.

=head2 change

Changes policy, issues or revokes an invitation, or approves/rejects an account.

=head1 DIAGNOSTICS

Returns status; database exceptions propagate.

=head1 CONFIGURATION AND ENVIRONMENT

Policy resides in PostgreSQL, open registration without staff approval by default.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>, L<GPForum::Service::SessionToken>.

=head1 INCOMPATIBILITIES

Requires migration 1026.

=head1 BUGS AND LIMITATIONS

Invitations are copied by the operator; no invitation mail is sent automatically.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. BSD-3-Clause.

=cut
