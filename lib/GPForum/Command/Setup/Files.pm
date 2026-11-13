# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Command::Setup::Files;

use Const::Fast;
use Mojo::Base 'GPForum::Command::Setup::Answers', -signatures;
use v5.40;

use English    qw(-no_match_vars);
use Mojo::File qw(path);
use Mojo::Util qw(decode encode trim);
use GPForum::Command::Support::ServiceEnvironment;
use GPForum::Command::Usage;
use GPForum::Service::Operations::Host;
use GPForum::X::Io;

our $VERSION = '0.001';

const my $EDIT           => 'GPForum::Command::Support::EnvironmentFileEdit';
const my $FILE_MODE      => oct '640';
const my $DIRECTORY_MODE => oct '755';
const my $MODE_BITS      => oct '777';
const my $OTHERS_BITS    => oct '007';
const my $STAT_MODE      => 2;
const my $STAT_UID       => 4;
const my $STAT_GID       => 5;

# What setup would do, said and not done.
sub dry_run ( $self, $options, $state, $plan, $database, $lines, $findings ) {
    if ( $state->{deployed} && $self->is_root && !$self->account->ids ) {
        my @commands = @{ $self->account->commands( $self->root ) };
        $findings->add(
            name    => 'account',
            status  => @commands ? 'ok' : 'degraded',
            message => @commands
            ? [
                'setup.would_account',
                {
                    user    => $self->account->name,
                    command => join( q{ }, @{ $commands[0] } ),
                }
              ]
            : [ 'setup.account_missing', { user => $self->account->name } ],
        );
    }
    my $file = $self->_file_message( $state, $lines, 'would_' );
    $findings->add(
        name    => 'file',
        status  => 'ok',
        message => [
            $file->[0],
            {
                %{ $file->[1] },
                $state->{exists} ? _shape( $state->{file} ) : ()
            }
        ],
    );
    $self->_say_sender( $state, $findings );

    # In the order a run does them: the file, then the link.
    my $link = $self->_link_wanted;
    if ( $link && !$link->{other} ) {
        $findings->add(
            name    => 'command',
            status  => 'ok',
            message => [ 'setup.would_link', $link ],
        );
    }
    $findings->add(
        name => 'database',
        %{ $self->would_database( $state, $plan, $database ) },
    );
    $findings->add(
        name    => 'schema',
        status  => 'ok',
        message => ['setup.would_migrate'],
    );

    return $self->print_report( $options, $state, $findings, {},
        $self->said_text('setup.dry_run') );
}

# The account the services run as, and the directory its uploads go in: made
# by root on a deployed host. Returns whether setup goes on.
sub ensure_account ( $self, $state, $lines, $findings, $changed ) {
    return 1 if !$state->{deployed};

    my $account = $self->account;
    my $user    = $account->name;
    if ( !$self->is_root ) {
        $findings->add(
            name    => 'account',
            status  => 'degraded',
            message =>
              [ 'setup.not_root', { file => $state->{file}, user => $user } ],
            fixes => ['sudo gpforum setup'],
        );
        return 1;
    }

    my $made = 0;
    if ( !$account->ids ) {
        my @commands = @{ $account->commands( $self->root ) };
        if ( !@commands ) {
            $findings->add(
                name    => 'account',
                status  => 'degraded',
                message => [ 'setup.account_missing', { user => $user } ],
                fixes   => [
                    $self->said_text('setup.account_by_hand'),
                    $self->said_text(
                        'setup.run_again', { command => 'sudo gpforum setup' }
                    ),
                ],
            );
            return 1;
        }
        my $failed = $account->make( $self->root );
        if ($failed) {
            $findings->add(
                name    => 'account',
                status  => 'fail',
                message => [
                    'setup.account_failed',
                    { user => $user, reason => $failed->{reason} }
                ],
                fixes => ["sudo $failed->{command}"],
            );
            return 0;
        }
        $made = 1;
        $changed->{account} = 1;
    }

    my $uploads = $self->_uploads($lines);
    my $directories;
    try {
        $directories = $account->make_directory($uploads);
    }
    catch ($error) {
        $findings->add(
            name    => 'account',
            status  => 'fail',
            message => [
                'setup.uploads_failed',
                {
                    directory => $uploads,
                    reason    => GPForum::Command::Usage->trimmed($error)
                }
            ],
        );
        return 0;
    };
    if ( @{$directories} ) {
        $changed->{uploads} = 1;
    }
    $findings->add(
        name    => 'account',
        status  => 'ok',
        message => [
            $made ? 'setup.account_made' : 'setup.account_present',
            { user => $user, directory => $uploads }
        ],
    );

    return 1;
}

