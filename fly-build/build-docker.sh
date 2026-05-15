#!/usr/bin/env bash

build() {
  PERCONA_IMG="2.6.0-ppg$1-pgbouncer1.24.0"

  FLY_TAG="percona-$PERCONA_IMG-fly-$(git rev-parse --short HEAD)"
  FLY_IMG="ghcr.io/superfly/pgbouncer:$FLY_TAG"

  docker build . -f fly-build/Dockerfile --build-arg PERCONA_IMG="${PERCONA_IMG}" -t "$FLY_IMG"

  [ "$PUSH" == "true" ] && docker push "$FLY_IMG"
}

# Both PG 17.4 and 16.8
build "17.4"
build "16.8"
