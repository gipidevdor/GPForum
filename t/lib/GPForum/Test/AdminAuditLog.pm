# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::AdminAuditLog;

use JSON::MaybeXS;
use Mojo::Base 'GPForum::Test::SettledCalls', -signatures;
use v5.40;

use Mojo::Promise;

our $VERSION = '0.001';

my $CODEC = JSON::MaybeXS->new( canonical => 1, utf8 => 0 );

# The audit log as Admin::Diagnostics sees it: its call layer's
# api.ops_record_audit appends a row, and page, AuditReview's, reads rows
# back newest first by action -- so a test follows a check from its audit
# write to the settings page that shows it. The metadata goes through JSON,
# as it does into a jsonb column, so a value the database could not store
# fails here too. The log is its own recorder, call layer and audit review.
has rows => sub { return []; };

# EventRecorder's: the record ops_record_audit is sent, here the row as it
# was given.
sub audit_call ( $self, %row ) {
    return { audit => {%row}, explicit => 0 };
}

# The two functions Diagnostics calls: the audit insert, and the SET LOCAL
# that lets a slow check's transaction sit idle, which a log has no need of.
sub row ( $self, $name, $values ) {
    return { audit => $self->record_audit( %{ $values->{audit} } ) }
      if $name eq 'ops_record_audit';
    return {} if $name eq 'admin_allow_slow_answer';
    die "AdminAuditLog does not answer $name\n";
}

sub rows ( $self, $name, $values ) {
    die "AdminAuditLog does not answer $name\n";
}

sub record_audit ( $self, %row ) {
    my $stored = {
        %row,
        audit_id => 'audit-' . ( 1 + scalar @{ $self->rows } ),
        metadata => $CODEC->decode( $CODEC->encode( $row{metadata} // {} ) ),
    };
    push @{ $self->rows }, $stored;

    return { %{$stored} };
}

sub page ( $self, $filters, $page ) {
    my $action = $filters->{action};
    my @rows   = reverse grep { !defined $action || $_->{action} eq $action }
      @{ $self->rows };
    my $limit = $page->{limit} || scalar @rows;
    if ( @rows > $limit ) {
        splice @rows, $limit;
    }

    return {
        next_cursor => undef,
        rows        => [ map { +{ %{$_} } } @rows ],
    };
}

sub page_p ( $self, $filters, $page, $context = undef ) {
    return Mojo::Promise->resolve( $self->page( $filters, $page ) );
}

# The rows for one action, oldest first.
sub actions ( $self, $action ) {
    return [ grep { $_->{action} eq $action } @{ $self->rows } ];
}

1;

__END__

=head1 NAME

GPForum::Test::AdminAuditLog - Recording audit log for the console diagnostics.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $log = GPForum::Test::AdminAuditLog->new;
    GPForum::Service::Admin::Diagnostics->new(
        audit_review => $log,
        functions    => $log,
        recorder     => $log,
        ...
    );

=head1 DESCRIPTION

Stands in for the call layer that runs C<api.ops_record_audit>, for
L<GPForum::Infrastructure::EventRecorder> (C<audit_call>) and for
L<GPForum::Service::Admin::AuditReview> (C<page>, filtered by action,
newest first), so the row a check writes is the row the page reads.

=head1 SUBROUTINES/METHODS

=head2 audit_call

The call sent to C<api.ops_record_audit>: the row as given.

=head2 row

Answers C<ops_record_audit> by storing the row, and
C<admin_allow_slow_answer> with nothing; dies on any other function.

=head2 rows

Dies: no list function is answered.

=head2 record_audit

Stores the row, its metadata round-tripped through JSON.

=head2 page

The rows matching C<action>, newest first, up to C<limit>.

=head2 page_p

C<page> as a settled promise.

=head2 actions

The stored rows for one action, oldest first.

=head1 DIAGNOSTICS

Dies when metadata cannot be encoded, as a jsonb insert would fail.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Test::SettledCalls>, L<JSON::MaybeXS>, L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

No hash chain, cursor or date filter.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
