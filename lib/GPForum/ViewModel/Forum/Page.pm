# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::ViewModel::Forum::Page;

use English qw(-no_match_vars);
use Const::Fast;
use Mojo::Base 'GPForum::ViewModel::Forum::Rows', -signatures;
use v5.40;

our $VERSION = '0.001';

# The reactions a post may get, in the order the page shows them (ADR 0145).
const my @REACTIONS => qw(heart laugh celebrate think);

sub categories_page ( $self, %input ) {
    return {
        categories => [ map { $self->category($_) } @{ $input{categories} } ],
    };
}

sub category_page ( $self, %input ) {
    my $items = $self->array_or_empty( $input{threads_page}{items} );

    return {
        category    => $self->category( $input{category} ),
        next_cursor => $input{threads_page}{next_cursor},
        threads => [ map { $self->_category_thread( $_, \%input ) } @{$items} ],
    };
}

# The tag index and a tag's page (ADR 0135).
sub tags_page ( $self, %input ) {
    return {
        tags => [
            map { $self->_tag($_) } @{ $self->array_or_empty( $input{tags} ) }
        ],
    };
}

sub tag_page ( $self, %input ) {
    my $items = $self->array_or_empty( $input{threads} );

    return {
        category => $input{category}
        ? $self->category( $input{category} )
        : undef,
        tag     => $self->_tag( $input{tag} ),
        threads => [ map { $self->_tagged_thread( $_, \%input ) } @{$items} ],
    };
}

sub thread_page ( $self, %input ) {
    my $parts = $self->_thread_page_parts( \%input );

    return {
        %{$parts},
        page_metadata => $self->thread_page_metadata(
            metadata_builder => $input{metadata_builder},
            posts            => $parts->{posts},
            thread           => $parts->{thread},
        ),
    };
}

