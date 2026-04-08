#!/bin/bash
# build-curl.sh — Build curl 7.88.1 natively on EtrayZ NAS
#
# Target:  OX810SE ARM926EJ-S 183MHz, kernel 2.6.24.4, GCC 4.4.5
# Depends: OpenSSL 1.1.1w at /usr/local/lib/ (run build-openssl.sh first)
# Result:  /usr/bin/curl  (old curl backed up to /usr/bin/curl.7.21.bak)
#
# Why 7.88.1?  curl 7.21 (Squeeze) lacks TLS 1.2 support.
# Why not 8.x? curl 8.0+ calls eventfd(0, EFD_NONBLOCK|EFD_CLOEXEC).
#              EFD_CLOEXEC was added in kernel 2.6.27 — this NAS has 2.6.24.
#              curl 8.x segfaults immediately on this kernel.
#
# Notes:
#   - /tmp is a small tmpfs on the NAS. Set TMPDIR to avoid "no space" errors
#     during configure and build.
#   - Use -j1 to avoid libtool parallel-build race conditions with GCC 4.4.5.
#   - --disable-dependency-tracking speeds up single-CPU builds.
#
# Usage: bash build-curl.sh
# Time:  ~15 minutes on 183 MHz ARM

set -e

VERSION="7.88.1"
SRC_DIR="/home/sysadmin/curl-${VERSION}"
OPENSSL_PREFIX="/usr/local"
TMPDIR_BUILD="/home/sysadmin/tmp"

echo "=== Building curl ${VERSION} natively on EtrayZ ==="
echo ""

# Require OpenSSL 1.1.1
if [[ ! -f "$OPENSSL_PREFIX/lib/libssl.so.1.1" ]]; then
    echo "ERROR: OpenSSL 1.1.1 not found at $OPENSSL_PREFIX/lib/libssl.so.1.1"
    echo "       Run build-openssl.sh first."
    exit 1
fi

# Use a real tmpdir (NAS /tmp is very small)
mkdir -p "$TMPDIR_BUILD"
export TMPDIR="$TMPDIR_BUILD"

# ---- Download ----
if [[ ! -d "$SRC_DIR" ]]; then
    cd /home/sysadmin
    echo "[1/5] Downloading curl ${VERSION}..."
    wget -q "https://curl.se/download/curl-${VERSION}.tar.gz" \
        -O "curl-${VERSION}.tar.gz"
    tar xf "curl-${VERSION}.tar.gz"
    rm "curl-${VERSION}.tar.gz"
else
    echo "[1/5] Source already present: $SRC_DIR"
fi

cd "$SRC_DIR"

# ---- Configure ----
echo "[2/5] Configuring..."
./configure \
    --with-openssl="$OPENSSL_PREFIX" \
    CFLAGS="-I$OPENSSL_PREFIX/include" \
    LDFLAGS="-L$OPENSSL_PREFIX/lib -Wl,-rpath,$OPENSSL_PREFIX/lib" \
    --disable-dependency-tracking \
    --disable-manual \
    --without-zstd \
    --without-brotli

# ---- Build ----
echo "[3/5] Building (use -j1 to avoid libtool race on old make)..."
make -j1

# ---- Backup old curl ----
echo "[4/5] Backing up system curl..."
if [[ -f /usr/bin/curl && ! -f /usr/bin/curl.7.21.bak ]]; then
    cp /usr/bin/curl /usr/bin/curl.7.21.bak
    echo "    Backed up: /usr/bin/curl → /usr/bin/curl.7.21.bak"
fi

# ---- Install ----
echo "[5/5] Installing to /usr/bin/curl ..."
cp src/curl /usr/bin/curl
chmod 755 /usr/bin/curl

echo ""
echo "=== Done ==="
echo "    Binary: /usr/bin/curl"
echo "    Backup: /usr/bin/curl.7.21.bak (Squeeze original)"
echo ""
echo "    Verify: curl --version"
curl --version | head -1
