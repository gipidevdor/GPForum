# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::Dkim;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;

use Carp qw(croak);
use Email::Simple;
use Mail::DKIM::Signer;
use Mail::DKIM::Verifier;

our $VERSION = '0.001';

const my $DNS_TIMEOUT => 3;
__PACKAGE__->requires('config');

sub sign ( $self, $email ) {
    my $config = $self->config;
    return $email if !length( $config->dkim_key_file );
    my ( $domain, $selector, $key ) =
      ( $config->dkim_domain, $config->dkim_selector, $config->dkim_key_file );
    croak 'DKIM needs a domain and selector'
      if $domain   !~ /\A[[:alnum:]](?:[[:alnum:].-]*[[:alnum:]])?\z/imsx
      || $selector !~ /\A[[:alnum:]][[:alnum:]_-]*\z/imsx;
    croak 'DKIM key must be a readable private file (mode 0600)'
      if !-f $key || !-r $key || -l $key || ( ( stat $key )[2] & oct '077' );
    my ($from_domain) = $config->mail_from =~ /\@([^\s>]+)>?\z/msx;
    croak 'DKIM signing domain must match the From domain'
      if !defined $from_domain || lc $from_domain ne lc $domain;
    my $signer = Mail::DKIM::Signer->new(
        Algorithm => 'rsa-sha256',
        Method    => 'relaxed/relaxed',
        Domain    => $domain,
        Selector  => $selector,
        KeyFile   => $key,
        Headers   => 'List-Unsubscribe:List-Unsubscribe-Post',
    );
    my $raw = $email->as_string;
    $raw =~ s/\r?\n/\r\n/gmsx;
    $signer->PRINT($raw);
    $signer->CLOSE;
    my $signature = $signer->signature or croak 'DKIM produced no signature';
    return Email::Simple->new( $signature->as_string . "\r\n" . $raw );
}

# Verify a real signature with the public DNS record, without sending mail.
# A present TXT record alone does not prove it matches the private key.
sub check ($self) {
    my $email = $self->sign(
        Email::Simple->create(
            header => [
                From    => $self->config->mail_from,
                To      => 'probe@invalid',
                Subject => 'GPForum DKIM diagnostic'
            ],
            body => "DKIM probe\r\n"
        )
    );
    local $Mail::DKIM::DNS::TIMEOUT = $DNS_TIMEOUT;
    my $verifier = Mail::DKIM::Verifier->new;
    $verifier->PRINT( $email->as_string );
    $verifier->CLOSE;
    return {
        status  => $verifier->result eq 'pass' ? 'ok' : 'fail',
        message => $verifier->result_detail,
        record  => $self->config->dkim_selector
          . '._domainkey.'
          . $self->config->dkim_domain
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::Dkim - Application DKIM boundary.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Identity::Dkim->new(...);

=head1 DESCRIPTION

Application DKIM boundary. See ADR 0155.

=head1 SUBROUTINES/METHODS

=head2 sign

Takes an Email::Simple message and returns its signed serialization. A configured signing failure propagates before transport delivery. An empty key path preserves MTA signing.

=head2 check

Signs a diagnostic message and verifies it against the public DNS selector without delivering it. Returns status, message and record.

=head1 DIAGNOSTICS

Exceptions propagate to the command or worker, which reports the failure.

=head1 CONFIGURATION AND ENVIRONMENT

Receives configuration or collaborators through constructor arguments. See
ADR 0155 for the operator settings and commands.

=head1 DEPENDENCIES

Uses the modules listed in the source preamble and the locked cpanfile.

=head1 INCOMPATIBILITIES

Requires Perl 5.40 or newer.

=head1 BUGS AND LIMITATIONS

See ADR 0155 for the scope and operational limits.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
