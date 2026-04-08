# EtrayZ Custom Firmware — Deployment Guide

Three deployment paths are available. All produce the same result: a fully configured
Debian 6 Squeeze NAS ready to boot.

---

## Path A: Restore from Disk Image (Easiest)

The disk image (`etrayz-system.img.xz`, 838 MB) contains the complete system area:
GPT partition table, boot sectors at raw offsets, md0 rootfs, and md1 swap.
Just write it to the disk — no partitioning or manual boot file placement needed.

### Prerequisites

```bash
sudo apt-get install xz-utils gdisk xfsprogs    # Debian/Ubuntu
sudo pacman -S xz gdisk xfsprogs                # Arch
sudo dnf install xz gdisk xfsprogs              # Fedora
```

### Steps

1. **Remove the HDD** from the EtrayZ NAS.

2. **Connect the HDD** to your PC via USB-to-SATA adapter.

3. **Download** `etrayz-system.img.xz` from Google Drive.

4. **Run the restore script:**
   ```bash
   cd XtreamerEtrayZ
   sudo bash scripts/restore-from-image.sh etrayz-system.img.xz /dev/sdX
   ```
   The script will:
   - Write the full image (GPT + boot sectors + md0 + md1) via `dd`
   - Create a fresh XFS `/home` partition (sda3) filling the rest of the disk

5. **Disconnect the HDD** and put it back in the NAS.

6. **Power on** and wait ~3 minutes for boot.

7. **Find the NAS IP** in your router's DHCP lease table.

---

## Path B: Deploy Pre-built Rootfs

Use the ready-made rootfs archive included in this repository. This is the fastest
way — no compilation, no internet required during deployment.

### Prerequisites

A Linux PC (Debian, Ubuntu, Fedora, Arch, etc.) with:

```bash
sudo apt-get install mdadm parted e2fsprogs      # Debian/Ubuntu
sudo pacman -S mdadm parted e2fsprogs             # Arch
sudo dnf install mdadm parted e2fsprogs           # Fedora
```

A USB-to-SATA adapter or internal SATA port to connect the EtrayZ HDD.

### Steps

1. **Remove the HDD** from the EtrayZ NAS (slide out the drive bay).

2. **Connect the HDD** to your PC via USB-to-SATA adapter.

3. **Download** `etrayz-rootfs.tar.xz` from Google Drive and place it in `rootfs/`.

4. **Identify the device** — run `lsblk` and find the EtrayZ disk (e.g., `/dev/sdc`).
   **Double-check!** Using the wrong device will destroy data.

5. **Run the deploy script:**
   ```bash
   cd XtreamerEtrayZ
   sudo ./scripts/deploy-prebuilt.sh /dev/sdX
   ```
   The script will:
   - Create a GPT partition table matching the original layout
   - Create md0 (rootfs) and md1 (swap) RAID arrays
   - Extract the Debian rootfs to md0
   - Write bootloader and kernel at raw sector offsets
   - Write the rom_codes disk signature

6. **Disconnect the HDD** and put it back in the NAS.

7. **Power on** and wait ~3 minutes for boot.

8. **Find the NAS IP** in your router's DHCP lease table.

9. **SSH in:**
   ```bash
   ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa sysadmin@<IP>
   # Password: etrayz
   ```

10. **Format the data partition** (XFS, must be done from the NAS kernel):
   ```bash
   sudo mkfs.xfs -f /dev/sda3
   sudo mount /dev/sda3 /home
   sudo mkdir -p /home/{public,downloads/{complete,incomplete,watch},sysadmin}
   sudo chown -R sysadmin:sysadmin /home/downloads /home/public /home/sysadmin
   ```

11. **Change the default passwords:**
    ```bash
    passwd
    sudo passwd root
    ```

### What the deploy script does NOT do

- **Format /dev/sda3 (XFS data partition):** The NAS kernel 2.6.24 only supports XFS v4
  format. A modern PC's `mkfs.xfs` creates v5 (CRC) which the old kernel cannot read.
  You must format this partition from the running NAS.

- **Set your specific IP:** The NAS uses DHCP by default. To set a static IP, edit
  `/etc/network/interfaces` on the rootfs after deployment.

---

## Path C: Build from Scratch

