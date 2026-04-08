#!/bin/bash
# Build useful software packages for EtrayZ NAS
#
# Run inside the toolchain container:
#   docker run -it -v $(pwd)/toolchain:/src etrayz-toolchain
#   bash /src/build-packages.sh [package...]
#
# Or from host:
#   ./toolchain/run.sh bash toolchain/build-packages.sh [package...]
#
# Available packages:
#   dropbear    - Lightweight SSH server/client (replaces OpenSSH 5.5)
#   zlib        - Compression library (dependency for others)
#   busybox     - Multi-tool binary with modern applets
#   nano        - Text editor (newer than Squeeze's nano 2.2)
#   htop        - Interactive process viewer
#   tmux        - Terminal multiplexer
#   all         - Build everything
#
# Output: /build/output/ (ARM binaries ready for the NAS)

set -e

BUILD_DIR="/build"
OUTPUT_DIR="/build/output"
SRC_DIR="/build/src"
JOBS=2

# Toolchain environment — native Debian Squeeze armel (GCC 4.4.5, EGLIBC 2.11.3)
export CFLAGS="-march=armv5te -mtune=arm926ej-s -msoft-float -Os"
export CXXFLAGS="$CFLAGS"

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR" "$SRC_DIR"

# =============================================================================
# Package versions - chosen for compatibility with GCC 4.2.4 + glibc 2.6.1
# =============================================================================
DROPBEAR_VER="2022.83"   # Newest working on kernel 2.6.24 (2025.89 segfaults: uses getrandom/clock_gettime features)
ZLIB_VER="1.3.1"
BUSYBOX_VER="1.36.1"
NANO_VER="2.9.8"         # Last version supporting old autotools/gcc
HTOP_VER="2.2.0"         # Last C99-compatible version (3.x needs newer)
TMUX_VER="2.6"           # Last version without too many modern dependencies

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
info() { echo -e "${YELLOW}>>>>${NC} $1"; }

# =============================================================================
download() {
    local url="$1" dest="$2"
    if [ -f "$dest" ]; then
        info "Already downloaded: $(basename "$dest")"
        return 0
    fi
    info "Downloading: $url"
    wget -q -O "$dest" "$url" || curl -sL -o "$dest" "$url" || fail "Download failed: $url"
}

# =============================================================================
build_zlib() {
    info "Building zlib $ZLIB_VER..."
    download "https://zlib.net/zlib-${ZLIB_VER}.tar.gz" "$SRC_DIR/zlib-${ZLIB_VER}.tar.gz"
    cd "$BUILD_DIR"
    rm -rf zlib-${ZLIB_VER}
    tar xzf "$SRC_DIR/zlib-${ZLIB_VER}.tar.gz"
    cd zlib-${ZLIB_VER}

    ./configure --prefix=/etrayz/usr
    make -j$JOBS
    make install

    ok "zlib $ZLIB_VER installed to /etrayz/usr"
}

# =============================================================================
build_dropbear() {
    info "Building dropbear $DROPBEAR_VER..."
    download "https://matt.ucc.asn.au/dropbear/releases/dropbear-${DROPBEAR_VER}.tar.bz2" \
             "$SRC_DIR/dropbear-${DROPBEAR_VER}.tar.bz2"
    cd "$BUILD_DIR"
    rm -rf dropbear-${DROPBEAR_VER}
    tar xjf "$SRC_DIR/dropbear-${DROPBEAR_VER}.tar.bz2"
    cd dropbear-${DROPBEAR_VER}

    # Configure: disable features that need kernel >2.6.24
    # getrandom() needs kernel 3.17 — force-disable so dropbear uses /dev/urandom instead
    ac_cv_func_getrandom=no \
    ./configure \
        --disable-zlib \
        --disable-wtmp \
        --disable-lastlog \
        --disable-pututxline \
        --prefix=/usr/local

    # Build all programs: dropbear server, dbclient, dropbearkey, dropbearconvert
    make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" \
         STATIC=1 SCPPROGRESS=1 -j$JOBS

    # Strip binaries
    strip dropbear dbclient dropbearkey dropbearconvert scp 2>/dev/null || true

    # Copy to output
    cp dropbear dbclient dropbearkey dropbearconvert scp "$OUTPUT_DIR/"

    # Create combined multi-call binary (saves space)
    make clean
    make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" \
         STATIC=1 MULTI=1 SCPPROGRESS=1 -j$JOBS || true
    if [ -f dropbearmulti ]; then
        strip dropbearmulti
        cp dropbearmulti "$OUTPUT_DIR/"
    fi

    ok "dropbear $DROPBEAR_VER → $OUTPUT_DIR/"
    ls -lh "$OUTPUT_DIR"/dropbear* "$OUTPUT_DIR"/dbclient "$OUTPUT_DIR"/scp 2>/dev/null
    file "$OUTPUT_DIR/dropbear"
}

