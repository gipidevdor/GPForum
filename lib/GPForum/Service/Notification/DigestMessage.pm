# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::DigestMessage;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use Mojo::Util qw(xml_escape);

use GPForum::Infrastructure::Id;
use GPForum::Service::I18N;

our $VERSION = '0.001';

const my %IS_FREQUENCY => map { $_ => 1 } qw(daily weekly);

# The mail's own few styles, inline as mail clients need them: the forum's
# text and muted colours, its system font stack, a readable measure.
const my $BODY_STYLE => 'margin:0 auto;max-width:40em;padding:16px;'
  . 'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,'
  . 'Helvetica,Arial,sans-serif;font-size:16px;line-height:1.5;'
  . 'color:#1f2328;background:#ffffff';
const my $HEADING_STYLE => 'font-size:20px;line-height:1.3;margin:0 0 8px';
const my $LIST_STYLE    => 'list-style:none;margin:16px 0;padding:0';
const my $ITEM_STYLE    => 'margin:0 0 12px';
const my $LINK_STYLE    => 'color:#0b57d0;font-weight:600';
const my $MUTED_STYLE   => 'color:#59636e;font-size:14px';
const my $FOOTER_STYLE =>
  'border-top:1px solid #d1d9e0;margin-top:24px;padding-top:12px;'
  . 'color:#59636e;font-size:13px';

has i18n => sub { return GPForum::Service::I18N->new; };

