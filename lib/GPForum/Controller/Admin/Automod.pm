# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Admin::Automod;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Admin::Base', -signatures;
use v5.40;

our $VERSION = '0.001';

const my $HTTP_OK          => 200;
const my $HTTP_BAD_REQUEST => 400;
const my $HTTP_CONFLICT    => 409;
const my $PAGE             => 'admin_automod';

# ADR 0133: what each answer of the store says, and with which status.
const my %STATUS => (
    duplicate => $HTTP_CONFLICT,
    invalid   => $HTTP_BAD_REQUEST,
    limit     => $HTTP_CONFLICT,
);
const my %FLASH => (
    word_added   => 'admin.automod_word_added',
    word_removed => 'admin.automod_word_removed',
    links_set    => 'admin.automod_links_set',
    unchanged    => 'admin.automod_unchanged',
    duplicate    => 'admin.automod_duplicate',
    limit        => 'admin.automod_limit',
);
const my %INVALID => map { $_ => "admin.automod_invalid_$_" }
  qw(phrase action replacement link_limit link_trust_below link_action);

# The watched words and the link rule, with the forms that change them.
sub show ($self) {
    my $user_id = $self->authorized_user_id( $self->admin_access->view_action );
    return if !$user_id;

    my ( $words, $rules );
    try {
        my $store = $self->gp_automod_store;
        $words = $store->words;
        $rules = $store->rules_for(undef) // {};
    }
    catch ($error) {
        $self->app->log->error("admin automod failed: $error");
        return $self->system_failure;
    };
    my $automod = $self->gp_automod_store->automod;
    my %page    = (
        words               => [ map { _word_row($_) } @{$words} ],
        link_limit          => $rules->{link_limit},
        link_trust_below    => $rules->{link_trust_below} // 1,
        link_action         => $rules->{link_action}      // 'block',
        actions             => $automod->actions,
        link_actions        => $automod->link_actions,
        maximum_words       => $automod->maximum_words,
        default_replacement => $automod->default_replacement,
    );
    $self->res->headers->cache_control('private, no-store');
    return $self->render( json => \%page, status => $HTTP_OK )
      if $self->_wants_json;

    return $self->render(
        template => 'admin/automod',
        status   => $HTTP_OK,
        %page
    );
}

sub _word_row ($word) {
    return { %{$word}, ui => { id => "word-$word->{word_id}" } };
}

sub add_word ($self) {
    my $user_id = $self->authorized_write_user_id;
    return if !$user_id;

    return $self->_answer(
        'word_added',
        $self->_stored(
            sub {
                return $self->gp_automod_store->add_word(
                    {
                        actor_user_id => $user_id,
                        phrase        => $self->param('phrase'),
                        action        => $self->param('action'),
                        replacement   => $self->param('replacement'),
                    }
                );
            }
        )
    );
}

sub remove_word ($self) {
    my $user_id = $self->authorized_write_user_id;
    return if !$user_id;

    return $self->_answer(
        'word_removed',
        $self->_stored(
            sub {
                return $self->gp_automod_store->remove_word(
                    {
                        actor_user_id => $user_id,
                        word_id       => $self->param('word_id'),
                    }
                );
            }
        )
    );
}

sub set_links ($self) {
    my $user_id = $self->authorized_write_user_id;
    return if !$user_id;

    return $self->_answer(
        'links_set',
        $self->_stored(
            sub {
                return $self->gp_automod_store->set_link_rule(
                    {
                        actor_user_id    => $user_id,
                        link_limit       => $self->param('link_limit'),
                        link_trust_below => $self->param('link_trust_below'),
                        link_action      => $self->param('link_action'),
                    }
                );
            }
        )
    );
}

# The store's answer, or undef when it failed (logged).
sub _stored ( $self, $call ) {
    my $result;
    try {
        $result = $call->();
    }
    catch ($error) {
        $self->app->log->error("admin automod write failed: $error");
        return undef;
    };

    return $result;
}

sub _answer ( $self, $done, $result ) {
    return $self->system_failure if !$result;

    my $status = $result->{status} // 'invalid';
    my $code =
        $result->{ok}           ? $HTTP_OK
      : exists $STATUS{$status} ? $STATUS{$status}
      :                           $HTTP_BAD_REQUEST;
    return $self->render( json => $result, status => $code )
      if $self->_wants_json;

    if ( $result->{ok} ) {
        my $key = $status eq 'unchanged' ? $FLASH{unchanged} : $FLASH{$done};
        $self->flash( success => $self->i18n($key) );
    }
    else {
        my $field = $result->{field} // q{};
        my $key =
            exists $FLASH{$status}  ? $FLASH{$status}
          : exists $INVALID{$field} ? $INVALID{$field}
          :                           $INVALID{phrase};
        $self->flash(
            error => $self->i18n(
                $key,
                { maximum => $self->gp_automod_store->automod->maximum_words }
            )
        );
    }

    return $self->redirect_to($PAGE);
}

1;

__END__

=head1 NAME

GPForum::Controller::Admin::Automod - Watched words and the link rule in the admin console.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/admin/automod')->to('Admin::Automod#show');
    $routes->post('/admin/automod/words')->to('Admin::Automod#add_word');

=head1 DESCRIPTION

The staff side of ADR 0133. The page lists the watched words with the form
that adds one and a way to remove each, and the link rule with its form.
Reading needs the admin console's view permission; every change needs its
manage permission, a CSRF token and the admin write rate limit, and is
audited by the store. Each form answers with a redirect and a notice, or
JSON when asked.

=head1 SUBROUTINES/METHODS

=head2 show

The page (or its JSON).

=head2 add_word

Adds a watched word: phrase, action (block, flag or replace) and an
optional replacement.

=head2 remove_word

Removes the watched word named in the path.

=head2 set_links

Sets the link rule: the most links (empty for none), the trust level below
which it applies, and its action (block or flag).

=head1 DIAGNOSTICS

A failed store call is logged and answered as a system failure.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Controller::Admin::Base>,
L<GPForum::Service::Moderation::AutomodStore>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
