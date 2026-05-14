ARG PERCONA_IMG

FROM docker.io/debian:bookworm AS builder

RUN apt-get update && apt-get -y install build-essential libtool git pkg-config musl musl-dev musl-tools curl

COPY . /src

RUN cd /src && ./fly-build/build-static.sh

FROM docker.io/percona/percona-postgresql-operator:${PERCONA_IMG}

COPY --from=builder /src/pgbouncer-static /usr/bin/pgbouncer