# ADR 0078: the digest's subject, plain text and HTML, in the member's
# language, from what the scheduled job recorded: the threads, latest
# first, each with its category and how many posts are new, and how many
# more there were than it names. Every link is absolute, under base_url.
sub compose ( $self, $input ) {
    my $locale = $input->{locale} || 'en';
    my $frequency =
        $IS_FREQUENCY{ $input->{frequency} // q{} }
      ? $input->{frequency}
      : 'daily';
    my $base = $input->{base_url} // q{};
    $base =~ s{ / \z}{}msx;
    my @items = map { $self->_item( $locale, $base, $_ ) }
      grep {
        ref $_ eq 'HASH'
          && GPForum::Infrastructure::Id->is_uuid_spelling( $_->{thread_id} )
      } @{ $input->{items} || [] };
    my $more = ( $input->{thread_total} // 0 ) - @items;
    my %text = (
        subject =>
          $self->_t( $locale, "notifications.digest.subject.$frequency" ),
        intro => $self->_t( $locale, "notifications.digest.intro.$frequency" ),
        more  => $more > 0
        ? $self->i18n->translate_count( $locale, 'notifications.digest.more',
            $more )
        : undef,
        settings_url    => "$base/settings",
        unsubscribe_url => $input->{unsubscribe_url} // q{},
    );

    return {
        subject => $text{subject},
        text    => $self->_text( $locale, \%text, \@items ),
        html    => $self->_html( $locale, \%text, \@items ),
    };
}

sub _item ( $self, $locale, $base, $item ) {
    return {
        url      => "$base/t/$item->{thread_id}",
        title    => $item->{title}          // q{},
        category => $item->{category_title} // q{},
        posts    => $self->i18n->translate_count(
            $locale, 'notifications.digest.new_posts',
            $item->{new_posts} // 0
        ),
    };
}

sub _text ( $self, $locale, $text, $items ) {
    my @lines = ( $text->{intro}, q{} );
    for my $item ( @{$items} ) {
        push @lines,
          q{- }
          . $self->_t(
            $locale,
            'notifications.digest.item',
            {
                title    => $item->{title},
                category => $item->{category},
                posts    => $item->{posts},
            }
          ),
          q{  } . $item->{url}, q{};
    }
    if ( defined $text->{more} ) {
        push @lines, $text->{more}, q{};
    }
    push @lines, q{--},
      $self->_t(
        $locale,
        'notifications.digest.footer',
        {
            settings_url    => $text->{settings_url},
            unsubscribe_url => $text->{unsubscribe_url},
        }
      );

    return join( "\n", @lines ) . "\n";
}

sub _html ( $self, $locale, $text, $items ) {
    my @list = map { $self->_html_item( $locale, $_ ) } @{$items};
    my $more =
      defined $text->{more}
      ? '<p>' . xml_escape( $text->{more} ) . '</p>'
      : q{};
    my $footer = sprintf '<p%s><a href="%s">%s</a> &middot; '
      . '<a href="%s">%s</a></p>',
      _style($FOOTER_STYLE), xml_escape( $text->{settings_url} ),
      xml_escape( $self->_t( $locale, 'notifications.digest.settings_link' ) ),
      xml_escape( $text->{unsubscribe_url} ),
      xml_escape(
        $self->_t( $locale, 'notifications.digest.unsubscribe_link' ) );

    return join q{},
      '<!DOCTYPE html><html lang="', xml_escape($locale), '">',
      '<head><meta charset="utf-8">',
      '<meta name="viewport" content="width=device-width, initial-scale=1">',
      '<title>', xml_escape( $text->{subject} ), '</title></head>',
      '<body',   _style($BODY_STYLE),    '>',
      '<h1',     _style($HEADING_STYLE), '>', xml_escape( $text->{subject} ),
      '</h1>',
      '<p>', xml_escape( $text->{intro} ), '</p>',
      '<ul', _style($LIST_STYLE), '>', @list, '</ul>',
      $more, $footer, '</body></html>', "\n";
}

sub _html_item ( $self, $locale, $item ) {
    my $meta = $self->_t(
        $locale,
        'notifications.digest.item_meta',
        { category => $item->{category}, posts => $item->{posts} }
    );

    return sprintf '<li%s><a href="%s"%s>%s</a><br><span%s>%s</span></li>',
      _style($ITEM_STYLE), xml_escape( $item->{url} ), _style($LINK_STYLE),
      xml_escape( $item->{title} ), _style($MUTED_STYLE), xml_escape($meta);
}

# An inline style attribute, escaped: a style may quote a font name.
sub _style ($style) {
    return sprintf ' style="%s"', xml_escape($style);
}

sub _t ( $self, $locale, $key, $variables = undef ) {
    return $self->i18n->translate( $locale, $key, $variables );
}

1;

__END__

=head1 NAME

GPForum::Service::Notification::DigestMessage - The words and markup of the email digest.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $message = GPForum::Service::Notification::DigestMessage->new(
        i18n => $i18n )->compose(
        {
            locale          => 'it',
            frequency       => 'daily',
            items           => \@threads,
            thread_total    => 25,
            base_url        => 'https://forum.example',
            unsubscribe_url => $link,
        }
    );    # { subject, text, html }

=head1 DESCRIPTION

ADR 0078. Says the daily or weekly digest in the member's language: a
subject, an introduction naming the period, each thread (latest first) as
a link with its category and how many new posts it has, a line for the
threads beyond those named, and a footer linking the notification settings
and the signed link that stops the digest. The plain-text and HTML parts
say the same; the HTML escapes every value and styles itself inline, as
mail clients need. A thread whose id is not a uuid is left out.

=head1 SUBROUTINES/METHODS

=head2 compose

Takes C<locale>, C<frequency> (C<daily> or C<weekly>; anything else reads
as daily), C<items> (C<thread_id>, C<title>, C<category_title>,
C<new_posts>), C<thread_total>, C<base_url> and C<unsubscribe_url>.
Returns C<< { subject, text, html } >>.

=head1 DIAGNOSTICS

None: a missing message reads as its key, as L<GPForum::Service::I18N> does.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Const::Fast>, L<Mojo::Base>, L<Mojo::Util>,
L<GPForum::Infrastructure::Id> and L<GPForum::Service::I18N>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The mail's colours are fixed: a mail client's dark mode adapts them, or
not, as it does any mail.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