# =============================================================================
build_busybox() {
    info "Building busybox $BUSYBOX_VER..."
    download "https://busybox.net/downloads/busybox-${BUSYBOX_VER}.tar.bz2" \
             "$SRC_DIR/busybox-${BUSYBOX_VER}.tar.bz2"
    cd "$BUILD_DIR"
    rm -rf busybox-${BUSYBOX_VER}
    tar xjf "$SRC_DIR/busybox-${BUSYBOX_VER}.tar.bz2"
    cd busybox-${BUSYBOX_VER}

    # Use default config and enable static
    make defconfig
    sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
    # Disable features that need kernel >2.6.24
    sed -i 's/CONFIG_FEATURE_INOTIFYD=y/# CONFIG_FEATURE_INOTIFYD is not set/' .config 2>/dev/null || true

    make -j$JOBS

    strip busybox
    cp busybox "$OUTPUT_DIR/"

    ok "busybox $BUSYBOX_VER → $OUTPUT_DIR/busybox"
    ls -lh "$OUTPUT_DIR/busybox"
    file "$OUTPUT_DIR/busybox"
}

# =============================================================================
build_nano() {
    info "Building nano $NANO_VER..."
    download "https://www.nano-editor.org/dist/v2.9/nano-${NANO_VER}.tar.xz" \
             "$SRC_DIR/nano-${NANO_VER}.tar.xz"
    cd "$BUILD_DIR"
    rm -rf nano-${NANO_VER}
    tar xJf "$SRC_DIR/nano-${NANO_VER}.tar.xz"
    cd nano-${NANO_VER}

    ./configure \

        --prefix=/usr/local \
        --disable-nls \
        --enable-tiny \
        --disable-browser \
        --disable-speller

    make -j$JOBS
    strip src/nano
    cp src/nano "$OUTPUT_DIR/"

    ok "nano $NANO_VER → $OUTPUT_DIR/nano"
    ls -lh "$OUTPUT_DIR/nano"
    file "$OUTPUT_DIR/nano"
}

# =============================================================================
build_htop() {
    info "Building htop $HTOP_VER..."
    download "https://github.com/htop-dev/htop/releases/download/${HTOP_VER}/htop-${HTOP_VER}.tar.gz" \
             "$SRC_DIR/htop-${HTOP_VER}.tar.gz"
    cd "$BUILD_DIR"
    rm -rf htop-${HTOP_VER}
    tar xzf "$SRC_DIR/htop-${HTOP_VER}.tar.gz"
    cd htop-${HTOP_VER}

    ./configure \

        --prefix=/usr/local \
        --disable-unicode \
        --enable-proc

    make -j$JOBS
    strip htop
    cp htop "$OUTPUT_DIR/"

    ok "htop $HTOP_VER → $OUTPUT_DIR/htop"
    ls -lh "$OUTPUT_DIR/htop"
    file "$OUTPUT_DIR/htop"
}