sub search_page ( $self, %input ) {
    my $results = $self->array_or_empty( $input{results} );

    # ranking_capped: only the candidate_limit newest matches were ranked, so
    # the page says the order is theirs, not the best of every match.
    # degraded is for the template: rendering sets the stash's status to the
    # HTTP code, so the page never saw status 'degraded' and a failed search
    # read as "no results". JSON keeps status as it was.
    return {
        candidate_limit => $input{candidate_limit},
        degraded        => ( $input{status} // q{} ) eq 'degraded' ? 1 : 0,
        filters         => $input{filters}  || {},
        has_more        => $input{has_more} || 0,
        limit           => $input{limit},
        more_limit      => $input{more_limit},
        query           => $self->string( $input{query} ),
        ranking_capped  => $input{ranking_capped} ? 1 : 0,
        results         => [ map { $self->search_result($_) } @{$results} ],
        $self->_optional_status( $input{status} ),
    };
}

sub autocomplete_response ( $self, %input ) {
    my $suggestions = $self->array_or_empty( $input{suggestions} );

    return {
        query       => $self->string( $input{query} ),
        suggestions =>
          [ map { $self->autocomplete_suggestion($_) } @{$suggestions} ],
        $self->_optional_status( $input{status} ),
    };
}

sub report_response ( $self, $report ) {
    return {
        report => $self->report($report),
        status => 'reported',
    };
}

sub created_thread_response ( $self, $stored ) {
    return {
        status    => 'created',
        thread_id => $self->column( $stored->{thread}, 'thread_id' ),
    };
}

sub updated_thread_response ( $self, $stored ) {
    return {
        slug      => $self->column( $stored->{thread}, 'slug' ),
        status    => 'updated',
        thread_id => $self->column( $stored->{thread}, 'thread_id' ),
        title     => $self->column( $stored->{thread}, 'title' ),
    };
}

sub deleted_thread_response ( $self, $stored ) {
    return {
        status    => 'deleted',
        thread_id => $self->column( $stored->{thread}, 'thread_id' ),
    };
}

sub restored_thread_response ( $self, $stored ) {
    return {
        status    => 'restored',
        thread_id => $self->column( $stored->{thread}, 'thread_id' ),
    };
}

sub moved_thread_response ( $self, $stored ) {
    return {
        category_id => $self->column( $stored->{thread}, 'category_id' ),
        status      => 'moved',
        thread_id   => $self->column( $stored->{thread}, 'thread_id' ),
    };
}

sub created_post_response ( $self, $stored ) {
    return {
        post_id => $self->column( $stored->{post}, 'post_id' ),
        status  => 'created',
    };
}

sub updated_post_response ( $self, $stored ) {
    return {
        post_id   => $self->column( $stored->{post}, 'post_id' ),
        status    => 'updated',
        thread_id => $self->column( $stored->{post}, 'thread_id' ),
    };
}

sub deleted_post_response ( $self, $stored ) {
    return {
        post_id   => $self->column( $stored->{post}, 'post_id' ),
        status    => 'deleted',
        thread_id => $self->column( $stored->{post}, 'thread_id' ),
    };
}

sub restored_post_response ( $self, $stored ) {
    return {
        post_id   => $self->column( $stored->{post}, 'post_id' ),
        status    => 'restored',
        thread_id => $self->column( $stored->{post}, 'thread_id' ),
    };
}

sub read_marker_response ( $self, $marked ) {
    return {
        read_state => $marked->{read_state},
        status     => 'ok',
    };
}

sub reading_summary ( $self, %input ) {
    if ( !$self->has_text( $input{user_id} ) ) {
        return { authenticated => 0 };
    }

    return $self->_reading_for_user( \%input );
}

sub _reading_for_user ( $self, $input ) {
    my $summary =
      $input->{read_state}->summary_for_page( $input->{user_id},
        $input->{thread_id}, $input->{posts} || [],
      );
    $summary->{read_command_id} =
      $self->string_or_empty( $input->{read_command_id} );

    return $summary;
}

sub engagement_summary ( $self, %input ) {
    if ( !$self->has_text( $input{user_id} ) ) {
        return { authenticated => 0 };
    }

    return $self->_engagement_for_user( \%input );
}

sub thread_page_metadata ( $self, %input ) {
    if ( !$input{metadata_builder} ) {
        return {};
    }

    return $input{metadata_builder}->thread_metadata( $input{thread},
        { safe_text => $input{posts}[0]{body} || q{}, },
    );
}

sub _thread_page_parts ( $self, $input ) {
    my $page   = $input->{page};
    my $thread = $self->thread( $page->{thread} );
    my $posts  = $self->_thread_page_posts(
        $self->array_or_empty( $page->{posts}{items} ),
        {
            attachments =>
              $self->hash_or_empty( $input->{attachments_by_post} ),
            attachment_delete_command_ids =>
              $self->hash_or_empty( $input->{attachment_delete_command_ids} ),
            attachment_upload_command_ids =>
              $self->hash_or_empty( $input->{attachment_upload_command_ids} ),
            delete_command_ids =>
              $self->hash_or_empty( $input->{delete_command_ids} ),
            edit_command_ids =>
              $self->hash_or_empty( $input->{edit_command_ids} ),
            like_command_ids =>
              $self->hash_or_empty( $input->{like_command_ids} ),
            likes                => $self->hash_or_empty( $input->{likes} ),
            reactions            => $self->hash_or_empty( $input->{reactions} ),
            reaction_command_ids =>
              $self->hash_or_empty( $input->{reaction_command_ids} ),
            reply_targets => $self->hash_or_empty( $input->{reply_targets} ),
            restore_command_ids =>
              $self->hash_or_empty( $input->{restore_command_ids} ),
            report_command_ids =>
              $self->hash_or_empty( $input->{report_command_ids} ),
            listed_members => $self->hash_or_empty( $input->{listed_members} ),
            thread         => $thread,
            viewer_user_id => $input->{viewer_user_id},
        },
    );
    $self->_apply_thread_edit_state( $thread, $input );
    $self->_apply_thread_restore_state( $thread, $input );
    $self->_apply_thread_moderation_state( $thread, $input );
    $self->_apply_thread_tags( $thread, $input );

    return {
        engagement       => $self->_summary_hash( $input->{engagement} ),
        next_cursor      => $page->{posts}{next_cursor},
        posts            => $posts,
        reading          => $self->_summary_hash( $input->{reading} ),
        reply_command_id =>
          $self->string_or_empty( $input->{reply_command_id} ),
        thread => $thread,
    };
}

sub _thread_page_posts ( $self, $post_rows, $context ) {
    my @posts;
    for my $row ( @{$post_rows} ) {
        push @posts, $self->_post_with_attachments( $row, $context );
    }

    return \@posts;
}

sub _post_with_attachments ( $self, $row, $context ) {
    my $post = $self->post($row);
    $post->{attachments} = $self->_attachments_for_post( $post, $context );
    $self->_apply_edit_state( $post, $row, $context );
    $self->_apply_restore_state( $post, $context );
    $self->_apply_report_state( $post, $context );
    $self->_apply_like_state( $post, $context );
    $self->_apply_reaction_state( $post, $context );
    $self->_apply_reply_state( $post, $context );
    $self->_apply_relation_state( $post, $context );

    return $post;
}

# Every reader sees how many liked a post; a signed-in reader who is not
# its author, and while it is not deleted, may like it or take theirs back.
# The post this post answers, when it answers one (ADR 0132).
sub _apply_reply_state ( $self, $post, $context ) {
    my $target = $context->{reply_targets}{ $post->{post_id} };
    return if ref $target ne 'HASH';
    $post->{reply_to} = {
        author_username => $target->{author_username},
        position        => $target->{position},
        post_id         => $target->{post_id},
    };
    return;
}

# The four reactions on a post (ADR 0145), each with its count, whether the
# viewer gave it, and the command id of the viewer's form; a reader who
# may like may react.
sub _apply_reaction_state ( $self, $post, $context ) {
    my $given = $context->{reactions}{ $post->{post_id} }            || {};
    my $ids   = $context->{reaction_command_ids}{ $post->{post_id} } || {};
    $post->{reactions} = [
        map {
            +{
                command_id => $self->string_or_empty( $ids->{$_} ),
                count      => $given->{$_}{count} || 0,
                reacted    => $given->{$_}{reacted} ? 1 : 0,
                reaction   => $_,
            }
        } @REACTIONS
    ];
    $post->{can_react} = $post->{can_like} ? 1 : 0;

    return;
}

sub _apply_like_state ( $self, $post, $context ) {
    my $likes = $context->{likes}{ $post->{post_id} } || {};
    $post->{like_count} = $likes->{like_count} || 0;
    $post->{liked}      = $likes->{liked} ? 1 : 0;
    my $viewer = $context->{viewer_user_id};
    $post->{can_like} =
         $self->has_text($viewer)
      && !$self->has_text( $post->{deleted_at} )
      && ( $post->{author_user_id} // q{} ) ne $viewer ? 1 : 0;
    $post->{like_command_id} =
      $self->string_or_empty(
        $context->{like_command_ids}{ $post->{post_id} } );

    return;
}

# ADR 0130: a post by a member the reader ignores or blocks is collapsed
# behind a control that shows it.
sub _apply_relation_state ( $self, $post, $context ) {
    my $author = $post->{author_user_id} // q{};
    return if !length $author;
    return if $author eq ( $context->{viewer_user_id} // q{} );
    if ( $context->{listed_members}{$author} ) {
        $post->{ignored} = 1;
    }

    return;
}

sub _category_thread ( $self, $row, $input ) {
    my $thread = $self->thread($row);
    $self->_apply_thread_restore_state( $thread, $input );
    $self->_apply_thread_tags( $thread, $input );

    return $thread;
}

sub _tagged_thread ( $self, $row, $input ) {
    my $thread = $self->thread($row);
    $self->_apply_thread_tags( $thread, $input );

    return $thread;
}

# The thread's tags (ADR 0135), from the page's read of them by thread id;
# none is an empty list, so every row has the key.
sub _apply_thread_tags ( $self, $thread, $input ) {
    my $tags = $self->hash_or_empty( $input->{thread_tags} );
    $thread->{tags} =
      [ map { $self->_tag($_) }
          @{ $self->array_or_empty( $tags->{ $thread->{thread_id} // q{} } ) }
      ];

    return;
}

sub _tag ( $self, $tag ) {
    my $hash = $self->hash_or_empty($tag);

    return {
        name => $self->string_or_empty( $hash->{name} ),
        slug => $self->string_or_empty( $hash->{slug} ),
        (
            exists $hash->{thread_count}
            ? ( thread_count => $hash->{thread_count} )
            : ()
        ),
    };
}

sub _apply_thread_restore_state ( $self, $thread, $input ) {
    return if !$self->_thread_is_restorable( $thread, $input );

    $thread->{can_restore_thread} = 1;
    $thread->{restore_thread_command_id} =
      $self->_restore_thread_command_id( $thread, $input );

    return;
}

sub _restore_thread_command_id ( $self, $thread, $input ) {
    my $ids = $self->hash_or_empty( $input->{restore_thread_command_ids} );

    return $self->string_or_empty( $ids->{ $thread->{thread_id} }
          || $input->{restore_thread_command_id} );
}

sub _apply_thread_edit_state ( $self, $thread, $input ) {
    if ( !$self->_thread_is_editable( $thread, $input ) ) {
        return;
    }

    $thread->{can_edit_thread}   = 1;
    $thread->{can_delete_thread} = 1;
    $thread->{can_move_thread}   = 1;
    $thread->{edit_thread_command_id} =
      $self->string_or_empty( $input->{edit_thread_command_id} );
    $thread->{delete_thread_command_id} =
      $self->string_or_empty( $input->{delete_thread_command_id} );
    $thread->{move_thread_command_id} =
      $self->string_or_empty( $input->{move_thread_command_id} );
    $thread->{move_categories} = $self->_move_categories($input);

    return;
}

# A reader who moderates threads gets the staff actions in the thread's
# tools, each form with a command id of its own, so one sent twice is one
# action and two different ones are two. A deleted thread offers none: its
# author's restore is what is left to do with it.
sub _apply_thread_moderation_state ( $self, $thread, $input ) {
    return if !$input->{can_moderate_thread};
    return if $self->has_text( $thread->{deleted_at} );
    $thread->{can_moderate_thread} = 1;
    my $ids = $self->hash_or_empty( $input->{moderation_command_ids} );
    $thread->{moderation_command_ids} =
      { map { $_ => $self->string_or_empty( $ids->{$_} ) } qw(hide lock pin) };
    return;
}

sub _thread_is_editable ( $self, $thread, $input ) {
    return 0 if $self->has_text( $thread->{deleted_at} );

    return $self->_author_thread_write( $thread, $input );
}

sub _thread_is_restorable ( $self, $thread, $input ) {
    return 0 if !$self->has_text( $thread->{deleted_at} );

    return $self->_author_thread_write( $thread, $input );
}

sub _author_thread_write ( $self, $thread, $input ) {
    my $viewer = $input->{viewer_user_id};
    if ( !$self->has_text($viewer) ) {
        return 0;
    }
    if ( $thread->{locked_at} ) {
        return 0;
    }

    my $author = $thread->{author_user_id} || q{};

    return $author eq $viewer ? 1 : 0;
}

sub _move_categories ( $self, $input ) {
    my $categories = $self->array_or_empty( $input->{categories} );

    return [ map { $self->category($_) } @{$categories} ];
}

sub _apply_report_state ( $self, $post, $context ) {
    $post->{report_command_id} =
      $self->string_or_empty(
        $context->{report_command_ids}{ $post->{post_id} } );

    return;
}

sub _apply_edit_state ( $self, $post, $row, $context ) {
    return if !$self->_post_is_editable( $post, $context );

    $post->{body_source} = $self->_edit_body_source($row);
    $post->{can_edit}    = 1;
    $post->{can_delete}  = 1;
    $post->{delete_command_id} =
      $self->string_or_empty(
        $context->{delete_command_ids}{ $post->{post_id} } );
    $post->{edit_command_id} =
      $self->string_or_empty(
        $context->{edit_command_ids}{ $post->{post_id} } );
    $post->{upload_command_id} =
      $self->string_or_empty(
        $context->{attachment_upload_command_ids}{ $post->{post_id} } );

    return;
}

sub _attachments_for_post ( $self, $post, $context ) {
    my $rows = $context->{attachments}{ $post->{post_id} } || [];
    my @attachments;
    for my $row ( @{$rows} ) {
        push @attachments, $self->_attachment_with_command( $row, $context );
    }

    return \@attachments;
}

sub _attachment_with_command ( $self, $row, $context ) {
    my %attachment = %{$row};
    $attachment{delete_command_id} = $self->string_or_empty(
        $context->{attachment_delete_command_ids}{ $attachment{attachment_id} }
    );

    return \%attachment;
}

sub _apply_restore_state ( $self, $post, $context ) {
    return if !$self->_post_is_restorable( $post, $context );

    $post->{can_restore} = 1;
    $post->{restore_command_id} =
      $self->string_or_empty(
        $context->{restore_command_ids}{ $post->{post_id} } );

    return;
}

sub _edit_body_source ( $self, $row ) {
    my $source = $self->_body_source($row);
    if ( $self->has_text($source) ) {
        return $source;
    }

    return $self->string_or_empty( $self->column( $row, 'body' ) );
}

sub _post_is_editable ( $self, $post, $context ) {
    return 0 if !$self->_author_write_context($context);
    return 0 if $self->has_text( $post->{deleted_at} );

    return $self->_same_viewer( $post, $context );
}

sub _post_is_restorable ( $self, $post, $context ) {
    return 0 if !$self->_author_write_context($context);
    return 0 if !$self->has_text( $post->{deleted_at} );

    return $self->_same_viewer( $post, $context );
}

sub _author_write_context ( $self, $context ) {
    return 0 if !$self->has_text( $context->{viewer_user_id} );
    return 0 if $context->{thread}{locked_at};

    return 1;
}

sub _same_viewer ( $self, $post, $context ) {
    my $author = $post->{author_user_id} || q{};

    return $author eq ( $context->{viewer_user_id} || q{} ) ? 1 : 0;
}

sub _summary_hash ( $, $value ) {
    if ( ref $value eq 'HASH' ) {
        return $value;
    }

    return { authenticated => 0 };
}

sub _optional_status ( $, $status ) {
    if ( defined $status ) {
        return ( status => $status );
    }

    return;
}

sub _engagement_for_user ( $self, $input ) {
    my $summary = eval { return $self->_engagement_lookup($input); };
    if ($EVAL_ERROR) {
        $self->_warn_engagement( $input, $EVAL_ERROR );
        return $self->_degraded_engagement;
    }

    return $summary;
}

sub _engagement_lookup ( $self, $input ) {
    my $thread_id = $self->column( $input->{thread}, 'thread_id' );

    return {
        authenticated => 1,
        bookmark      => $input->{bookmark_store}
          ->status_for_user_target( $input->{user_id}, 'thread', $thread_id ),
        bookmark_command_id =>
          $self->string_or_empty( $input->{bookmark_command_id} ),
        bookmark_remove_command_id =>
          $self->string_or_empty( $input->{bookmark_remove_command_id} ),
        mute_command_id => $self->string_or_empty( $input->{mute_command_id} ),
        subscribe_command_id =>
          $self->string_or_empty( $input->{subscribe_command_id} ),
        subscription => $input->{subscription_store}
          ->status_for_user_target( $input->{user_id}, 'thread', $thread_id ),
        thread_report_command_id =>
          $self->string_or_empty( $input->{thread_report_command_id} ),
        unsubscribe_command_id =>
          $self->string_or_empty( $input->{unsubscribe_command_id} ),
    };
}

sub _warn_engagement ( $, $input, $error ) {
    if ( $input->{logger} ) {
        $input->{logger}->warn("engagement summary degraded: $error");
    }

    return;
}

sub _degraded_engagement {
    return {
        authenticated => 1,
        bookmark      => { bookmarked => 0 },
        status        => 'degraded',
        subscription  => { muted => 0, subscribed => 0 },
    };
}

1;

__END__

=head1 NAME

GPForum::ViewModel::Forum::Page - Forum page view models.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $page = $pages->thread_page(%input);

=head1 DESCRIPTION

Assembles category, thread, search, and mutation page payloads from row
view models. New-thread form state stays on
L<GPForum::ViewModel::Forum::Form>.
L<GPForum::ViewModel::Forum::Presenter> remains the public facade.

=head1 SUBROUTINES/METHODS

=head2 categories_page

Returns the category index payload.

=head2 category_page

Returns a category thread-list payload.

=head2 thread_page

Returns a thread page with posts, attachments, and metadata.

=head2 search_page

Returns a search results payload, with C<ranking_capped> true when only the
newest C<candidate_limit> matches were ranked.

=head2 autocomplete_response

Returns autocomplete suggestions.

=head2 report_response

Returns a created-report payload.

=head2 created_thread_response

Returns a created-thread mutation payload.

=head2 updated_thread_response

Returns an updated-thread mutation payload.

=head2 deleted_thread_response

Returns a deleted-thread mutation payload.

=head2 restored_thread_response

Returns a restored-thread mutation payload.

=head2 moved_thread_response

Returns a moved-thread mutation payload.

=head2 created_post_response

Returns a created-post mutation payload.

=head2 updated_post_response

Returns an updated-post mutation payload.

=head2 deleted_post_response

Returns a deleted-post mutation payload.

=head2 read_marker_response

Returns a read-marker mutation payload.

=head2 reading_summary

Returns anonymous or per-user reading state.

=head2 engagement_summary

Returns bookmark and subscription state, or a degraded payload.

=head2 thread_page_metadata

Delegates document metadata when a builder is supplied.

=head1 DIAGNOSTICS

Engagement lookup failures log a warning when a logger is present and return
a degraded authenticated payload.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Uses L<GPForum::ViewModel::Forum::Rows>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Attachment lists are keyed by post id from the store, not loaded here.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
