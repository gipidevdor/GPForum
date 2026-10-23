# GPForum CPAN License Review

This review is an operational gate, not a substitute for legal advice. It
records the CPAN dependency decisions GPForum currently accepts for a
BSD-3-Clause project. Production dependencies must remain pinned by
`cpanfile.snapshot`; development-only dependencies must not become runtime
requirements without review.

| Module | Scope | License posture | Risk | Decision |
| --- | --- | --- | --- | --- |
| perl | runtime | Perl 5 license | language runtime | allowed |
| Mojolicious | runtime | Artistic-2.0 | mature web framework; floor 9.51 for the Mojo::DOM title and textarea escaping fix of 9.50 and the WebSocket handshake fix of 9.51 | allowed |
| EV | runtime | Perl 5 license; bundled libev uses BSD-2-Clause or GPL-2.0-or-later | XS event loop; required epoll on Linux and kqueue on macOS/FreeBSD; pinned by Carton | allowed |
| DBIx::Class | runtime | Perl 5 license | mature ORM layer | allowed |
| Minion | runtime | Artistic-2.0 | optional async worker framework | allowed |
| JSON::MaybeXS | runtime | Perl 5 license | JSON adapter selection | allowed |
| Cpanel::JSON::XS | runtime | Perl 5 license | preferred JSON::MaybeXS backend; floor 4.80 for the decode, encode and incr_parse CVEs it fixes (CVE-2026-110672 to CVE-2026-110687), after CVE-2026-9334 and CVE-2026-9516 | allowed |
| Try::Tiny | runtime (transitive) | MIT | required by DBIx::Class, DateTime and Email::Sender; GPForum itself uses native try/catch | allowed |
| DateTime | runtime | Perl 5 license | date/time core dependency | allowed |
| DateTime::TimeZone | runtime | Perl 5 license | named directly by the date formatter and the time zone preference; tz data is frozen in the pinned release, so zone rule changes need a version bump | allowed |
| Crypt::Argon2 | runtime | Apache-2.0 | password hashing XS dependency | allowed |
| Crypt::URandom | runtime | Perl 5 license | entropy source | allowed |
| Crypt::PK::Ed25519 | runtime (CryptX) | Perl 5 license | XS Ed25519 post attestations; CryptX 0.091 is pinned in the lock, with its bundled cryptographic implementation | allowed |
| Email::Sender | runtime | Perl 5 license | email delivery boundary | allowed |
| Email::Address::XS | runtime | Perl 5 license | Email::Sender::Simple address parsing | allowed |
| Email::Simple | runtime | Perl 5 license | message construction in the identity mailer | allowed |
| Email::MIME | runtime | Perl 5 license | inbound reply MIME parsing; pinned to 1.954, with message size, part count and nesting bounded by MailIn | allowed |
| Authen::SASL | runtime | Perl 5 license | SMTP AUTH mechanisms Net::SMTP loads on demand when GPFORUM_SMTP_USERNAME is set | allowed |
| IO::Socket::SSL | runtime | Perl 5 license | TLS for SMTP (STARTTLS or implicit, the default under GPFORUM_SMTP_TLS) and doctor's https probes; brings Net::SSLeay (Artistic-2.0), XS built against the host's OpenSSL, whose security updates come from the OS | allowed |
| Const::Fast | runtime | Perl 5 license | immutable scalar helper | allowed |
| DBI | runtime | Perl 5 license | transitive database interface; security floor 1.656 for CVE-2026-108518 and CVE-2026-111879, after the CPANSA-DBI 2026 advisories fixed in 1.652+ | allowed |
| Clone | runtime (transitive) | Perl 5 license | XS deep copy, loaded through DateTime and Specio; floor 0.51 for C stack growth past MAX_DEPTH and memory leaks | allowed |
| Package::Stash::XS | runtime (transitive) | Perl 5 license | XS stash access, loaded through DBIx::Class and namespace::clean; floor 0.32 for the crash of perl issue 24845 | allowed |
| Perl::Critic | develop | Perl 5 license | quality gate only | dev-only allowed |
| Perl::Tidy | develop | GPL-compatible tooling posture | formatting gate only | dev-only allowed |
| Test::More | develop | Perl 5 license | test framework | dev-only allowed |
| Test::Exception | develop | Perl 5 license | test helper | dev-only allowed |
| Test::Fatal | develop | Perl 5 license | test helper | dev-only allowed |
| Devel::Cover | develop | Perl 5 license | coverage tool | dev-only allowed |
| Devel::NYTProf | develop | Perl 5 license | profiling tool | dev-only allowed |
| URI | develop | Perl 5 license | transitive web-test dependency; security floor 5.40 for the over-long IDNA label slowdown fixed in 5.39, after the CPANSA-URI 2026 advisory | dev-only allowed |
| HTML::Parser | develop | Perl 5 license | transitive Devel::Cover dependency; floor 3.86 for the self-referencing entity expansion fix | dev-only allowed |
| HTTP::Date | develop | Perl 5 license | transitive web-test dependency; security floor for CPANSA-HTTP-Date 2026 advisory | dev-only allowed |
| List::SomeUtils::XS | develop | Artistic-2.0 | transitive Perl::Critic dependency; security floor for CPANSA-List-SomeUtils-XS 2026 advisory | dev-only allowed |
| DBD::Pg | optional-postgres | Perl 5 license | PostgreSQL driver for DB-backed CI and deployments | allowed |
| Mojo::Pg | optional-postgres | Artistic-2.0 | required by Minion PostgreSQL backend | allowed |
| Test::PostgreSQL | optional-postgres | Perl 5 license | PostgreSQL integration testing helper | dev-only allowed |

Dependency governance rules:

* Any new `requires` entry in `cpanfile` or `cpanfile.postgres` must add a row here in the same patch.
* Runtime dependencies require explicit license posture and operational risk.
* Development dependencies may be stricter or heavier only if they do not become
  production requirements.
* `script/cpan-license-check` is the mechanical gate that ensures review
  coverage does not drift.