Build the entire rootfs yourself. This gives you full control over what's installed
and how it's configured. You do NOT need a running EtrayZ NAS — all proprietary
kernel modules and firmware are included in the `nas_files/` directory.

### Prerequisites

A Debian/Ubuntu x86_64 PC with:

```bash
sudo apt-get install debootstrap qemu-user-static binfmt-support mdadm parted e2fsprogs
```

The `qemu-user-static` + `binfmt-support` packages allow running ARM binaries on your
x86_64 system, which is how debootstrap installs packages for the armel architecture.

### Steps

1. **Build the rootfs:**
   ```bash
   cd XtreamerEtrayZ
   sudo ./scripts/build-from-scratch.sh
   ```
   This will:
   - Run debootstrap to create a Debian 6 Squeeze armel base
   - Install all packages (SSH, Samba, Transmission, lighttpd, monit, etc.)
   - Install kernel modules and firmware from `nas_files/nas_modules_fw.tar.gz`
   - Create static `/dev` nodes (no udev on kernel 2.6.24)
   - Configure all services, users, network, dashboard
   - Output `rootfs/etrayz-rootfs.tar.xz`

   Build time: ~15-30 minutes (ARM emulation via QEMU is slow).

2. **Deploy to HDD** using the same deploy script from Path B:
   ```bash
   sudo ./scripts/deploy-prebuilt.sh /dev/sdX
   ```

3. Follow steps 5-10 from Path B above.

### Customizing the build

The build script is well-commented. Common modifications:

- **Change packages:** Edit the `apt-get install` line in the script
- **Change hostname:** Edit the hostname section
- **Change default passwords:** Edit the chpasswd lines
- **Change MAC address:** Edit `/etc/network/interfaces` hwaddress line
- **Add SSH keys:** Copy to `${ROOTFS}/home/sysadmin/.ssh/authorized_keys`

### Rebuilding

To rebuild from scratch (e.g., after modifying the script):
```bash
sudo rm -rf build/rootfs
sudo ./scripts/build-from-scratch.sh
```

To rebuild without repeating debootstrap (just reconfigure):
```bash
# The script detects existing rootfs and skips debootstrap
sudo ./scripts/build-from-scratch.sh
```

---

## Disk Layout Details

The EtrayZ boot chain reads the kernel from **raw sector offsets** on the disk,
not from a filesystem. This layout must be exact:

```
Sector    Content                Size
0         rom_codes signature    444 bytes
1-33      GPT header + entries   16.5 KB
34        stage1.wrapped         456 bytes
36        u-boot.wrapped         111 KB
290       uImage (kernel)        1.9 MB
8482      uImage.1 (backup)      948 KB
16674     uUpgradeRootfs         247 KB
32768+    Partition 1 starts     (sda1 at 16 MB)
57088     stage1 (copy 2)        456 bytes
57090     u-boot (copy 2)        111 KB
57344     uImage (copy 3)        1.9 MB
```

### Critical ordering rule

**Boot files MUST be written AFTER `parted mklabel gpt`.**

The `parted mklabel gpt` command writes GPT structures at sectors 0-33 and at the
end of the disk. `stage1.wrapped` is at sector 34, which is inside the GPT partition
entry area. If you run parted AFTER writing boot files, it will overwrite stage1 and
the NAS will not boot.

The deploy script handles this correctly (partition first, then write boot files).

### Partition table

```
Partition   Start    End      Size     Type    Use
sda1        16 MB    2064 MB  ~2 GB    RAID    md0 → ext3 rootfs
sda2        2064 MB  2576 MB  ~500 MB  RAID    md1 → swap
sda3        2576 MB  end      rest     plain   XFS /home (data)
```

These sizes match the original firmware installer (`installglue`). The md arrays use
metadata version 0.90 for compatibility with kernel 2.6.24.

---

## Troubleshooting

### NAS doesn't boot (no ping, no SSH)

1. **Wait at least 3 minutes.** The 183 MHz ARM CPU is slow to boot.
2. **Check boot files were written correctly:**
   ```bash
   # Verify stage1 exists at sector 34
   sudo dd if=/dev/sdX bs=512 skip=34 count=1 2>/dev/null | xxd | head -3
   # Should show data, not all zeros
   ```
3. **Check partition table is GPT:**
   ```bash
   sudo parted /dev/sdX print
   ```
