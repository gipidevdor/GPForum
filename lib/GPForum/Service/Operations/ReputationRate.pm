# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Operations::ReputationRate;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';
__PACKAGE__->requires('schema');

sub level ( $self, $user_id ) {
    return 0 if !GPForum::Infrastructure::Id->is_uuid($user_id);
    my $level = 0;
    try {
        if ( my $functions =
            GPForum::Infrastructure::SqlFunction->for_schema( $self->schema ) )
        {
            my $row = $functions->row( 'forum_protocol_member',
                { user_id => $user_id, email => undef } );
            return $row ? $row->{trust_level} : 0;
        }
        my $user = $self->schema->resultset('User')->find($user_id);
        if (   $user
            && $user->get_column('status') eq 'active'
            && !defined $user->get_column('deleted_at') )
        {
            $level = $user->get_column('trust_level');
        }
    }
    catch ($error) { return 0; };
    return 0 if !defined $level || $level !~ /\A [0-4] \z/msx;
    return 0 + $level;
}

1;

__END__

=head1 NAME

GPForum::Service::Operations::ReputationRate - Resolve server-side trust for rate limits.

=head1 DESCRIPTION

C<level($user_id)> reads the active account's trust level (0 to 4).
Unknown, closed or unreadable accounts receive level zero. Clients cannot
supply this value. Anonymous readers do not cause an account lookup.

=head1 SUBROUTINES/METHODS

=head2 level

Returns the active account trust level, falling back to zero on absent or unavailable account data.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $level = $policy->level($user_id);

=head1 DIAGNOSTICS

Unavailable or missing accounts receive trust level zero.

=head1 CONFIGURATION AND ENVIRONMENT

Inject the application schema.

=head1 DEPENDENCIES

SqlFunction and Infrastructure::Id.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Does not grant account permissions or bypass suspension checks.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
