#!/bin/bash
# Build the EtrayZ cross-compilation Docker image
#
# Prerequisites:
#   - Docker installed
#   - QEMU binfmt registered (for running ARM containers on x86_64)
#   - linux-2.6.24.4.tar.gz in this directory (downloaded automatically if missing)
#   - nas_modules_fw.tar.gz in this directory (copied from nas_files/)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KERNEL_URL="https://github.com/superna9999/linux/archive/refs/heads/linux-2.6.24.4.tar.gz"

echo "=== EtrayZ Toolchain Docker Build ==="
echo ""
echo "Building Debian Squeeze armel container with QEMU user-mode emulation."
echo "GCC 4.4.5 · EGLIBC 2.11.3 — matching the NAS exactly."
echo ""

# Check for kernel source
if [ ! -f "$SCRIPT_DIR/linux-2.6.24.4.tar.gz" ]; then
    echo "Downloading kernel source (58MB)..."
    echo "  From: $KERNEL_URL"
    wget -q --show-progress -O "$SCRIPT_DIR/linux-2.6.24.4.tar.gz" "$KERNEL_URL"
    echo ""
fi

# Check for kernel modules + firmware
if [ ! -f "$SCRIPT_DIR/nas_modules_fw.tar.gz" ]; then
    if [ -f "$PROJECT_DIR/nas_files/nas_modules_fw.tar.gz" ]; then
        echo "Copying kernel modules from nas_files/..."
        cp "$PROJECT_DIR/nas_files/nas_modules_fw.tar.gz" "$SCRIPT_DIR/"
    else
        echo "WARNING: nas_modules_fw.tar.gz not found. Proprietary modules won't be included."
    fi
fi

# Ensure QEMU binfmt is registered
if [ ! -f /proc/sys/fs/binfmt_misc/qemu-arm ]; then
    echo "Registering QEMU ARM binfmt handlers..."
    docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
fi

# Build the Docker image
echo "Building Docker image (this takes a few minutes on first build)..."
echo ""
docker build -t etrayz-toolchain "$SCRIPT_DIR"

echo ""
echo "=== Build complete! ==="
echo ""
echo "Usage:"
echo "  # Interactive shell:"
echo "  ./toolchain/run.sh"
echo ""
echo "  # Compile a program:"
echo "  ./toolchain/run.sh gcc -o hello hello.c"
echo ""
echo "  # Build packages (dropbear, busybox, etc.):"
echo "  ./toolchain/run.sh bash toolchain/build-packages.sh dropbear"
echo ""
echo "  # Build a kernel module:"
echo "  ./toolchain/run.sh make ARCH=arm CROSS_COMPILE='' -C /kernel M=/src modules"
echo ""
