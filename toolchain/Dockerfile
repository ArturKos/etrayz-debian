# EtrayZ Cross-Compilation Toolchain
#
# Uses Debian Squeeze armel via debootstrap + QEMU user-mode emulation.
# Matching the NAS exactly: GCC 4.4.5 · EGLIBC 2.11.3 · Binutils 2.20
#
# Binaries built here run directly on the NAS — no ABI mismatch.
# Kernel 2.6.24.4 source included for module building.
#
# Prerequisites:
#   - linux-2.6.24.4.tar.gz in this directory
#     (download from: https://github.com/superna9999/linux/archive/refs/heads/linux-2.6.24.4.tar.gz)
#   - QEMU binfmt registered:
#     docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
#
# Usage:
#   cd toolchain && ./build.sh
#   ./run.sh                        # interactive shell
#   ./run.sh gcc -o hello hello.c   # compile a program

# --- Stage 1: Build ARM Squeeze rootfs via debootstrap ---
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    debootstrap qemu-user-static binfmt-support \
    && rm -rf /var/lib/apt/lists/*

# Create ARM Squeeze rootfs
RUN debootstrap --arch=armel --foreign --no-check-gpg \
        squeeze /squeeze http://archive.debian.org/debian && \
    cp /usr/bin/qemu-arm-static /squeeze/usr/bin/ && \
    chroot /squeeze /debootstrap/debootstrap --second-stage

# Configure repos and install build tools
RUN echo "deb http://archive.debian.org/debian squeeze main" > /squeeze/etc/apt/sources.list && \
    echo 'Acquire::Check-Valid-Until "false";' > /squeeze/etc/apt/apt.conf.d/10archive && \
    chroot /squeeze apt-get update && \
    chroot /squeeze apt-get install -y --force-yes --no-install-recommends \
        gcc g++ make autoconf automake libtool pkg-config \
        bzip2 xz-utils patch bc wget curl \
        libc6-dev linux-libc-dev \
        libncurses5-dev libssl-dev \
    && rm -rf /squeeze/var/lib/apt/lists/*

# Extract kernel source (local copy, no git clone needed)
COPY linux-2.6.24.4.tar.gz /squeeze/tmp/
RUN cd /squeeze && \
    tar xzf tmp/linux-2.6.24.4.tar.gz -C / && \
    mv /linux-linux-2.6.24.4 /squeeze/kernel && \
    rm /squeeze/tmp/linux-2.6.24.4.tar.gz

# Configure kernel for module building
RUN cd /squeeze/kernel && \
    cp arch/arm/configs/oxnas_810_eabi_wd_prod_defconfig .config && \
    sed -i 's/CONFIG_LOCALVERSION_AUTO=y/# CONFIG_LOCALVERSION_AUTO is not set/' .config && \
    chroot /squeeze sh -c 'cd /kernel && yes "" | make ARCH=arm CROSS_COMPILE="" oldconfig' && \
    chroot /squeeze sh -c 'cd /kernel && make ARCH=arm CROSS_COMPILE="" modules_prepare' && \
    touch /squeeze/kernel/Module.symvers && \
    mkdir -p /squeeze/lib/modules/2.6.24.4 && \
    ln -sf /kernel /squeeze/lib/modules/2.6.24.4/build && \
    ln -sf /kernel /squeeze/lib/modules/2.6.24.4/source

# Install proprietary kernel modules and firmware blobs from original NAS
COPY nas_modules_fw.tar.gz /squeeze/tmp/
RUN tar xzf /squeeze/tmp/nas_modules_fw.tar.gz -C /squeeze/ && \
    rm /squeeze/tmp/nas_modules_fw.tar.gz

# --- Stage 2: Final image ---
FROM scratch
COPY --from=builder /squeeze /
COPY --from=builder /usr/bin/qemu-arm-static /usr/bin/qemu-arm-static

# Environment
ENV CFLAGS="-march=armv5te -mtune=arm926ej-s -msoft-float -Os"
ENV CXXFLAGS="-march=armv5te -mtune=arm926ej-s -msoft-float -Os"

# Shell profile
COPY etrayz-toolchain.sh /etc/profile.d/etrayz-toolchain.sh

WORKDIR /src
CMD ["/bin/bash", "--login"]
