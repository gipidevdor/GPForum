# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Plugin::Contract;

use Const::Fast;
use List::Util qw(any);
use Hash::Util qw(lock_hash);
use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::URL;
use Mojo::JSON qw(encode_json);
use GPForum::X::Argument;

our $VERSION = '0.001';
const my $API           => 1;
const my $URL_LIMIT     => 2_048;
const my $TEXT_LIMIT    => 256;
const my $LIST_LIMIT    => 16;
const my $HOST_LIMIT    => 1_024;
const my $HTTPS_PORT    => '443';
const my $SOURCE_LIMIT  => 50_000;
const my $FORMULA_LIMIT => 4_096;
const my $SPAN_LIMIT    => 50;
const my %CAPABILITY => map { $_ => 1 }
  qw(link.resolve.v1 media.embed.v1 math.render.v1);
const my %KINDS => map { $_ => 1 }
  qw(video audio post article repository issue pull_request commit release);

sub manifest_v1 ( $self, $manifest ) {
    _record( $manifest,
        [qw(api_version id name version capabilities url_hosts frame_hosts)],
        [] );
    _api( $manifest->{api_version} );
    _text( $manifest->{id} );
    if ( $manifest->{id} !~ /\A [[:lower:]][[:lower:][:digit:]_]{0,31} \z/amsx )
    {
        _refuse();
    }
    _text( $manifest->{name} );
    _text( $manifest->{version} );
    if ( $manifest->{version} !~
        /\A [[:digit:]]+ (?: [.] [[:digit:]]+ ){1,2} \z/amsx )
    {
        _refuse();
    }
    my $capabilities = _list( $manifest->{capabilities} );

    for my $capability ( @{$capabilities} ) {
        if ( !exists $CAPABILITY{$capability} ) { _refuse(); }
    }
    my $hosts  = _hosts( $manifest->{url_hosts} );
    my $frames = _hosts( $manifest->{frame_hosts} );
    _capability_origins( $capabilities, $hosts, $frames );
    return {
        %{$manifest},
        capabilities => $capabilities,
        url_hosts    => $hosts,
        frame_hosts  => $frames
    };
}

sub _capability_origins ( $capabilities, $hosts, $frames ) {
    my $math = any { $_ eq 'math.render.v1' } @{$capabilities};
    if ($math) {
        if ( @{$capabilities} != 1 || @{$hosts} || @{$frames} ) { _refuse(); }
    }
    elsif ( !@{$hosts} || !any { $_ eq 'link.resolve.v1' } @{$capabilities} ) {
        _refuse();
    }
    my $embeds = any { $_ eq 'media.embed.v1' } @{$capabilities};
    if ( ( @{$frames} ? !$embeds : $embeds ) ) { _refuse(); }
    return;
}

sub math_request_v1 ( $self, $request ) {
    _record( $request, [qw(api_version source)], [] );
    _api( $request->{api_version} );
    _source( $request->{source}, $SOURCE_LIMIT );
    my %copy = %{$request};
    lock_hash(%copy);
    return \%copy;
}

sub math_response_v1 ( $self, $manifest, $request, $response ) {
    _record( $response, [qw(api_version provider spans)], [] );
    _api( $response->{api_version} );
    _text( $response->{provider} );
    if ( $response->{provider} ne $manifest->{id}
        || !any { $_ eq 'math.render.v1' } @{ $manifest->{capabilities} } )
    {
        _refuse();
    }
    my $spans = $response->{spans};
    if ( ref $spans ne 'ARRAY' || @{$spans} > $SPAN_LIMIT ) { _refuse(); }
    my @copy;
    my $end = 0;
    for my $span ( @{$spans} ) {
        _math_span( $span, $request->{source}, $end );
        $end = $span->{start} + $span->{length};
        push @copy, { %{$span} };
    }
    return { %{$response}, spans => \@copy };
}

sub _math_span ( $span, $source, $end ) {
    _record( $span, [qw(start length source display)], [] );
    _source( $span->{source}, $FORMULA_LIMIT );
    _text( $span->{display} );
    for my $key (qw(start length)) {
        if (  !defined $span->{$key}
            || ref $span->{$key}
            || encode_json( $span->{$key} ) !~ /\A [[:digit:]]{1,5} \z/amsx )
        {
            _refuse();
        }
    }
    if (   $span->{start} < $end
        || !$span->{length}
        || $span->{start} + $span->{length} > length $source )
    {
        _refuse();
    }
    my $selected = substr $source, $span->{start}, $span->{length};
    my $tex      = $span->{source};
    my @forms =
        $span->{display} eq 'inline' ? ( "\$$tex\$", q{\(} . $tex . q{\)} )
      : $span->{display} eq 'block'  ? ( "\$\$$tex\$\$", q{\[} . $tex . q{\]} )
      :                                ();
    if ( !length($tex) || !any { $_ eq $selected } @forms ) {
        _refuse();
    }
    return;
}