4. **Common cause:** Boot files written BEFORE parted. Re-run the deploy script.

### NAS boots but no network

- The GMAC driver needs `/sbin/hotplug` to load CoPro firmware
- Check `/var/log/bootdebug.log` (pull HDD, mount md0, read the log)
- Verify `/sbin/hotplug` exists and is executable
- Verify `/lib/firmware/gmac_copro_firmware` exists

### SSH: "no matching host key type found"

Modern SSH disables legacy RSA. Use:
```bash
ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa sysadmin@<IP>
```

### XFS: wrong fs type or bad superblock

The NAS kernel only supports XFS v4. Modern `mkfs.xfs` creates v5 (CRC format).
Format from the NAS: `sudo mkfs.xfs -f /dev/sda3`

### DHCP not getting an IP

- Check MAC address is set: `ip link show eth0`
- Should be `00:1c:85:20:4e:45` (set in `/etc/network/interfaces`)
- The GMAC driver defaults to `00:30:e0:00:00:00` without the hwaddress setting
- Fallback: the `fixnet` init script tries static IP `192.168.1.234/24`

### Rootfs corrupt / fsck fails

Pull the HDD and run on your PC:
```bash
sudo mdadm --assemble /dev/md0 /dev/sdX1
sudo fsck.ext3 -y /dev/md0
sudo mdadm --stop /dev/md0
```

---

## After First Boot

### Services overview

| Service        | Port  | Auto-start | Monitor |
|----------------|-------|------------|---------|
| SSH            | 22    | Yes        | monit   |
| Samba          | 445   | Yes        | monit   |
| Transmission   | 9091  | Yes        | monit   |
| lighttpd       | 80    | Yes        | monit   |
| monit          | 2812  | Yes        | —       |

### Useful commands

```bash
# Check service status
sudo monit status

# View boot log
cat /var/log/bootdebug.log

# Check disk health
sudo smartctl -d sat -a /dev/sda

# Check RAID status
cat /proc/mdstat

# Update packages (archived, no new versions)
sudo apt-get update
sudo apt-get install <package>
```

### Adding packages

Debian Squeeze is EOL — all archive signing keys have expired. `apt-get update` always
shows a `W: GPG error: NO_PUBKEY` warning but this is harmless and does **not** block installs.

The fix is already applied in `/etc/apt/apt.conf.d/99ignore-expiry`:
```
Acquire::Check-Valid-Until "false";
APT::Get::AllowUnauthenticated "true";
```

Installing packages works normally:
```bash
sudo apt-get update          # W: GPG warning is expected, ignore it
sudo apt-get install <package-name>
```

To suppress the warning in scripts:
```bash
sudo apt-get update 2>&1 | grep -v "^W:"
```

Most packages from the Squeeze archive are still downloadable from archive.debian.org.

---

## Compiling Software for the NAS

### Native Compilation (Recommended)

The NAS has **GCC 4.4.5** installed. For packages that need to run on the NAS,
compile directly on the NAS itself. Cross-compilation via Docker produces binaries
that segfault due to glibc version mismatches and missing kernel syscalls.

**Key constraints:**
- GCC 4.4.5 — C++98/C++0x only; `nullptr` requires GCC 4.6+ (breaks aria2 1.21+)
- Kernel 2.6.24 — missing `eventfd(EFD_NONBLOCK)`, `getrandom()`, `accept4()` (added in 2.6.27/3.17)
- OpenSSL 1.1.1w installed at `/usr/local/lib/`, use `-Wl,-rpath,/usr/local/lib`
- Set `TMPDIR=/home/sysadmin/tmp` (avoids 256MB /tmp filling during builds)
- Use `make -j1` and `--disable-dependency-tracking` to avoid libtool race conditions

**Standard build procedure:**
```bash
# Transfer source
scp package-1.0.tar.gz sysadmin@<NAS_IP>:~/

# SSH in and build
ssh sysadmin@<NAS_IP>
mkdir -p ~/tmp
tar xf package-1.0.tar.gz && cd package-1.0
TMPDIR=/home/sysadmin/tmp \
PKG_CONFIG_PATH=/usr/local/lib/pkgconfig \
CFLAGS="-march=armv5te -mtune=arm926ej-s -msoft-float -Os" \
LDFLAGS="-L/usr/local/lib -Wl,-rpath,/usr/local/lib" \
./configure --prefix=/usr/local --disable-dependency-tracking
make -j1 && sudo make install
```