# The ln that makes the link, as an operator types it.
sub _linking ( $flags, $link ) {
    return join q{ }, q{sudo ln}, $flags,
      map { GPForum::Service::Operations::Host->shell_word($_) }
      @{$link}{qw(target link)};
}

# gpforum on root's PATH, as a link to this checkout's bin/gpforum, which
# finds its own code and dependencies from anywhere: the step the guides had
# the operator type before setup. A gpforum already there is left alone --
# one that is this checkout's says nothing, another is said, with the
# command that replaces it. Returns 1: setup goes on either way.
sub ensure_link ( $self, $findings, $changed ) {
    my $link = $self->_link_wanted;
    return 1 if !$link;

    if ( $link->{other} ) {
        $findings->add(
            name    => 'command',
            status  => 'degraded',
            message => [ 'setup.link_other', $link ],
            fixes   => [ _linking( q{-sf}, $link ) ],
        );
        return 1;
    }

    try {
        path( $link->{directory} )->make_path( { mode => $DIRECTORY_MODE } );
        symlink $link->{target}, $link->{link}
          or GPForum::X::Io->throw( message => "symlink: $OS_ERROR" );
        $changed->{link} = 1;
        $findings->add(
            name    => 'command',
            status  => 'ok',
            message => [ 'setup.link_made', $link ],
        );
    }
    catch ($error) {
        $findings->add(
            name    => 'command',
            status  => 'degraded',
            message => [
                'setup.link_failed',
                {
                    %{$link}, reason => GPForum::Command::Usage->trimmed($error)
                }
            ],
            fixes => [ _linking( q{-s}, $link ) ],
        );
    };

    return 1;
}

# The link setup would make -- { directory, link, target, other } -- or
# undef when there is nothing to make: no place to make it, no bin/gpforum
# in this checkout, or a link to it already there.
sub _link_wanted ($self) {
    my $directory = $self->links_into;
    return undef if !defined $directory;

    my $target = $self->root->child( 'bin', 'gpforum' );
    return undef if !-x $target;
    $target = $target->realpath->to_string;

    my $link = path( $directory, 'gpforum' );
    my %wanted =
      ( directory => $directory, link => "$link", target => $target );
    return \%wanted if !-e $link && !-l $link;

    my $there = -e $link ? $link->realpath->to_string : q{};
    return undef if $there eq $target;

    return { %wanted, other => 1 };
}

# Where the uploads go: the attachment root the file will hold, the code
# directory's var/attachments by default.
sub _uploads ( $self, $lines ) {
    my $root = $EDIT->values_of($lines)->{GPFORUM_ATTACHMENT_ROOT};
    if ( !defined $root || !length $root ) {
        $root = 'var/attachments';
    }

    return path($root)->is_abs ? $root : $self->root->child($root)->to_string;
}

# The environment file: written when it changed, given to the services'
# group when root runs this. Returns whether setup goes on.
sub write_file ( $self, $state, $lines, $findings, $changed ) {
    my $file    = $state->{file};
    my $text    = join q{}, @{$lines};
    my $same    = $state->{exists} && $text eq join q{}, @{ $state->{lines} };
    my %owner   = $self->_ownership($state);
    my $message = $self->_file_message( $state, $lines, q{} );

    try {
        if ( !$same ) {
            _make_parent($file);
            $EDIT->replace(
                $file,
                encode( 'UTF-8', $text ),
                $state->{exists} ? () : %owner
            );
            $changed->{file} = 1;
        }
        my @stat = stat $file;
        if (   $state->{exists}
            && $state->{deployed}
            && defined $owner{gid}
            && $owner{gid} != $stat[$STAT_GID] )
        {
            chown $stat[$STAT_UID], $owner{gid}, $file
              or GPForum::X::Io->throw( message => "chown: $OS_ERROR" );
            $changed->{file} = 1;
            $message = [ 'setup.file_given', $message->[1] ];
        }
    }
    catch ($error) {
        $findings->add(
            name    => 'file',
            status  => 'fail',
            message => [
                'setup.cannot_write',
                {
                    file   => $file,
                    reason => GPForum::Command::Usage->trimmed($error)
                }
            ],
            fixes => [ 'sudo gpforum setup', ['setup.another_file'] ],
        );
        return 0;
    };

    $findings->add(
        name    => 'file',
        status  => 'ok',
        message => [ $message->[0], { %{ $message->[1] }, _shape($file) } ],
    );
    $self->_say_sender( $state, $findings );
    $self->_say_if_open( $file, $findings );

    return 1;
}

