#!/bin/bash
# build-wget.sh — Build wget 1.20.3 natively on EtrayZ NAS
#
# Target:  OX810SE ARM926EJ-S 183MHz, kernel 2.6.24.4, GCC 4.4.5
# Depends: OpenSSL 1.1.1w at /usr/local/lib/ (run build-openssl.sh first)
# Result:  /usr/bin/wget  (old wget backed up to /usr/bin/wget.1.12.bak)
#
# Why 1.20.3?  wget 1.12 (Squeeze) uses gnutls/OpenSSL 0.9.8 — TLS 1.0 only.
#              Most modern HTTPS servers reject TLS 1.0 connections.
# Why not newer? wget 1.21+ requires newer autoconf macros; 1.20.3 is the
#              last version that builds cleanly with GCC 4.4.5.
#
# Usage: bash build-wget.sh
# Time:  ~10 minutes on 183 MHz ARM

set -e

VERSION="1.20.3"
SRC_DIR="/home/sysadmin/wget-${VERSION}"
OPENSSL_PREFIX="/usr/local"

echo "=== Building wget ${VERSION} natively on EtrayZ ==="
echo ""

# Require OpenSSL 1.1.1
if [[ ! -f "$OPENSSL_PREFIX/lib/libssl.so.1.1" ]]; then
    echo "ERROR: OpenSSL 1.1.1 not found at $OPENSSL_PREFIX/lib/libssl.so.1.1"
    echo "       Run build-openssl.sh first."
    exit 1
fi

# ---- Download ----
if [[ ! -d "$SRC_DIR" ]]; then
    cd /home/sysadmin
    echo "[1/5] Downloading wget ${VERSION}..."
    wget -q "https://ftp.gnu.org/gnu/wget/wget-${VERSION}.tar.gz" \
        -O "wget-${VERSION}.tar.gz"
    tar xf "wget-${VERSION}.tar.gz"
    rm "wget-${VERSION}.tar.gz"
else
    echo "[1/5] Source already present: $SRC_DIR"
fi

cd "$SRC_DIR"

# ---- Configure ----
echo "[2/5] Configuring..."
# --disable-iri:   avoids libidn dependency (not installed on NAS)
# --disable-nls:   avoids gettext/locale machinery
# --disable-pcre:  avoids libpcre dependency
# -rpath: embed /usr/local/lib into the binary so it finds libssl.so.1.1
#         at runtime without LD_LIBRARY_PATH
./configure \
    --with-ssl=openssl \
    --with-openssl \
    CFLAGS="-I$OPENSSL_PREFIX/include" \
    LDFLAGS="-L$OPENSSL_PREFIX/lib -Wl,-rpath,$OPENSSL_PREFIX/lib" \
    --disable-iri \
    --disable-nls \
    --disable-pcre

# ---- Build ----
echo "[3/5] Building..."
make -j1

# ---- Backup old wget ----
echo "[4/5] Backing up system wget..."
if [[ -f /usr/bin/wget && ! -f /usr/bin/wget.1.12.bak ]]; then
    cp /usr/bin/wget /usr/bin/wget.1.12.bak
    echo "    Backed up: /usr/bin/wget → /usr/bin/wget.1.12.bak"
fi

# ---- Install ----
echo "[5/5] Installing to /usr/bin/wget ..."
cp src/wget /usr/bin/wget
chmod 755 /usr/bin/wget

echo ""
echo "=== Done ==="
echo "    Binary: /usr/bin/wget"
echo "    Backup: /usr/bin/wget.1.12.bak (Squeeze original)"
echo ""
echo "    Verify: wget --version"
wget --version | head -1
