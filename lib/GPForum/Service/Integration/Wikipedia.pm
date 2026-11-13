# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::Wikipedia;

use Const::Fast;
use Encode     qw(decode FB_CROAK);
use List::Util qw(any);
use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::URL;
use Mojo::Util qw(url_unescape);

our $VERSION = '0.001';
const my $TITLE_LIMIT => 255;
const my $LABEL_LIMIT => 256;

# Exact language domains from Wikimedia's public SiteMatrix, reviewed
# 2026-11-01. Closed, readable editions remain valid citation targets.
# No runtime discovery, wildcard origins or requests to Wikimedia.
const my @LANGUAGES => qw(
  aa ab ace ady af ak als alt am ami an ang ann anp ar arc ary arz as ast atj
  av avk awa ay az azb ba ban bar bat-smg bbc bcl bdr be-tarask be bew bg bh bi
  bjn blk bm bn bo bol bpy br bs btm bug bxr ca cbk-zam cdo ce ceb ch cho chr
  chy ckb co cr crh cs csb cu cv cy da dag de dga din diq dsb dtp dty dv dz ee
  el eml en eo es et eu ext fa fat ff fi fiu-vro fj fo fon fr frp frr fur fy ga
  gag gan gcr gd gl glk gn gom gor got gpe gu guc gur guw gv ha hak haw he hi
  hif ho hr hsb ht hu hy hyw hz ia iba id ie ig igl ii ik ilo inh io is isv it
  iu ja jam jbo jv ka kaa kab kai kaj kbd kbp kcg kg kge ki kj kk kl km kn knc
  ko koi kr krc ks ksh ku kus kv kw ky la lad lb lbe lez lfn lg li lij lld lmo
  ln lo lrc lt ltg lv mad mag mai map-bms mdf mg mh mhr mi min mk ml mn mni
  mnw mos mr mrj ms mt mus mwl my myv mzn na nah nap nds-nl nds ne new ng nia
  nl nn no nov nqo nr nrm nso nup nv ny oc olo om or os pa pag pam pap pcd pcm
  pdc pfl pi pih pl pms pnb pnt ppl ps pt pwn qu rki rm rmy rn ro roa-rup
  roa-tara rsk ru rue rw sa sah sat sc scn sco sd se sg sh shi shn si simple
  sk skr sl sm smn sn so sq sr srn ss st stq su sv sw syl szl szy ta tay tcy
  tdd te tet tg th ti tig tk tl tly tn to tok tpi tr trv ts tt tum tw ty tyv
  udm ug uk ur uz ve vec vep vi vls vo wa war wo wuu xal xh xmf yi yo za zea
  zgh zh-classical zh-min-nan zh-yue zh zu
);
const my %LANGUAGE => map { $_ => 1 } @LANGUAGES;

sub manifest_v1 ($self) {
    return {
        api_version  => 1,
        id           => 'wikipedia',
        name         => 'Wikipedia',
        version      => $VERSION,
        capabilities => ['link.resolve.v1'],
        url_hosts    =>
          [ map { ( "$_.wikipedia.org", "$_.m.wikipedia.org" ) } @LANGUAGES ],
        frame_hosts => [],
    };
}

