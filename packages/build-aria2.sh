#!/bin/bash
# build-aria2.sh — Build aria2 1.15.1 natively on EtrayZ NAS
#
# Target:  OX810SE ARM926EJ-S 183MHz, kernel 2.6.24.4, GCC 4.4.5
# Depends: OpenSSL 1.1.1w at /usr/local/lib/ (run build-openssl.sh first)
# Result:  /usr/bin/aria2c  (old aria2c backed up to /usr/bin/aria2c.1.10.bak)
#
# Why 1.15.1?  aria2 1.10.0 (Squeeze) has XML-RPC issues and no HTTPS on
#              modern servers. 1.15.1 fixes these and works with OpenSSL 1.1.1w.
# Why not newer? aria2 1.21+ requires C++11 features not supported by GCC 4.4.5.
#              1.15.1 is the last version buildable with GCC 4.4.5 and C++03.
#
# REQUIRED PATCH: OpenSSL 1.1.x made EVP_MD_CTX an opaque type (it was a
# plain struct in 0.9.x/1.0.x). aria2 1.15.1 stores it by value in a class
# member — this no longer compiles. The patch below:
#   - Changes `EVP_MD_CTX ctx_` → `EVP_MD_CTX* ctx_` in the header
#   - Changes EVP_MD_CTX_init/cleanup to EVP_MD_CTX_new/free in the .cc
#   - Removes `&` from all ctx_ references in EVP function calls
#
# Config change (1.10.x → 1.15.x option rename):
#   enable-xml-rpc  → enable-rpc
#   xml-rpc-listen-port → rpc-listen-port
#   xml-rpc-listen-all  → rpc-listen-all
#
# Usage: bash build-aria2.sh
# Time:  ~30 minutes on 183 MHz ARM

set -e

VERSION="1.15.1"
SRC_DIR="/home/sysadmin/aria2-${VERSION}"
OPENSSL_PREFIX="/usr/local"

echo "=== Building aria2 ${VERSION} natively on EtrayZ ==="
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
    echo "[1/6] Downloading aria2 ${VERSION}..."
    wget -q "https://github.com/aria2/aria2/releases/download/release-${VERSION}/aria2-${VERSION}.tar.bz2" \
        -O "aria2-${VERSION}.tar.bz2"
    tar xf "aria2-${VERSION}.tar.bz2"
    rm "aria2-${VERSION}.tar.bz2"
else
    echo "[1/6] Source already present: $SRC_DIR"
fi

cd "$SRC_DIR"

# ---- Apply OpenSSL 1.1.x patch ----
echo "[2/6] Patching EVP_MD_CTX for OpenSSL 1.1.x..."
H_FILE="src/LibsslMessageDigestImpl.h"
CC_FILE="src/LibsslMessageDigestImpl.cc"

# Header: change value member to pointer
if grep -q "EVP_MD_CTX ctx_;" "$H_FILE"; then
    sed -i 's/EVP_MD_CTX ctx_;/EVP_MD_CTX* ctx_;/' "$H_FILE"
    echo "    Patched $H_FILE: EVP_MD_CTX ctx_ → EVP_MD_CTX* ctx_"
else
    echo "    $H_FILE already patched or unexpected content — skipping"
fi

# Implementation: replace init/cleanup with new/free, remove & from ctx_ refs
if grep -q "EVP_MD_CTX_init" "$CC_FILE"; then
    # EVP_MD_CTX_init(&ctx_) → ctx_ = EVP_MD_CTX_new()
    sed -i 's/EVP_MD_CTX_init(&ctx_);/ctx_ = EVP_MD_CTX_new();/' "$CC_FILE"
    # EVP_MD_CTX_cleanup(&ctx_) → EVP_MD_CTX_free(ctx_)
    sed -i 's/EVP_MD_CTX_cleanup(&ctx_);/EVP_MD_CTX_free(ctx_);/' "$CC_FILE"
    # EVP_DigestInit_ex(&ctx_, ...) → EVP_DigestInit_ex(ctx_, ...)
    sed -i 's/EVP_DigestInit_ex(&ctx_,/EVP_DigestInit_ex(ctx_,/g' "$CC_FILE"
    # EVP_DigestUpdate(&ctx_, ...) → EVP_DigestUpdate(ctx_, ...)
    sed -i 's/EVP_DigestUpdate(&ctx_,/EVP_DigestUpdate(ctx_,/g' "$CC_FILE"
    # EVP_DigestFinal_ex(&ctx_, ...) → EVP_DigestFinal_ex(ctx_, ...)
    sed -i 's/EVP_DigestFinal_ex(&ctx_,/EVP_DigestFinal_ex(ctx_,/g' "$CC_FILE"
    echo "    Patched $CC_FILE: EVP_MD_CTX init/cleanup/digest functions"
else
    echo "    $CC_FILE already patched or unexpected content — skipping"
fi

# ---- Configure ----
echo "[3/6] Configuring..."
./configure \
    --with-openssl \
    CXXFLAGS="-I$OPENSSL_PREFIX/include" \
    LDFLAGS="-L$OPENSSL_PREFIX/lib -Wl,-rpath,$OPENSSL_PREFIX/lib" \
    --with-libcares \
    --with-libxml2 \
    --enable-bittorrent \
    --enable-metalink \
    --enable-websocket

# ---- Build ----
echo "[4/6] Building (this takes ~25 minutes)..."
make -j1

# ---- Backup old aria2c ----
echo "[5/6] Backing up system aria2c..."
if [[ -f /usr/bin/aria2c && ! -f /usr/bin/aria2c.1.10.bak ]]; then
    cp /usr/bin/aria2c /usr/bin/aria2c.1.10.bak
    echo "    Backed up: /usr/bin/aria2c → /usr/bin/aria2c.1.10.bak"
fi

# ---- Install ----
echo "[6/6] Installing..."
# Stop running instance first (can't replace a running binary)
if pgrep aria2c > /dev/null; then
    echo "    Stopping running aria2c..."
    killall aria2c || true
    sleep 1
fi
cp src/aria2c /usr/bin/aria2c
chmod 755 /usr/bin/aria2c

# ---- Fix config option names (1.10.x → 1.15.x rename) ----
CONF="/etc/aria2/aria2.conf"
if [[ -f "$CONF" ]]; then
    echo ""
    echo "    Updating $CONF option names (xml-rpc-* → rpc-*)..."
    sed -i \
        -e 's/^enable-xml-rpc=/enable-rpc=/' \
        -e 's/^xml-rpc-listen-port=/rpc-listen-port=/' \
        -e 's/^xml-rpc-listen-all=/rpc-listen-all=/' \
        "$CONF"
fi

echo ""
echo "=== Done ==="
echo "    Binary: /usr/bin/aria2c"
echo "    Backup: /usr/bin/aria2c.1.10.bak (Squeeze original)"
echo "    Config: $CONF (option names updated)"
echo ""
echo "    Start:  sudo service aria2 start"
echo "    Verify: aria2c --version"
aria2c --version | head -1
