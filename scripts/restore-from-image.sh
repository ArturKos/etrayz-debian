#!/bin/bash
# restore-from-image.sh — Restore EtrayZ system to a disk from etrayz-system.img.xz
#
# The image contains (sectors 0 to 5031935, ~2.4GB):
#   - GPT partition table
#   - Boot files at raw sector offsets (stage1, u-boot, kernel, etc.)
#   - sda1: md0 ext3 rootfs (~1.9GB)
#   - sda2: md1 swap (~489MB)
#
# sda3 (XFS /home) is NOT in the image — it is created fresh to fill the rest of the disk.
#
# Usage: sudo bash restore-from-image.sh <image.img.xz> <disk>
# Example: sudo bash restore-from-image.sh etrayz-system.img.xz /dev/sdb
#
# WARNING: This will DESTROY ALL DATA on the target disk.

set -e

IMAGE="$1"
DISK="$2"

if [[ -z "$IMAGE" || -z "$DISK" ]]; then
    echo "Usage: sudo bash $0 <image.img.xz> <disk>"
    echo "Example: sudo bash $0 etrayz-system.img.xz /dev/sdb"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Must run as root (sudo)"
    exit 1
fi

if [[ ! -f "$IMAGE" ]]; then
    echo "ERROR: Image file not found: $IMAGE"
    exit 1
fi

if [[ ! -b "$DISK" ]]; then
    echo "ERROR: Target disk not found: $DISK"
    exit 1
fi

DISK_SIZE=$(blockdev --getsize64 "$DISK")
DISK_GB=$((DISK_SIZE / 1024 / 1024 / 1024))

echo "============================================"
echo "  EtrayZ Disk Restore"
echo "============================================"
echo "  Image : $IMAGE"
echo "  Target: $DISK ($DISK_GB GB)"
echo ""
echo "  WARNING: ALL DATA ON $DISK WILL BE ERASED!"
echo "============================================"
read -p "Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 1; }

echo ""
echo "[1/4] Stopping any active md arrays on $DISK..."
for part in ${DISK}1 ${DISK}2 ${DISK}3; do
    mdadm --zero-superblock "$part" 2>/dev/null || true
done
mdadm --stop /dev/md0 2>/dev/null || true
mdadm --stop /dev/md1 2>/dev/null || true

echo "[2/4] Writing image to $DISK (this takes ~2 minutes)..."
xzcat "$IMAGE" | dd of="$DISK" bs=4M status=progress conv=fsync
echo "Image written."

echo "[3/4] Re-reading partition table..."
partprobe "$DISK" || blockdev --rereadpt "$DISK"
sleep 2

echo "[4/4] Creating /home partition (sda3) on remaining space..."
# sdb2 ends at sector 5031935, sdb3 starts at 5031936
# Use sgdisk to add partition 3 filling the rest of the disk
sgdisk -n 3:5031936:0 -t 3:8300 -c 3:"home" "$DISK"
partprobe "$DISK" || blockdev --rereadpt "$DISK"
sleep 2

echo ""
echo "Formatting ${DISK}3 as XFS (/home)..."
mkfs.xfs -f "${DISK}3"

echo ""
echo "============================================"
echo "  Restore complete!"
echo ""
echo "  The disk is ready to be installed in the EtrayZ."
echo "  On first boot, /home will be mounted from ${DISK}3."
echo ""
echo "  Boot files are at the correct raw sector offsets."
echo "  GPT, md0 (rootfs) and md1 (swap) are restored."
echo "============================================"
