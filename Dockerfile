FROM debian:sid-slim

RUN set -ex; \
    if ! command -v gpg > /dev/null; then \
        apt-get update; \
        apt-get install -y --no-install-recommends \
            gnupg \
            dirmngr \
        ; \
        rm -rf /var/lib/apt/lists/*; \
    fi

# explicitly set user/group IDs
RUN set -eux; \
    groupadd -r postgres --gid=999; \
# https://salsa.debian.org/postgresql/postgresql-common/blob/997d842ee744687d99a2b2d95c1083a2615c79e8/debian/postgresql-common.postinst#L32-35
    useradd -r -g postgres --uid=999 --home-dir=/var/lib/postgresql --shell=/bin/bash postgres; \
# also create the postgres user's home directory with appropriate permissions
# see https://github.com/docker-library/postgres/issues/274
    mkdir -p /var/lib/postgresql; \
    chown -R postgres:postgres /var/lib/postgresql

# make the "en_US.UTF-8" locale so postgres will be utf-8 enabled by default
RUN set -eux; \
    if [ -f /etc/dpkg/dpkg.cfg.d/docker ]; then \
# if this file exists, we're likely in "debian:xxx-slim", and locales are thus being excluded so we need to remove that exclusion (since we need locales)
        grep -q '/usr/share/locale' /etc/dpkg/dpkg.cfg.d/docker; \
        sed -ri '/\/usr\/share\/locale/d' /etc/dpkg/dpkg.cfg.d/docker; \
        ! grep -q '/usr/share/locale' /etc/dpkg/dpkg.cfg.d/docker; \
    fi; \
    apt-get update; apt-get install -y --no-install-recommends locales; rm -rf /var/lib/apt/lists/*; \
    localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG en_US.utf8

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
# install "nss_wrapper" in case we need to fake "/etc/passwd" and "/etc/group" (especially for OpenShift)
# https://github.com/docker-library/postgres/issues/359
# https://cwrap.org/nss_wrapper.html
        libnss-wrapper \
# install "xz-utils" for .sql.xz docker-entrypoint-initdb.d files
        xz-utils \
    ; \
    rm -rf /var/lib/apt/lists/*

RUN mkdir /docker-entrypoint-initdb.d

ENV PG_MAJOR 12
ENV POSTGIS 3

RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        wget ca-certificates "postgresql-$PG_MAJOR" "postgresql-$PG_MAJOR-postgis-$POSTGIS" postgis \
    ; \
    wget -O /usr/local/bin/docker-entrypoint.sh "https://raw.githubusercontent.com/docker-library/postgres/master/$PG_MAJOR/docker-entrypoint.sh"; \
    chmod +x /usr/local/bin/docker-entrypoint.sh; \
    apt-get remove -y wget ca-certificates; \
    apt-get autoremove -y; \
    rm -rf /var/lib/apt/lists/*

# Build and install osml10n extension and su-exec (lightweight alternative for gosu).
RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        git ca-certificates build-essential postgresql-server-dev-all curl libkakasi2-dev libutf8proc-dev debhelper libicu-dev pandoc \
    ; \
    git clone https://github.com/giggls/mapnik-german-l10n; \
    cd mapnik-german-l10n; \
    make deb; \
    cd ..; \
    dpkg -i *osml10n_*.deb; \
    rm -rf mapnik-german-l10n *osml10n*.deb; \
    git clone https://github.com/ncopa/su-exec.git; \
    cd su-exec; \
    make; \
    mv su-exec /usr/sbin/gosu; \
    cd ..; \
    rm -rf su-exec; \
    apt-get remove -y git ca-certificates build-essential postgresql-server-dev-all curl debhelper pandoc; \
    apt-get autoremove -y; \
    rm -rf /var/lib/apt/lists/*

# make the sample config easier to munge (and "correct by default")
RUN set -eux; \
    dpkg-divert --add --rename --divert "/usr/share/postgresql/postgresql.conf.sample.dpkg" "/usr/share/postgresql/$PG_MAJOR/postgresql.conf.sample"; \
    cp -v /usr/share/postgresql/postgresql.conf.sample.dpkg /usr/share/postgresql/postgresql.conf.sample; \
    ln -sv ../postgresql.conf.sample "/usr/share/postgresql/$PG_MAJOR/"; \
    sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" /usr/share/postgresql/postgresql.conf.sample; \
    grep -F "listen_addresses = '*'" /usr/share/postgresql/postgresql.conf.sample

RUN mkdir -p /var/run/postgresql && chown -R postgres:postgres /var/run/postgresql && chmod 2777 /var/run/postgresql

ENV PATH $PATH:/usr/lib/postgresql/$PG_MAJOR/bin
ENV PGDATA /var/lib/postgresql/data
# this 777 will be replaced by 700 at runtime (allows semi-arbitrary "--user" values)
RUN mkdir -p "$PGDATA" && chown -R postgres:postgres "$PGDATA" && chmod 777 "$PGDATA"
VOLUME /var/lib/postgresql/data

ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 5432
CMD ["postgres"]
