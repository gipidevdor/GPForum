requires 'perl', '5.040.0';

requires 'Mojolicious', '9.54';
# Mojo::Base -async_await keeps the complete HTTP call chain on Mojo::Promise.
requires 'Future::AsyncAwait', '0.71';
# The supported OS profiles require libev's native epoll/kqueue backend.
requires 'EV', '4.37';
requires 'Mojo::Pg', '5.01';
requires 'DBD::Pg', '3.21.2';
requires 'Minion', '12.0';
requires 'JSON::MaybeXS', '1.004008';
# Never loaded by name: it is the XS backend JSON::MaybeXS selects at runtime,
# and the floor is what keeps it from falling back to the pure-Perl one.
requires 'Cpanel::JSON::XS', '4.80';
requires 'DateTime', '1.68';
# Named directly by the date formatter and the time zone preference (9.3).
requires 'DateTime::TimeZone', '2.72';
requires 'Crypt::Argon2', '0.032';
requires 'Crypt::URandom', '0.55';
requires 'Authen::WebAuthn', '== 0.005';
requires 'CBOR::XS', '1.87';
requires 'Email::Sender', '2.603';
requires 'Email::Address::XS', '1.05';
requires 'Email::Simple', '2.218';
requires 'Email::MIME', '1.954';
requires 'Mail::DKIM', '1.20261105';
requires 'Net::DNS', '1.57';
requires 'Crypt::PK::Ed25519', '0.091';
requires 'Crypt::JWT', '0.038';
# Net::SMTP loads Authen::SASL only when the server asks for AUTH, so
# nothing names it in a use line -- and without it every SMTP setup with
# GPFORUM_SMTP_USERNAME failed at the first message.
requires 'Authen::SASL', '2.2100';
# Mail leaves over TLS by default (GPFORUM_SMTP_TLS: STARTTLS on 587,
# implicit on 465), which Net::SMTP speaks only through IO::Socket::SSL; it
# loads it then, so nothing names it in a use line, and without it the start
# refuses an smtp transport. doctor's https probes use it too.
requires 'IO::Socket::SSL', '2.099';
requires 'Const::Fast', '0.014';

# Security floors for transitive dependencies the service loads: releases that
# fix a published advisory or CVE, or a memory-safety defect in XS code.
requires 'DBI', '1.656';
requires 'Clone', '0.51';
requires 'Package::Stash::XS', '0.32';
requires 'SQL::Abstract', '2.000003';

# What the suite loads. Production keeps these small, pure-Perl requirements
# as before the switch to cpm; only the develop phase is omitted.
on test => sub {
    requires 'Test::More', '1.302226';
    requires 'Test::Exception', '0.43';
    requires 'Test::Fatal', '0.019';
};

# The maintainer's tools. A production host installs without them:
# `make install-deps-production` (script/bootstrap-deps --production).
on develop => sub {
    # Historical ORM metadata and fixture comparisons are maintainer-only.
    requires 'DBIx::Class', '0.082844';
    # Perl::Critic, Perl::Tidy, Devel::Cover and Devel::NYTProf are invoked as
    # programs by script/, not loaded by name, so they are declared but never
    # appear in a use statement.
    requires 'Perl::Critic', '1.156';
    requires 'Perl::Tidy', '20260826';
    requires 'Devel::Cover', '1.52';
    requires 'Devel::NYTProf', '6.16';

    # Security floors for transitive test-tool dependencies.
    requires 'URI', '5.40';
    requires 'HTML::Parser', '3.86';
    requires 'HTTP::Date', '6.08';
    requires 'List::SomeUtils::XS', '0.59';
};

# PostgreSQL test helper and compatibility feature pins. The runtime driver
# and Mojo::Pg are required above; production no longer depends on DBIx.
# `script/bootstrap-deps --postgres` enables this feature in cpm.
feature 'postgres', sub {
    do './cpanfile.postgres';
};