sub _source ( $value, $limit ) {
    if (  !defined $value
        || ref $value
        || substr( encode_json($value), 0, 1 ) ne q{"}
        || length($value) > $limit
        || $value =~ /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/msx )
    {
        _refuse();
    }
    return;
}

sub request_v1 ( $self, $request ) {
    _record( $request, [qw(api_version url)], [] );
    _api( $request->{api_version} );
    $self->https_url( $request->{url} );
    my %copy = %{$request};
    lock_hash(%copy);
    return \%copy;
}

sub response_v1 ( $self, $manifest, $response ) {
    return undef if !defined $response;
    _record( $response, [qw(api_version provider kind label url)], ['embed'] );
    _api( $response->{api_version} );
    _text( $response->{provider} );
    if ( $response->{provider} ne $manifest->{id} ) { _refuse(); }
    _text( $response->{kind} );
    if ( !exists $KINDS{ $response->{kind} } ) { _refuse(); }
    _text( $response->{label} );
    $self->_allowed_url( $response->{url}, $manifest->{url_hosts} );
    my %copy = %{$response};

    if ( exists $response->{embed} ) {
        my $embed = $response->{embed};
        _record( $embed, [qw(url kind)], [] );
        _text( $embed->{kind} );
        if ( $embed->{kind} ne 'audio' && $embed->{kind} ne 'video' ) {
            _refuse();
        }
        if ( $embed->{kind} ne $response->{kind} ) { _refuse(); }
        $self->_allowed_url( $embed->{url}, $manifest->{frame_hosts} );
        $copy{embed} = { %{$embed} };
    }
    return \%copy;
}

sub https_url ( $self, $raw ) {
    if ( !defined $raw || ref $raw || length($raw) > $URL_LIMIT ) { _refuse(); }
    if ( $raw !~ m{\A https:// [^\s<>"'\\]+ \z}msxi )             { _refuse(); }
    my $url = Mojo::URL->new($raw);
    if ( !$url->host || defined $url->userinfo )           { _refuse(); }
    if ( defined $url->port && $url->port ne $HTTPS_PORT ) { _refuse(); }
    return $url;
}

sub _allowed_url ( $self, $raw, $hosts ) {
    my $url = $self->https_url($raw);
    if ( !any { $_ eq lc( $url->host ) } @{$hosts} ) {
        _refuse();
    }
    return;
}

sub _record ( $value, $required, $optional ) {
    if ( ref $value ne 'HASH' ) { _refuse(); }
    my %allowed = map { $_ => 1 } @{$required}, @{$optional};
    if ( any { !exists $allowed{$_} } keys %{$value} ) {
        _refuse();
    }
    if ( any { !exists $value->{$_} } @{$required} ) {
        _refuse();
    }
    return;
}

sub _api ($value) {
    if ( !defined $value || ref $value || encode_json($value) ne "$API" ) {
        _refuse();
    }
    return;
}

sub _text ($value) {
    if ( !defined $value || ref $value )               { _refuse(); }
    if ( substr( encode_json($value), 0, 1 ) ne q{"} ) { _refuse(); }
    if (  !length($value)
        || length($value) > $TEXT_LIMIT
        || $value =~ /[[:cntrl:]]/msx )
    {
        _refuse();
    }
    return;
}

sub _list ( $value, $limit = $LIST_LIMIT ) {
    if ( ref $value ne 'ARRAY' || @{$value} > $limit ) { _refuse(); }
    my %seen;
    for my $item ( @{$value} ) {
        _text($item);
        if ( $seen{$item}++ ) { _refuse(); }
    }
    return [ @{$value} ];
}

sub _hosts ($value) {
    my $hosts = _list( $value, $HOST_LIMIT );
    for my $host ( @{$hosts} ) {
        if ( $host !~
            /\A [[:lower:][:digit:]]+ (?: [.-] [[:lower:][:digit:]]+ )* \z/amsx
          )
        {
            _refuse();
        }
    }
    return $hosts;
}

sub _refuse {
    GPForum::X::Argument->throw(
        message => 'plugin API v1 contract violation' );
}

1;

__END__

=head1 NAME

GPForum::Service::Plugin::Contract - Closed, versioned plugin API boundary.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $manifest = $contract->manifest_v1($plugin->manifest_v1);
    my $request = $contract->request_v1({api_version => 1, url => $url});
    my $response = $contract->response_v1($manifest, $plugin->resolve_link_v1($request));

=head1 DESCRIPTION

API v1 uses plain data only. Unknown or missing fields, references in scalar
fields, unsupported capabilities, incompatible versions, duplicate list items,
unsafe URLs and undeclared origins are rejected. Request hashes are copied
and locked. Responses and manifests are copied before core use. No controller,
database, credentials or core service objects cross this boundary.

=head1 SUBROUTINES/METHODS

=head2 manifest_v1

Validates and copies a manifest. Link modules declare link.resolve.v1 and
optional media.embed.v1; a local math module declares only math.render.v1.

=head2 math_request_v1

Validates and locks a plain API version and source request, bounded to 50,000
characters. Receives no user, controller, configuration or service object.

=head2 math_response_v1

Validates at most 50 ordered, nonoverlapping spans in the exact input source.
Each formula is bounded to 4,096 characters and must match its declared
inline or display delimiters. No rendered HTML crosses this boundary.

=head2 request_v1

Validates and locks an API version and HTTPS URL request.

=head2 response_v1

Validates a response against its manifest, or accepts undef for no match.

=head2 https_url

Validates a bounded credential-free HTTPS URL and returns an internal URL object.
This internal utility is not part of the plugin wire contract.

=head1 DIAGNOSTICS

Invalid data throws L<GPForum::X::Argument> without including submitted content.

=head1 CONFIGURATION AND ENVIRONMENT

None. API v1 is fixed; new operations require a new explicit contract.

=head1 DEPENDENCIES

L<Const::Fast>, L<Hash::Util>, L<Mojo::Base>, L<Mojo::URL>, L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

No implicit coercion or unknown extension fields are supported.

=head1 BUGS AND LIMITATIONS

This validates a data boundary, not an execution sandbox for privileged Perl.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
