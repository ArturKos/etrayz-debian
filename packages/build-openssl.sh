#!/bin/bash
# build-openssl.sh — Build OpenSSL 1.1.1w natively on EtrayZ NAS
#
# Target:  OX810SE ARM926EJ-S 183MHz, kernel 2.6.24.4, GCC 4.4.5
# Result:  /usr/local/lib/libssl.so.1.1, /usr/local/lib/libcrypto.so.1.1
#          /usr/local/include/openssl/, /usr/local/bin/openssl
#
# NOTE: Run directly on the NAS, not in the Docker toolchain.
#       The toolchain produces binaries that segfault on this kernel.
#
# Why 1.1.1w?  OpenSSL 0.9.8o (Squeeze default) lacks TLS 1.2/1.3.
#              wget, curl, aria2 all need TLS 1.2+ for modern HTTPS.
# Why not 3.x? OpenSSL 3.x requires more memory and is untested here.
#              1.1.1w is the last LTS branch; security-wise adequate for
#              a private LAN device.
#
# Usage: bash build-openssl.sh
# Time:  ~45 minutes on 183 MHz ARM

set -e

VERSION="1.1.1w"
SRC_DIR="/home/sysadmin/openssl-${VERSION}"
PREFIX="/usr/local"

echo "=== Building OpenSSL ${VERSION} natively on EtrayZ ==="
echo "    Target: ARM926EJ-S, GCC $(gcc --version | head -1)"
echo ""

# ---- Download ----
if [[ ! -d "$SRC_DIR" ]]; then
    cd /home/sysadmin
    echo "[1/5] Downloading OpenSSL ${VERSION}..."
    wget -q "https://www.openssl.org/source/openssl-${VERSION}.tar.gz" \
        -O "openssl-${VERSION}.tar.gz"
    tar xf "openssl-${VERSION}.tar.gz"
    rm "openssl-${VERSION}.tar.gz"
else
    echo "[1/5] Source already present: $SRC_DIR"
fi

cd "$SRC_DIR"

# ---- Configure ----
echo "[2/5] Configuring..."
# linux-generic32: correct for 32-bit ARM without hardware FPU
# shared: build .so files (needed by wget, curl, aria2 at runtime)
# no-tests: skip test suite (takes forever on 183 MHz)
./Configure \
    linux-generic32 \
    shared \
    no-tests \
    --prefix="$PREFIX" \
    --openssldir="$PREFIX/etc/ssl"

# ---- Build ----
echo "[3/5] Building (this takes ~40 minutes)..."
make -j1

# ---- Install ----
echo "[4/5] Installing to $PREFIX ..."
make install_sw   # install_sw = binaries + libs + headers, skip docs/man

# ---- Ldconfig ----
echo "[5/5] Updating ld.so.cache..."
if ! grep -q "$PREFIX/lib" /etc/ld.so.conf 2>/dev/null; then
    echo "$PREFIX/lib" >> /etc/ld.so.conf
fi
ldconfig

echo ""
echo "=== Done ==="
echo "    Library: $PREFIX/lib/libssl.so.1.1"
echo "    Library: $PREFIX/lib/libcrypto.so.1.1"
echo "    Binary:  $PREFIX/bin/openssl"
echo ""
echo "    Verify: openssl version  → OpenSSL ${VERSION}"
"$PREFIX/bin/openssl" version