sub resolve_link_v1 ( $self, $request ) {
    my $url = Mojo::URL->new( $request->{url} );
    my ($language) =
      lc( $url->host ) =~
      /\A ([[:lower:]-]+) (?:[.]m)? [.]wikipedia[.]org \z/amsx;
    return undef if !defined $language || !exists $LANGUAGE{$language};
    my $query = _reading_query($url);
    return undef if !$query;
    my $revision = $query->{oldid};
    return undef
      if $url->path->to_string !~ m{\A (?:/wiki/.+|/w/index[.]php) \z}msx;
    my $title = _page_title( $url, $query );
    return undef if !defined $title && !defined $revision;

    my $canonical = Mojo::URL->new("https://$language.wikipedia.org/");
    my $label;
    if ( defined $revision ) {

        # MediaWiki ignores a supplied title when oldid names a revision.
        # Never falsely attribute that revision to a URL-derived title.
        $canonical->path('/w/index.php')->query( oldid => $revision );
        $label = "#$revision";
    }
    else {
        my $slug = $title;
        $slug =~ tr/ /_/;
        $canonical->path->parts( [ 'wiki', split m{/}msx, $slug ] );
        $label = $title;
    }
    if ( defined $url->fragment ) { $canonical->fragment( $url->fragment ); }
    my $link = $canonical->to_string;
    $link =~ s/'/%27/gmsx;
    my $suffix = ' (' . uc($language) . q{)};
    return {
        api_version => 1,
        provider    => 'wikipedia',
        kind        => 'article',
        label => substr( $label, 0, $LABEL_LIMIT - length $suffix ) . $suffix,
        url   => $link,
    };
}

sub _reading_query ($url) {
    my $query = $url->query->to_hash;
    return undef if any { ref $query->{$_} } keys %{$query};
    return undef if exists $query->{action} && $query->{action} ne 'view';
    return undef if exists $query->{diff};
    return undef
      if defined $query->{oldid}
      && $query->{oldid} !~ /\A [1-9][[:digit:]]{0,19} \z/amsx;
    return $query;
}

sub _page_title ( $url, $query ) {
    my $title = $query->{title};
    if ( $url->path->to_string =~ m{\A /wiki/ (.+) \z}msx ) {
        my $bytes = url_unescape($1);
        try { $title = decode( 'UTF-8', $bytes, FB_CROAK ); }
        catch ($error) { return undef; };
    }
    return defined $title ? _title($title) : undef;
}

sub _title ($title) {
    $title =~ tr/_/ /;
    $title =~ s/\A [ ]+ | [ ]+ \z//gmsx;
    return undef
      if !length($title)
      || length($title) > $TITLE_LIMIT
      || $title =~ /[[:cntrl:]<>\[\]{}|\#\\\x{fffd}]/msx
      || $title =~ /%[[:xdigit:]]{2}/amsx
      || $title =~ m{(?: \A | / ) [.] {1,2} (?: / | \z )}msx;
    return $title;
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::Wikipedia - Independent multilingual Wikipedia plugin.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $descriptor = $provider->resolve_link_v1({api_version => 1, url => $https_url});

=head1 DESCRIPTION

Recognizes exact reviewed Wikipedia language domains, including mobile links,
normalizes readable Unicode page titles, and preserves section anchors and
stable revision citations. Revision labels use the revision id because the
remote revision may belong to a different title. Removes unrelated query
parameters and accepts read links only. Namespaces are retained as part of
the title; no claim is made that a target is a main-namespace encyclopedia
article, exists, or is the latest version. No remote content is fetched.

=head1 SUBROUTINES/METHODS

=head2 manifest_v1

Returns the fixed API v1 manifest, with exact reviewed language and mobile
domains and link.resolve.v1 only. Wikimedia SiteMatrix is the source of the
bundled allowlist; adding a new edition requires a reviewed module update.

=head2 resolve_link_v1

Returns a title, language and canonical reading URL for a supported API v1
request. Supports /wiki/ titles and /w/index.php title or oldid links.
Returns undef for unsupported hosts, actions, malformed titles or revisions.

=head1 DIAGNOSTICS

None. Unsupported links return undef.

=head1 CONFIGURATION AND ENVIRONMENT

Managed independently through Admin Plugins. GPFORUM_INTEGRATION_PLUGINS
sets the installation default.

=head1 DEPENDENCIES

L<Const::Fast>, L<Encode>, L<Mojo::Base>, L<Mojo::URL>, L<Mojo::Util>.

=head1 INCOMPATIBILITIES

Supports integration contract 1 only.

=head1 BUGS AND LIMITATIONS

No extracts, images, imported text, browser frames, account access or remote
existence checks. Content reuse would need an asynchronous versioned API
and explicit attribution and licence handling.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
