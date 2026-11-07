# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::LegalAccess;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use Time::Piece qw(gmtime);

use GPForum::Web::Responder;

our $VERSION = '0.001';

const my $HTTP_OK      => 200;
const my $TEMPLATE     => 'legal/page';
const my $ROBOTS       => 'index,follow';
const my $EXPIRES_DAYS => 180;
const my $DAY_SECONDS  => 86_400;
const my $HOUR_SECONDS => 3_600;

# Each page follows the text that says what it must hold, named on the page
# by its basis key:
#
#   terms    Regulation (EU) 2022/2065 (Digital Services Act), arts. 14 to
#            17 and 20: restrictions, moderation and its tools, notices,
#            statements of reasons, complaints;
#   privacy  Regulation (EU) 2016/679 (GDPR), art. 13, in its order;
#   cookies  Directive 2002/58/EC art. 5(3), D.Lgs. 196/2003 art. 122 and
#            the Garante's guidelines of 10 June 2021: technical cookies
#            only, each named with its purpose and duration;
#   notice   D.Lgs. 70/2003 art. 7 (Directive 2000/31/EC art. 5) and the
#            Digital Services Act's points of contact, arts. 11 and 12.
#
# A section is [ name, paragraphs, extras ]: its title is
# legal.PAGE.NAME.title and its paragraphs legal.PAGE.NAME.1 onwards; fields
# are the operator's facts it lists (see _fact), links the pages it points
# to (legal.PAGE.NAME.link.ROUTE), table the cookie list.
# Fields the law asks for only when they exist: a VAT number and a trade
# register for a forum run as a business (D.Lgs. 70/2003 art. 7(1)(d), (e)),
# a data protection officer when one is designated (GDPR art. 13(1)(b)).
# Left empty, they are left out; any other field says it is not given.
const my %WHEN_GIVEN => map { $_ => 1 } qw(vat_number register privacy_officer);

const my %PAGES => (
    terms => [
        [
            provider => 1,
            fields   => [qw(name email)],
            links    => ['legal_notice']
        ],
        [ accounts   => 2 ],
        [ conduct    => 2 ],
        [ moderation => 3 ],
        [ automated  => 2 ],
        [ notices    => 2 ],
        [ reasons    => 2 ],
        [ complaints => 2 ],
        [ changes    => 1 ],
    ],
    privacy => [
        [
            controller => 1,
            fields     => [qw(name address email privacy_officer)]
        ],
        [ data       => 4 ],
        [ purposes   => 4 ],
        [ recipients => 2 ],
        [ transfers  => 1 ],
        [ retention  => 4 ],
        [ rights     => 3, links => ['privacy_dashboard'] ],
        [ complaint  => 1 ],
        [ provision  => 1 ],
        [ automated  => 1 ],
    ],
    cookies =>
      [ [ kinds => 2 ], [ list => 0, table => 'cookies' ], [ manage => 1 ], ],
    notice => [
        [
            provider => 1,
            fields   => [qw(name address email vat_number register)]
        ],
        [ contact  => 2, fields => [qw(email languages)] ],
        [ security => 1, fields => [qw(security_txt)] ],
    ],
);

sub known_page ( $, $page ) {
    if ( !defined $page ) {
        return 0;
    }

    return exists $PAGES{$page} ? 1 : 0;
}

sub template {
    return $TEMPLATE;
}

