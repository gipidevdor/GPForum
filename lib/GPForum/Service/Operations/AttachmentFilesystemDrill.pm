# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Operations::AttachmentFilesystemDrill;

use Carp qw(croak);
use Const::Fast;
use Digest::SHA qw(sha256_hex);
use English     qw(-no_match_vars);
use File::Copy  qw(copy);
use File::Find  qw(find);
use File::Path  qw(make_path remove_tree);
use File::Spec;
use File::Temp qw(tempdir);
use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::File qw(path);

use GPForum::Infrastructure::Text qw(has_text);
use GPForum::Service::Attachment::FilesystemStorage;
use GPForum::Service::Operations::EvidenceHost qw(
  evidence_trimmed
);
use GPForum::Service::Operations::EvidenceMeta qw(evidence_finalize);
use GPForum::X::Check;

our $VERSION = '0.001';

const my $DEFAULT_ROOT => 'var/attachments';
const my $SAMPLE_KEY_A => 'drill/aa/bb/sample-one.bin';
const my $SAMPLE_KEY_B => 'drill/cc/nested/sample-two.txt';
const my $SAMPLE_BYTES_A => join q{},
  ( pack 'H*', '0001' ), 'GPForum-attachment-drill-a', ( pack 'H*', 'ff' );
const my $SAMPLE_BYTES_B => "attachment drill sample b\nline2\n";
const my $RESIDUAL_BETA  => 'This drill does not claim private-beta readiness.';
const my $RESIDUAL_LIVE =>
'Live production attachment trees and object-storage backends remain outside this rehearsal; the drill populates a throwaway var/attachments layout only.';

# The command's options: the drill reads none of them.
sub run ( $self, @ ) {
    my $evidence = _base_evidence();
    try {
        $self->_execute($evidence);
    }
    catch ($error) {
        $evidence->{status} = 'fail';
        $evidence->{error}  = evidence_trimmed($error);
    };
    $evidence->{status} ||= 'pass';
    $self->_cleanup($evidence);

    return evidence_finalize($evidence);
}

sub _execute ( $self, $evidence ) {
    my $workspace = tempdir( 'gpforum-attach-drill-XXXXXX', TMPDIR => 1 );
    $evidence->{_workspace} = $workspace;

    my $source_root = path( $workspace, $DEFAULT_ROOT )->to_string;
    my $backup_root = path( $workspace, 'backup', $DEFAULT_ROOT )->to_string;
    make_path($source_root);

    my $storage =
      GPForum::Service::Attachment::FilesystemStorage->new(
        root => $source_root );
    $storage->write_object( $SAMPLE_KEY_A, $SAMPLE_BYTES_A );
    $storage->write_object( $SAMPLE_KEY_B, $SAMPLE_BYTES_B );

    my $before = _inventory($source_root);
    _assert_inventory_size( $before, 2 );
    _copy_tree( $source_root, $backup_root );
    my $backup = _inventory($backup_root);
    _assert_inventories_match( $before, $backup, 'backup' );

    remove_tree( $source_root, { keep_root => 1 } );
    _assert_empty($source_root);

    _copy_tree( $backup_root, $source_root );
    my $after = _inventory($source_root);
    _assert_inventories_match( $before, $after, 'restore' );

    my $restored =
      GPForum::Service::Attachment::FilesystemStorage->new(
        root => $source_root );
    if ( $restored->read_object($SAMPLE_KEY_A) ne $SAMPLE_BYTES_A ) {
        GPForum::X::Check->throw(
            message => 'restored object A content mismatch' );
    }
    if ( $restored->read_object($SAMPLE_KEY_B) ne $SAMPLE_BYTES_B ) {
        GPForum::X::Check->throw(
            message => 'restored object B content mismatch' );
    }

    $evidence->{attachments} = {
        covered              => true,
        mode                 => 'populated_var_attachments',
        storage_backend      => 'filesystem',
        storage_root         => $DEFAULT_ROOT,
        workspace_layout     => $DEFAULT_ROOT,
        files                => scalar keys %{$after},
        sha256_match         => true,
        sample_object_keys   => [ $SAMPLE_KEY_A, $SAMPLE_KEY_B ],
        backup_path          => $backup_root,
        restore_path         => $source_root,
        wiped_before_restore => true,
    };

    return;
}

sub _cleanup ( $self, $evidence ) {
    my $workspace = delete $evidence->{_workspace};
    return if !has_text($workspace);
    remove_tree($workspace);

    return;
}

sub _inventory ($root) {
    my %files;
    find(
        {
            wanted => sub {
                return if !-f $File::Find::name;
                my $relative = File::Spec->abs2rel( $File::Find::name, $root );
                $relative =~ s{\\}{/}gmsx;
                open my $handle, '<:raw', $File::Find::name
                  or croak "failed to read $File::Find::name: $ERRNO";
                local $INPUT_RECORD_SEPARATOR = undef;
                my $content = <$handle>;
                close $handle
                  or croak "failed to close $File::Find::name: $ERRNO";
                $files{$relative} = sha256_hex($content);
            },
            no_chdir => 1,
        },
        $root
    );

    return \%files;
}

