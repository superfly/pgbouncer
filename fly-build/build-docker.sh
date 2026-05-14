PERCONA_IMG="2.6.0-ppg17.4-pgbouncer1.24.0"

FLY_TAG="percona-$PERCONA_IMG-fly-$(git rev-parse --short HEAD)"
FLY_IMG="ghcr.io/superfly/pgbouncer:$FLY_TAG"

docker build . -f fly-build/Dockerfile --build-arg PERCONA_IMG="${PERCONA_IMG}" -t "$FLY_IMG"

[ "$PUSH" == "true" ] && docker push "$FLY_IMG"
