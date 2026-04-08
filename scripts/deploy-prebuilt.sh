#!/bin/bash
# =============================================================================
# EtrayZ Deploy Script — Path A: Pre-built Rootfs
# =============================================================================
# Deploys the pre-built rootfs archive to an EtrayZ HDD connected to your PC.
#
# This script will:
#   1. Create a GPT partition table (matching original firmware layout)
#   2. Create md RAID1 arrays (metadata 0.90, required by kernel 2.6.24)
#   3. Format and populate the rootfs from the archive
#   4. Write boot files at raw sector offsets (stage1, u-boot, kernel)
#   5. Write rom_codes disk signature
#
# The data partition (sda3/XFS) is left UNFORMATTED because kernel 2.6.24
# only supports XFS v4 format. A modern mkfs.xfs creates v5 (CRC) which
# the old kernel cannot read. The NAS will format it on first boot, or you
# can format it from the running NAS with: sudo mkfs.xfs -f /dev/sda3
#
# Prerequisites:
#   sudo apt-get install mdadm parted e2fsprogs
#
# Usage:
#   sudo ./deploy-prebuilt.sh /dev/sdX
#
# WARNING: This DESTROYS all data on the specified disk!
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${CYAN}=== $* ===${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DISK="${1:-}"

# --- Validate inputs ---------------------------------------------------------

[[ -z "$DISK" ]] && error "Usage: $0 /dev/sdX"
[[ -b "$DISK" ]] || error "Not a block device: $DISK"
[[ $EUID -ne 0 ]] && error "This script must be run as root (sudo)."

# Required files
ROOTFS_ARCHIVE="${REPO_DIR}/rootfs/etrayz-rootfs.tar.xz"
BOOT_DIR="${REPO_DIR}/boot_files"
ROM_CODES="${REPO_DIR}/rom_codes"
MODULES_ARCHIVE="${REPO_DIR}/nas_files/nas_modules_fw.tar.gz"

[[ -f "$ROOTFS_ARCHIVE" ]] || error "Rootfs archive not found: $ROOTFS_ARCHIVE"
[[ -d "$BOOT_DIR" ]]       || error "Boot files directory not found: $BOOT_DIR"
[[ -f "$ROM_CODES" ]]      || error "rom_codes not found: $ROM_CODES"

for f in stage1.wrapped u-boot.wrapped uImage uImage.1 uUpgradeRootfs; do
    [[ -f "${BOOT_DIR}/$f" ]] || error "Missing boot file: ${BOOT_DIR}/$f"
done

# Required tools
for cmd in parted mdadm mkfs.ext3; do
    command -v "$cmd" >/dev/null || error "$cmd not found. Install: sudo apt-get install parted mdadm e2fsprogs"
done

# Safety: refuse to operate on system disk
ROOT_DISK=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null || echo "")
[[ -n "$ROOT_DISK" ]] && [[ "/dev/${ROOT_DISK}" == "$DISK" ]] && \
    error "Refusing to operate on system disk ${DISK}!"

# --- Show disk info and confirm ----------------------------------------------

echo ""
info "Target disk: ${DISK}"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$DISK" 2>/dev/null || true
echo ""
warn "============================================"
warn "  THIS WILL DESTROY ALL DATA ON ${DISK}"
warn "============================================"
warn ""
warn "New layout:"
warn "  ${DISK}1  ~2.0 GB  → md0 (rootfs, ext3)"
warn "  ${DISK}2  ~500 MB  → md1 (swap)"
warn "  ${DISK}3  rest     → /home (XFS, formatted by NAS)"
warn ""
read -p "Type YES to proceed: " confirm
[[ "$confirm" != "YES" ]] && error "Aborted."

# --- Helper: determine partition names (sdX1 vs sdXp1) -----------------------

find_partitions() {
    sleep 2
    partprobe "$DISK" 2>/dev/null || true
    sleep 1
    if [[ -b "${DISK}1" ]]; then
        PART1="${DISK}1"; PART2="${DISK}2"; PART3="${DISK}3"
    elif [[ -b "${DISK}p1" ]]; then
        PART1="${DISK}p1"; PART2="${DISK}p2"; PART3="${DISK}p3"
    else
        sleep 3
        partprobe "$DISK" 2>/dev/null || true
        if [[ -b "${DISK}1" ]]; then
            PART1="${DISK}1"; PART2="${DISK}2"; PART3="${DISK}3"
        else
            error "Cannot find partitions after partitioning!"
        fi
    fi
}

# --- Cleanup function --------------------------------------------------------

MNT_ROOT=""
cleanup() {
    [[ -n "$MNT_ROOT" ]] && mountpoint -q "$MNT_ROOT" && umount "$MNT_ROOT" 2>/dev/null
    [[ -n "$MNT_ROOT" ]] && rmdir "$MNT_ROOT" 2>/dev/null
    mdadm --stop /dev/md0 2>/dev/null || true
    mdadm --stop /dev/md1 2>/dev/null || true
}
trap cleanup EXIT

# =============================================================================
step "Step 1: Stop existing arrays and unmount"
# =============================================================================

for md in /dev/md*; do
    [[ -b "$md" ]] || continue
    if mdadm --detail "$md" 2>/dev/null | grep -q "${DISK}"; then
        info "Stopping $md..."
        mdadm --stop "$md" 2>/dev/null || true
    fi
done

for part in "${DISK}"[0-9]* "${DISK}p"[0-9]*; do
    [[ -b "$part" ]] && umount "$part" 2>/dev/null || true
done

for part in "${DISK}"1 "${DISK}"2 "${DISK}"3 "${DISK}p1" "${DISK}p2" "${DISK}p3"; do
    [[ -b "$part" ]] && mdadm --zero-superblock "$part" 2>/dev/null || true