sub _copy_tree ( $from, $to ) {
    make_path($to);
    find(
        {
            wanted => sub {
                my $src = $File::Find::name;
                my $rel = File::Spec->abs2rel( $src, $from );
                return if $rel eq q{.};
                my $dest = path( $to, $rel )->to_string;
                if ( -d $src ) {
                    make_path($dest);
                    return;
                }
                return if !-f $src;
                make_path( path($dest)->dirname->to_string );
                copy( $src, $dest )
                  or croak "failed to copy $src to $dest: $ERRNO";
            },
            no_chdir => 1,
        },
        $from
    );

    return;
}

sub _assert_inventory_size ( $inventory, $expected ) {
    my $count = scalar keys %{$inventory};
    if ( $count != $expected ) {
        GPForum::X::Check->throw(
            message => "expected $expected attachment files, found $count" );
    }

    return;
}

sub _assert_inventories_match ( $expected, $actual, $label ) {
    my @expected_keys = sort keys %{$expected};
    my $expected_list = join "\n", @expected_keys;
    my $actual_list   = join "\n", sort keys %{$actual};
    if ( $expected_list ne $actual_list ) {
        GPForum::X::Check->throw( message => "$label file list mismatch" );
    }
    for my $key (@expected_keys) {
        if ( $expected->{$key} ne $actual->{$key} ) {
            GPForum::X::Check->throw(
                message => "$label digest mismatch for $key" );
        }
    }

    return;
}

sub _assert_empty ($root) {
    my $inventory = _inventory($root);
    if ( keys %{$inventory} ) {
        GPForum::X::Check->throw(
            message => 'source tree was not emptied before restore' );
    }

    return;
}

sub _base_evidence {
    return {
        check         => 'attachment_filesystem',
        status        => undef,
        drill         => 'attachment_filesystem',
        residual_gaps => [ $RESIDUAL_LIVE, $RESIDUAL_BETA ],
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Operations::AttachmentFilesystemDrill - Populated var/attachments backup/restore.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $evidence =
      GPForum::Service::Operations::AttachmentFilesystemDrill->new->run({});

=head1 DESCRIPTION

Creates a throwaway workspace with a populated C<var/attachments> tree via
L<GPForum::Service::Attachment::FilesystemStorage>, copies it to a backup
tree, wipes the source, restores into the same C<var/attachments> path, and
verifies SHA-256 digests and object bytes. Does not mutate a live operator
attachment root and does not claim private-beta readiness.

The C<staging-drill-attachments> command runs it as its attachments phase.
The workspace is a fresh temporary directory, removed when the drill ends.

=head1 SUBROUTINES/METHODS

=head2 run

Takes the command's options, of which it reads none.
Runs the drill and returns its evidence hash reference, finalized by
L<GPForum::Service::Operations::EvidenceMeta/evidence_finalize>:
C<check> and C<drill> (both C<attachment_filesystem>), C<status> (C<pass>
or C<fail>), C<residual_gaps>, C<secrets_redacted> and
C<private_beta_claimed> (0). On a pass, C<attachments> holds the files
counted, the sample object keys, the backup and restore paths and the
flags C<covered>, C<sha256_match> and C<wiped_before_restore>. On a
failure, C<error> holds the message and C<attachments> is absent. It does
not die: a failed step becomes a C<fail> status.

=head1 DIAGNOSTICS

C<run> reports, as C<error>, a step that died. A verification that fails
throws L<GPForum::X::Check>: C<expected 2 attachment
files, found N>, C<backup file list mismatch> or C<restore file list
mismatch>, C<backup digest mismatch for KEY> or C<restore digest mismatch
for KEY>, C<source tree was not emptied before restore>, C<restored object
A content mismatch> (or B), C<failed to read>, C<failed to close> or
C<failed to copy> with the system error, and any error of the attachment
storage.

=head1 CONFIGURATION AND ENVIRONMENT

None read directly. The workspace is created under the system temporary
directory (C<TMPDIR>).

=head1 DEPENDENCIES

L<Const::Fast>, L<Digest::SHA>, L<File::Copy>, L<File::Find>,
L<File::Path>, L<File::Temp>, L<Mojo::Base>,
L<Mojo::File>, L<GPForum::Service::Attachment::FilesystemStorage>,
L<GPForum::Service::Operations::EvidenceHost>,
L<GPForum::Service::Operations::EvidenceMeta>, L<GPForum::X::Check>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

It rehearses the filesystem backend on two sample objects only; live
attachment trees and object storage are outside it, as its residual gaps
say. The layout is always C<var/attachments>.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