# =============================================================================
build_tmux() {
    info "Building tmux $TMUX_VER..."
    download "https://github.com/tmux/tmux/releases/download/${TMUX_VER}/tmux-${TMUX_VER}.tar.gz" \
             "$SRC_DIR/tmux-${TMUX_VER}.tar.gz"
    cd "$BUILD_DIR"
    rm -rf tmux-${TMUX_VER}
    tar xzf "$SRC_DIR/tmux-${TMUX_VER}.tar.gz"
    cd tmux-${TMUX_VER}

    ./configure \

        --prefix=/usr/local

    make -j$JOBS
    strip tmux
    cp tmux "$OUTPUT_DIR/"

    ok "tmux $TMUX_VER → $OUTPUT_DIR/tmux"
    ls -lh "$OUTPUT_DIR/tmux"
    file "$OUTPUT_DIR/tmux"
}

# =============================================================================
# Kernel module build helper
# =============================================================================
build_module_example() {
    info "Building example kernel module..."
    mkdir -p "$BUILD_DIR/kmod-example"
    cat > "$BUILD_DIR/kmod-example/hello.c" << 'MODEOF'
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("EtrayZ Toolchain");
MODULE_DESCRIPTION("Hello World test module for EtrayZ");

static int __init hello_init(void) {
    printk(KERN_INFO "Hello from EtrayZ kernel module!\n");
    return 0;
}

static void __exit hello_exit(void) {
    printk(KERN_INFO "Goodbye from EtrayZ kernel module!\n");
}

module_init(hello_init);
module_exit(hello_exit);
MODEOF

    cat > "$BUILD_DIR/kmod-example/Makefile" << 'MAKEEOF'
obj-m := hello.o

KDIR ?= /kernel

all:
	$(MAKE) ARCH=arm CROSS_COMPILE="" -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) ARCH=arm -C $(KDIR) M=$(PWD) clean
MAKEEOF

    cd "$BUILD_DIR/kmod-example"
    make

    if [ -f hello.ko ]; then
        cp hello.ko "$OUTPUT_DIR/"
        ok "hello.ko kernel module → $OUTPUT_DIR/hello.ko"
        modinfo hello.ko 2>/dev/null || file hello.ko
    else
        fail "Module build failed"
    fi
}

# =============================================================================
# Main
# =============================================================================

if [ $# -eq 0 ]; then
    echo "EtrayZ Package Builder"
    echo ""
    echo "Usage: $0 <package> [package...]"
    echo ""
    echo "Packages:"
    echo "  dropbear  - Lightweight SSH server/client (static, ~400KB)"
    echo "  zlib      - Compression library (needed by some packages)"
    echo "  busybox   - Multi-tool binary with modern applets"
    echo "  nano      - Text editor (newer than Squeeze's 2.2)"
    echo "  htop      - Interactive process viewer"
    echo "  tmux      - Terminal multiplexer"
    echo "  kmod      - Test kernel module (verifies module build works)"
    echo "  all       - Build everything"
    echo ""
    echo "Output directory: $OUTPUT_DIR"
    echo ""
    echo "Example:"
    echo "  $0 dropbear kmod"
    echo "  $0 all"
    exit 0
fi

PACKAGES="$@"
if echo "$PACKAGES" | grep -q "all"; then
    PACKAGES="zlib dropbear busybox nano htop tmux kmod"
fi

for pkg in $PACKAGES; do
    echo ""
    echo "================================================================"
    echo "  Building: $pkg"
    echo "================================================================"
    echo ""
    case "$pkg" in
        zlib)     build_zlib ;;
        dropbear) build_dropbear ;;
        busybox)  build_busybox ;;
        nano)     build_nano ;;
        htop)     build_htop ;;
        tmux)     build_tmux ;;
        kmod)     build_module_example ;;
        *)        echo "Unknown package: $pkg"; exit 1 ;;
    esac
done

echo ""
echo "================================================================"
echo "  Build complete! Output in $OUTPUT_DIR:"
echo "================================================================"
ls -lh "$OUTPUT_DIR/"
echo ""
echo "Deploy to NAS:"
echo "  scp $OUTPUT_DIR/<binary> sysadmin@192.168.1.234:~/"
