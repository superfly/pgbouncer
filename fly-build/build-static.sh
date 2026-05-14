#!/usr/bin/env bash
# Build PgBouncer as a fully static musl binary with c-ares DNS backend and OpenSSL TLS.

set -euo pipefail

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	grep '^# ' "$0" | sed 's/^# //'
	exit 0
fi

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

OPENSSL_VERSION=${OPENSSL_VERSION:-3.5.6}
LIBEVENT_VERSION=${LIBEVENT_VERSION:-2.1.12-stable}
CARES_VERSION=${CARES_VERSION:-1.34.6}

MUSL_CC=${MUSL_CC:-musl-gcc}
JOBS=${JOBS:-$(nproc)}
BUILD_DIR=${BUILD_DIR:-/tmp/pgbouncer-static-build}
SRC_DIR=${SRC_DIR:-$BUILD_DIR/src}
PREFIX=${PREFIX:-$BUILD_DIR/prefix}
OUT=${OUT:-$ROOT/pgbouncer-static}

export LIBRARY_PATH=${LIBRARY_PATH:-/usr/lib}

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "error: required command not found: $1" >&2
		exit 1
	}
}

fetch() {
	local url=$1
	local dest=$2
	if [ ! -f "$dest" ]; then
		curl -L --fail --retry 3 -o "$dest" "$url"
	fi
}

need_cmd "$MUSL_CC"
need_cmd curl
need_cmd tar
need_cmd make
need_cmd ar
need_cmd ranlib
need_cmd strip

mkdir -p "$SRC_DIR" "$PREFIX"

build_openssl() {
	local tarball="$SRC_DIR/openssl-$OPENSSL_VERSION.tar.gz"
	local build="$SRC_DIR/openssl-$OPENSSL_VERSION-musl"

	if [ -f "$PREFIX/lib64/libssl.a" ] && [ -f "$PREFIX/lib64/libcrypto.a" ]; then
		echo "==> OpenSSL already built"
		return
	fi

	echo "==> Building OpenSSL $OPENSSL_VERSION"
	fetch "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" "$tarball"
	rm -rf "$build"
	mkdir -p "$build"
	tar xzf "$tarball" -C "$build" --strip-components=1
	(
		cd "$build"
		CC="$MUSL_CC" ./Configure linux-x86_64 \
			no-shared no-tests no-module no-dso no-zlib \
			no-secure-memory no-engine no-afalgeng \
			--prefix="$PREFIX" --openssldir="$PREFIX/ssl"
		make -j"$JOBS" build_libs
		make install_dev
	)

	mkdir -p "$PREFIX/lib"
	ln -sf "$PREFIX/lib64/libssl.a" "$PREFIX/lib/libssl.a"
	ln -sf "$PREFIX/lib64/libcrypto.a" "$PREFIX/lib/libcrypto.a"
}

build_libevent() {
	local tarball="$SRC_DIR/libevent-$LIBEVENT_VERSION.tar.gz"
	local build="$SRC_DIR/libevent-$LIBEVENT_VERSION-musl"

	if [ -f "$PREFIX/lib/libevent.a" ]; then
		echo "==> libevent already built"
		return
	fi

	echo "==> Building libevent $LIBEVENT_VERSION"
	fetch "https://github.com/libevent/libevent/releases/download/release-$LIBEVENT_VERSION/libevent-$LIBEVENT_VERSION.tar.gz" "$tarball"
	rm -rf "$build"
	mkdir -p "$build"
	tar xzf "$tarball" -C "$build" --strip-components=1
	(
		cd "$build"
		LIBRARY_PATH="$LIBRARY_PATH" CC="$MUSL_CC" ./configure \
			--prefix="$PREFIX" \
			--disable-shared --enable-static \
			--disable-openssl \
			--disable-samples --disable-libevent-regress
		LIBRARY_PATH="$LIBRARY_PATH" make -j"$JOBS"
		make install
	)
}

build_cares() {
	local tarball="$SRC_DIR/c-ares-$CARES_VERSION.tar.gz"
	local build="$SRC_DIR/c-ares-$CARES_VERSION-musl"

	if [ -f "$PREFIX/lib/libcares.a" ]; then
		echo "==> c-ares already built"
		return
	fi

	echo "==> Building c-ares $CARES_VERSION"
	fetch "https://github.com/c-ares/c-ares/releases/download/v$CARES_VERSION/c-ares-$CARES_VERSION.tar.gz" "$tarball"
	rm -rf "$build"
	mkdir -p "$build"
	tar xzf "$tarball" -C "$build" --strip-components=1
	(
		cd "$build"
		LIBRARY_PATH="$LIBRARY_PATH" CC="$MUSL_CC" ./configure \
			--prefix="$PREFIX" \
			--disable-shared --enable-static \
			--disable-tests
		LIBRARY_PATH="$LIBRARY_PATH" make -j"$JOBS"
		make install
	)
}

prepare_pgbouncer_tree() {
	cd "$ROOT"

	if [ -f .gitmodules ]; then
		echo "==> Ensuring git submodules are present"
		git submodule update --init --recursive
	fi

	if [ ! -x ./configure ]; then
		echo "==> Generating configure script"
		./autogen.sh
	fi
}

build_pgbouncer() {
	echo "==> Building PgBouncer"
	cd "$ROOT"
	make clean >/dev/null 2>&1 || true

	LIBRARY_PATH="$LIBRARY_PATH" ./configure \
		--with-cares="$PREFIX" \
		--with-openssl="$PREFIX" \
		--disable-debug \
		CC="$MUSL_CC" \
		CFLAGS="-O2" \
		CPPFLAGS="-I$PREFIX/include" \
		LDFLAGS="-static -L$PREFIX/lib" \
		CARES_CFLAGS="-I$PREFIX/include" \
		CARES_LIBS="$PREFIX/lib/libcares.a" \
		LIBEVENT_CFLAGS="-I$PREFIX/include" \
		LIBEVENT_LIBS="$PREFIX/lib/libevent.a" \
		LIBS="-pthread"

	LIBRARY_PATH="$LIBRARY_PATH" make -j"$JOBS" pgbouncer
	cp pgbouncer "$OUT"
	strip "$OUT"
}

verify() {
	echo "==> Verifying $OUT"
	file "$OUT"
	if ldd "$OUT" 2>&1 | grep -vq "not a dynamic executable"; then
		echo "error: output does not appear to be fully static" >&2
		ldd "$OUT" || true
		exit 1
	fi
	"$OUT" --version
	sha256sum "$OUT"
}

build_openssl
build_libevent
build_cares
prepare_pgbouncer_tree
build_pgbouncer
verify

echo "==> Done: $OUT"