# A sender that followed the address, said: one setup derived, at the old
# host, kept mail going out from the old domain.
sub _say_sender ( $self, $state, $findings ) {
    my $followed = $state->{sender_followed};
    return if !$followed;

    $findings->add(
        name    => 'file',
        status  => 'ok',
        message => [ 'setup.sender_follows', $followed ],
    );

    return;
}

# Who the file belongs to when setup makes it: on a deployed host run as
# root, root and the services' group; in development run through sudo, the
# developer who ran it; otherwise whoever runs setup.
sub _ownership ( $self, $state ) {
    my %owner = ( mode => $FILE_MODE );
    return %owner if !$self->is_root;

    # Root's: this process's own, which root runs it as.
    if ( $state->{deployed} ) {
        my $group = $self->account->group_id;
        return (
            %owner,
            uid => $EFFECTIVE_USER_ID,
            defined $group ? ( gid => $group ) : ()
        );
    }
    return %owner if !defined $ENV{SUDO_UID};

    return ( %owner, uid => $ENV{SUDO_UID}, gid => $ENV{SUDO_GID} // 0 );
}

sub _make_parent ($file) {
    my $directory = path($file)->dirname;
    return if -d $directory;

    $directory->make_path( { mode => $DIRECTORY_MODE } );

    return;
}

# The file's line: written whole, with what it holds new; or the settings
# it set; or as it was.
sub _file_message ( $self, $state, $lines, $would ) {
    my %parameters = ( file => $state->{file} );
    if ( !$state->{exists} ) {
        return [ "setup.${would}file_new", \%parameters ];
    }

    my $before = $state->{values};
    my $after  = $EDIT->values_of($lines);
    my @names  = grep { ( $before->{$_} // q{} ) ne ( $after->{$_} // q{} ) }
      sort keys %{$after};
    return [ 'setup.file_same', \%parameters ] if !@names;

    return [
        "setup.${would}file_changed",
        { %parameters, names => join q{, }, @names }
    ];
}

# Its mode, owner and group, as ls shows them.
sub _shape ($file) {
    my @stat  = stat $file;
    my $owner = getpwuid $stat[$STAT_UID];
    my $group = getgrgid $stat[$STAT_GID];

    return (
        mode  => sprintf( '%04o', $stat[$STAT_MODE] & $MODE_BITS ),
        owner => $owner // $stat[$STAT_UID],
        group => $group // $stat[$STAT_GID],
    );
}

# A file every account on the host may read, said with the chmod that
# closes it; setup leaves the operator's mode as it is.
sub _say_if_open ( $self, $file, $findings ) {
    my $mode = ( stat $file )[$STAT_MODE];
    return if !defined $mode || !( $mode & $OTHERS_BITS );

    $findings->add(
        name    => 'file',
        status  => 'degraded',
        message => [
            'cli.secret.world_readable',
            {
                file    => $file,
                command =>
                  GPForum::Service::Operations::Host->closing_chmod($file),
            }
        ],
    );

    return;
}

# The settings the file now holds, for the steps that read them: the file
# wins over the shell here, since it is what the service will read.
sub load_environment ( $self, $state ) {
    my $environment =
      GPForum::Command::Support::ServiceEnvironment->new(
        file => $state->{file} );
    delete @ENV{ map { $_->[0] }
          @{ $environment->read_file( $state->{file} ) } };
    $environment->load;

    return;
}

1;

__END__

=head1 NAME

GPForum::Command::Setup::Files - The service account, the environment file and the link.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Part of GPForum::Command::Setup; callers use that class.

=head1 DESCRIPTION

Planning and making the service account, the link to the gpforum command and the environment file, and printing a dry run of all of it.

GPForum::Command::Setup inherits it, so the object a caller builds has every method; this
file holds one part of that class so each part can be read by itself.

=head1 SUBROUTINES/METHODS

=head2 dry_run

A step the parts of GPForum::Command::Setup share.

=head2 ensure_account

A step the parts of GPForum::Command::Setup share.

=head2 ensure_link

A step the parts of GPForum::Command::Setup share.

=head2 write_file

A step the parts of GPForum::Command::Setup share.

=head2 load_environment

A step the parts of GPForum::Command::Setup share.

=head1 DIAGNOSTICS

As GPForum::Command::Setup.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

As GPForum::Command::Setup.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
