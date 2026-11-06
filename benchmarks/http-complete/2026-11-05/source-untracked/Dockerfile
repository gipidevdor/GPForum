# syntax=docker/dockerfile:1
# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

# Build each target architecture independently; never copy host local/ or
# native modules from a different architecture into the runtime image.
ARG PERL_IMAGE=perl:5.44.0-slim-bookworm
FROM ${PERL_IMAGE} AS runtime-base
ENV GPFORUM_PERL=/usr/local/bin/perl
WORKDIR /opt/gpforum
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libpq5 libssl3 zlib1g \
    && rm -rf /var/lib/apt/lists/*

FROM runtime-base AS dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential cpanminus libpq-dev libssl-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* \
    && "$GPFORUM_PERL" /usr/bin/cpanm --notest --mirror https://cpan.metacpan.org/ --mirror-only App::cpm Carton
COPY cpanfile cpanfile.postgres cpanfile.snapshot ./
COPY script/bootstrap-deps script/gpforum-system-perl script/gpforum-carton script/gpforum-cpm ./script/
COPY lib/GPForum/Infrastructure/PerlRuntime.pm ./lib/GPForum/Infrastructure/
RUN script/bootstrap-deps --postgres --production

FROM dependencies AS verify
COPY t/854-perl-runtime.t ./t/
RUN script/gpforum-carton exec prove -l t/854-perl-runtime.t

FROM runtime-base AS runtime
RUN groupadd --gid 10001 gpforum \
    && useradd --uid 10001 --gid 10001 --no-create-home --home-dir /var/lib/gpforum --shell /usr/sbin/nologin gpforum \
    && mkdir -p /var/lib/gpforum/attachments /opt/gpforum/var/run \
    && chown -R gpforum:gpforum /var/lib/gpforum /opt/gpforum/var
COPY --from=verify /opt/gpforum/local ./local
COPY bin ./bin
COPY lib ./lib
COPY script ./script
COPY migrations ./migrations
COPY locale ./locale
COPY templates ./templates
COPY assets ./assets
COPY etc ./etc
COPY cpanfile cpanfile.postgres cpanfile.snapshot ./
RUN chmod -R a+rX /opt/gpforum
ENV GPFORUM_ENV=production \
    GPFORUM_ATTACHMENT_ROOT=/var/lib/gpforum/attachments \
    GPFORUM_RUNTIME_PID_FILE=/var/lib/gpforum/hypnotoad.pid
USER 10001:10001
VOLUME ["/var/lib/gpforum", "/opt/gpforum/var/run"]
ENTRYPOINT ["/opt/gpforum/bin/gpforum"]
CMD ["start", "--service", "--foreground"]