done

# =============================================================================
step "Step 2: Wipe and create GPT partition table"
# =============================================================================

info "Wiping first 32 MB..."
dd if=/dev/zero of="$DISK" bs=1M count=32 status=none

info "Creating GPT partition table..."
parted -s "$DISK" mklabel gpt

# Partition sizes match original firmware installer (installglue):
#   mkpart primary 16 2064      → sda1 ~2 GB
#   mkpart primary 2064 2576    → sda2 ~500 MB
#   mkpart primary 2576 100%    → sda3 rest
parted -s "$DISK" mkpart primary 16 2064
parted -s "$DISK" set 1 raid on
parted -s "$DISK" mkpart primary 2064 2576
parted -s "$DISK" set 2 raid on
parted -s "$DISK" mkpart primary 2576 100%

find_partitions
info "Partitions: ${PART1}, ${PART2}, ${PART3}"

# =============================================================================
step "Step 3: Create md RAID1 arrays (metadata 0.90)"
# =============================================================================

# Single-disk degraded RAID1 — kernel cmdline has root=/dev/md0
info "Creating md0 (rootfs) from ${PART1}..."
mdadm --create /dev/md0 --level=1 --raid-devices=2 --force \
    --metadata=0.90 --run "$PART1" missing

info "Creating md1 (swap) from ${PART2}..."
mdadm --create /dev/md1 --level=1 --raid-devices=2 --force \
    --metadata=0.90 --run "$PART2" missing

sleep 2

# =============================================================================
step "Step 4: Format and populate rootfs"
# =============================================================================

info "Formatting md0 as ext3..."
mkfs.ext3 -q -L etrayz-root /dev/md0

MNT_ROOT=$(mktemp -d)
mount /dev/md0 "$MNT_ROOT"

info "Extracting rootfs archive (this may take a few minutes)..."
tar xJf "$ROOTFS_ARCHIVE" -C "$MNT_ROOT"

# Update mdadm.conf with new array UUIDs
mkdir -p "$MNT_ROOT/etc/mdadm"
mdadm --detail --scan > "$MNT_ROOT/etc/mdadm/mdadm.conf"

ROOTFS_USED=$(du -sh "$MNT_ROOT" | awk '{print $1}')
info "Rootfs populated: ${ROOTFS_USED}"

umount "$MNT_ROOT"
rmdir "$MNT_ROOT"
MNT_ROOT=""

# =============================================================================
step "Step 5: Create swap"
# =============================================================================

info "Formatting md1 as swap..."
mkswap -L etrayz-swap /dev/md1

# =============================================================================
step "Step 6: Write rom_codes disk signature"
# =============================================================================

info "Writing rom_codes (444 bytes at sector 0)..."
dd if="$ROM_CODES" of="$DISK" bs=444 count=1 conv=notrunc status=none

# =============================================================================
step "Step 7: Write boot files at raw sector offsets"
# =============================================================================

# These offsets are from the original installer (installglue).
# U-Boot reads the kernel from these exact sector positions.
# Boot files MUST be written AFTER parted (parted mklabel gpt overwrites sector 34).

info "Writing stage1.wrapped   → sector 34..."
dd if="${BOOT_DIR}/stage1.wrapped"   of="$DISK" bs=512 seek=34    conv=notrunc status=none
info "Writing u-boot.wrapped   → sector 36..."
dd if="${BOOT_DIR}/u-boot.wrapped"   of="$DISK" bs=512 seek=36    conv=notrunc status=none
info "Writing uImage           → sector 290..."
dd if="${BOOT_DIR}/uImage"           of="$DISK" bs=512 seek=290   conv=notrunc status=none
info "Writing uImage.1         → sector 8482..."
dd if="${BOOT_DIR}/uImage.1"         of="$DISK" bs=512 seek=8482  conv=notrunc status=none
info "Writing uUpgradeRootfs   → sector 16674..."
dd if="${BOOT_DIR}/uUpgradeRootfs"   of="$DISK" bs=512 seek=16674 conv=notrunc status=none

# Backup copies (also from installglue)
info "Writing stage1 copy      → sector 57088..."
dd if="${BOOT_DIR}/stage1.wrapped"   of="$DISK" bs=512 seek=57088 conv=notrunc status=none
info "Writing u-boot copy      → sector 57090..."
dd if="${BOOT_DIR}/u-boot.wrapped"   of="$DISK" bs=512 seek=57090 conv=notrunc status=none
info "Writing uImage copy      → sector 57344..."
dd if="${BOOT_DIR}/uImage"           of="$DISK" bs=512 seek=57344 conv=notrunc status=none

# =============================================================================
step "Step 8: Stop arrays and sync"
# =============================================================================

mdadm --stop /dev/md0
mdadm --stop /dev/md1
sync

# =============================================================================
step "DONE"
# =============================================================================

echo ""
info "============================================"
info "  DEPLOYMENT COMPLETE"
info "============================================"
info ""
info "Disk layout:"
lsblk -o NAME,SIZE,TYPE "$DISK"
info ""
info "Next steps:"
info "  1. Disconnect the HDD from this computer"
info "  2. Put it back in the EtrayZ NAS"
info "  3. Power on and wait ~3 minutes"
info "  4. Find the NAS IP in your router's DHCP leases"
info "  5. SSH in:"
info "     ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa sysadmin@<NAS_IP>"
info "     Password: etrayz"
info "  6. CHANGE THE PASSWORDS!"
info ""
warn "NOTE: The data partition (${PART3}) is not formatted."
warn "The NAS kernel will format it as XFS v4 on first use, or you can"
warn "run this on the NAS after boot: sudo mkfs.xfs -f /dev/sda3"
warn ""
warn "If the NAS doesn't boot, see HOWTO.md troubleshooting section."