# The page's sections with the operator's facts in them. $facts holds the
# operator settings by field name (name, address, email, vat_number,
# register, privacy_officer), the languages contact is answered in, the
# security.txt address when one is served, and the cookies (see
# GPForum::Controller::Legal).
sub page_payload ( $self, $page, $canonical = undef, $facts = {} ) {
    if ( !$self->known_page($page) ) {
        return undef;
    }

    return {
        basis_key     => "legal.$page.basis",
        heading_id    => "legal-$page-heading",
        incomplete    => length( $facts->{name} // q{} ) ? 0 : 1,
        page          => $page,
        page_metadata => {
            canonical => $canonical,
            robots    => $ROBOTS,
        },
        sections =>
          [ map { _section( $page, $_, $facts ) } @{ $PAGES{$page} } ],
        title_key => "legal.$page",
    };
}

sub _section ( $page, $spec, $facts ) {
    my ( $name, $paragraphs, %extra ) = @{$spec};
    my $prefix = "legal.$page.$name";

    return {
        id        => "legal-$page-$name",
        title_key => "$prefix.title",
        text_keys => [ map { "$prefix.$_" } 1 .. $paragraphs ],
        facts     => [
            map  { _fact( $_, $facts ) }
            grep { !exists $WHEN_GIVEN{$_} || length( $facts->{$_} // q{} ) }
              @{ $extra{fields} // [] }
        ],
        links => [
            map { { route => $_, label_key => "$prefix.link.$_" } }
              @{ $extra{links} // [] }
        ],
        (
            $extra{table}
            ? ( cookies => $facts->{cookies} // [] )
            : ()
        ),
    };
}

# One field: its label, and its value or nothing (the page says it is not
# given). An address is a mailto: link, the security.txt an https one.
sub _fact ( $field, $facts ) {
    my $value = $facts->{$field};
    if ( ref $value eq 'ARRAY' ) {
        $value = @{$value} ? join q{, }, @{$value} : undef;
    }
    $value = defined $value && length $value ? $value : undef;
    my $href =
        !defined $value                                  ? undef
      : $field eq 'email' || $field eq 'privacy_officer' ? "mailto:$value"
      : $field eq 'security_txt'                         ? $value
      :                                                    undef;

    return {
        field     => $field,
        label_key => "legal.field.$field",
        value     => $value,
        href      => $href,
    };
}

# The cookies the forum sets, each first-party and technical (Garante,
# guidelines of 10 June 2021, section 6): the session, which also holds the
# form token (CSRF) and so reaches a visitor who opens a form, lasting a
# member's session and a visitor's the framework default; the language and
# theme a visitor chose; and the browser's signed list of the accounts that
# signed in from it (ADR 0147). Names and lifetimes come from the code that
# sets them.
sub cookie_rows ( $self, %input ) {
    my $days       = sub ($seconds) { return int( $seconds / $DAY_SECONDS ) };
    my $preference = {
        duration_key => 'legal.cookies.duration.days',
        duration     => { days => $days->( $input{preference_seconds} ) },
    };

    return [
        {
            name         => $input{session_name},
            purpose_key  => 'legal.cookies.purpose.session',
            duration_key => 'legal.cookies.duration.session',
            duration     => {
                days  => $days->( $input{session_seconds} ),
                hours => int( $input{visitor_seconds} / $HOUR_SECONDS ),
            },
        },
        map {
            {
                name        => $_->[0],
                purpose_key => "legal.cookies.purpose.$_->[1]",
                %{$preference},
            }
        } (
            [ $input{locale_name}, 'locale' ],
            [ $input{theme_name},  'theme' ],
            [ $input{device_name}, 'device' ],
        )
    ];
}

# RFC 9116: /.well-known/security.txt names where to report a
# vulnerability. Contact and Expires are required; Expires is an RFC 3339
# instant less than a year ahead (section 2.5.5), here the midnight UTC
# EXPIRES_DAYS days on, so a file regenerated from the settings on every
# request is never stale. With no contact there is no valid file, and none
# is served.
sub security_txt ( $self, %input ) {
    my $contact = $input{contact} // q{};
    if ( !length $contact && length( $input{operator_email} // q{} ) ) {
        $contact = 'mailto:' . $input{operator_email};
    }
    return undef if !length $contact;

    my $expires = gmtime( $input{now} + $EXPIRES_DAYS * $DAY_SECONDS );
    my @lines   = (
        "Contact: $contact",
        'Expires: ' . $expires->ymd . 'T00:00:00Z',
        (
            @{ $input{languages} // [] }
            ? 'Preferred-Languages: ' . join q{, },
              @{ $input{languages} }
            : ()
        ),
        "Canonical: $input{base_url}/.well-known/security.txt",
    );

    return join( "\n", @lines ) . "\n";
}

sub render_page ( $self, $controller, $payload ) {
    return GPForum::Web::Responder->new->payload(
        {
            controller => $controller,
            payload    => $payload,
            status     => $HTTP_OK,
            template   => $self->template,
        }
    );
}

1;

__END__

=head1 NAME

GPForum::Web::LegalAccess - Public legal-page payload and render contracts.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $payload = $access->page_payload( 'terms', $canonical, $facts );
    return $access->render_page( $controller, $payload );

    my $text = $access->security_txt(
        contact  => 'mailto:security@forum.example.com',
        base_url => 'https://forum.example.com',
        now      => time,
    );

=head1 DESCRIPTION

Owns the four pages in the colophon and C</.well-known/security.txt>.
Each page follows the text that says what it must hold, and names it: the
terms of use Regulation (EU) 2022/2065 (the Digital Services Act), arts.
14 to 21; the privacy notice Regulation (EU) 2016/679, art. 13, in its
order; the cookie notice Directive 2002/58/EC art. 5(3), D.Lgs. 196/2003
art. 122 and the Garante's guidelines of 10 June 2021; the legal notice
D.Lgs. 70/2003 art. 7 and the Act's points of contact, arts. 11 and 12.
security.txt follows RFC 9116.

It holds the section catalogue keys, the operator facts each section
lists, indexable metadata and the C<legal/page> template. It does not read
PostgreSQL or the settings: L<GPForum::Controller::Legal> passes the
canonical URL and the facts.

=head1 SUBROUTINES/METHODS

=head2 known_page

True for C<cookies>, C<notice>, C<privacy> and C<terms>.

=head2 template

Returns C<legal/page>.

=head2 page_payload

Takes a page name, its canonical URL and the facts hash (the operator's
C<name>, C<address>, C<email>, C<vat_number>, C<register> and
C<privacy_officer>, the C<languages> contact is answered in, the
C<security_txt> address when one is served, and the C<cookies>). Returns
the SSR/JSON hash for a known page: heading id, title and basis keys,
C<incomplete> when the operator has no name, C<page_metadata>, and the
sections, each with its id, title and paragraph keys, its facts (label key,
value or undef, link), the links it points to and, on the cookie notice,
the cookies. Returns undef for an unknown page.

=head2 cookie_rows

Takes the session cookie's name, the member and visitor session lifetimes,
and the language, theme and device cookies' names and lifetime, in
seconds. Returns the cookie notice's rows: each cookie's name, purpose key,
and duration key with its values.

=head2 security_txt

Takes C<contact> (a mailto:, https: or tel: URI), C<operator_email> used
when there is none, C<base_url>, C<languages> and C<now> (an epoch).
Returns RFC 9116 text: Contact, an Expires at midnight UTC 180 days on,
Preferred-Languages and Canonical. Returns undef with no contact, since a
file without one is not valid.

=head2 render_page

Renders the legal page through L<GPForum::Web::Responder>.

=head1 DIAGNOSTICS

JSON versus HTML negotiation stays inside L<GPForum::Web::Responder>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Uses L<Const::Fast>, L<Mojo::Base>, and L<GPForum::Web::Responder>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The translated copy lives in the gettext catalogs, C<locale/en.po> and
C<locale/it.po>, under the C<legal.*> keys. It describes what the software
does; the operator's own policy, and whether a provision applies to them,
remain theirs to review.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