**Packages already compiled natively (on the NAS):**

| Package  | Version | Notes |
|----------|---------|-------|
| OpenSSL  | 1.1.1w  | Shared libs at `/usr/local/lib/` |
| wget     | 1.20.3  | `--disable-iri --disable-nls` |
| curl     | 7.88.1  | Last 7.x — curl 8.x uses `eventfd` flags requiring kernel 2.6.27+ |
| aria2    | 1.15.1  | Needs `EVP_MD_CTX` pointer patch for OpenSSL 1.1.x (see below) |
| Dropbear | 2025.89 | Configure fix: `ac_cv_func_getrandom=no ac_cv_func_getentropy=no` |

**aria2 1.15.1 patch for OpenSSL 1.1.x** (`EVP_MD_CTX` became opaque):

`src/LibsslMessageDigestImpl.h`: change `EVP_MD_CTX ctx_` → `EVP_MD_CTX* ctx_`

`src/LibsslMessageDigestImpl.cc`:
- `EVP_MD_CTX_init(&ctx_)` → `ctx_ = EVP_MD_CTX_new()`
- `EVP_MD_CTX_cleanup(&ctx_)` → `EVP_MD_CTX_free(ctx_)`
- All `EVP_Digest*(&ctx_, ...)` → `EVP_Digest*(ctx_, ...)`

### Docker Toolchain (Kernel Modules Only)

The `toolchain/` directory contains a Docker environment using the original
firmware's GCC 4.2.4 under QEMU. **Only reliable for kernel modules** — userspace
binaries segfault on the NAS due to glibc version mismatch.

```bash
./toolchain/build.sh     # build Docker image (~1 min)
./toolchain/run.sh       # interactive shell

# Inside container — build a kernel module:
cd /src/mymodule && etrayz-run make
strings mymodule.ko | grep vermagic
# Must match: vermagic=2.6.24.4 mod_unload ARMv5

scp mymodule.ko sysadmin@<NAS_IP>:~/
ssh sysadmin@<NAS_IP> 'sudo insmod ~/mymodule.ko'
```

**Compiler flags:** `-march=armv5te -mtune=arm926ej-s -msoft-float`

### Prerequisites (Docker toolchain)

```bash
sudo apt-get install docker.io
sudo usermod -aG docker $USER
# Log out and back in
```

`hdd.bin` (from Google Drive `original_firmware/`) must be present at:
`etrayz/etrayz_1.0.4-official_installer/hdd.bin`

### Building the Toolchain Image

```bash
cd XtreamerEtrayZ
./toolchain/build.sh
```

This extracts the ARM toolchain from the original firmware into a Docker image
(`etrayz-toolchain`). The build takes ~1 minute and the resulting image is ~1.2 GB.

The script handles:
- Copying `hdd.bin` to the build context (cleaned up after build)
- Registering QEMU ARM binfmt handlers (if not already done)
- Building the Docker image

### What Software Can Run on the NAS?

| Software        | Status    | Notes                                           |
|-----------------|-----------|-------------------------------------------------|
| SQLite 3.7      | apt-get   | `apt-get install sqlite3`                       |
| PHP 5.3         | apt-get   | `apt-get install php5-cgi` — works with lighttpd|
| Python 2.6      | apt-get   | `apt-get install python`                        |
| MySQL 5.1       | apt-get   | Heavy for 128MB RAM, but installable            |
| Lua 5.1         | apt-get   | `apt-get install lua5.1`                        |
| Python 3.x      | **No**    | Needs kernel 2.6.32+, glibc 2.17+              |
| PHP 7/8         | **No**    | Needs glibc 2.17+                               |
| Node.js         | **No**    | Needs kernel 3.x+                              |
| Go/Rust binaries| **No**    | Runtime needs kernel 2.6.32+                    |
| Transmission 3+ | **No**    | Needs C++17 (GCC 7+)                           |

### Docker Troubleshooting

**"exec format error":** QEMU binfmt not registered:
```bash
sudo docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
```

**Kernel module refuses to load:** Check vermagic must be exactly `2.6.24.4 mod_unload ARMv5`.
