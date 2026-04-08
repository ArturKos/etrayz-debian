```
     _____ _____                 _____
    |   __|_   _|___ ___ _ _ __|   __|
    |   __| | | |  _| .'| | |- _|   __|
    |_____| |_| |_| |__,|_  |___|_____|
                         |___|

    ╔═══════════════════════════════════════════╗
    ║  XTREAMER ETRAYZ NAS — CUSTOM FIRMWARE    ║
    ║  Debian 6 Squeeze · ARM926EJ-S · OX810SE  ║
    ╚═══════════════════════════════════════════╝
```

# Xtreamer EtrayZ — Custom Debian Firmware

A custom **Debian 6 (Squeeze) armel** firmware for the **Xtreamer EtrayZ** single-bay NAS,
replacing the original 2009 Gentoo-based system with a modern, configurable Linux userspace
while keeping the original kernel and proprietary hardware drivers.

> **This project gives new life to abandoned hardware.** The EtrayZ was discontinued around
> 2011 with no firmware updates since. The original web UI uses bcompiler-encoded PHP that
> cannot be modified. This firmware replaces everything except the kernel with a clean
> Debian installation — SSH, Samba, Transmission, MiniDLNA, aria2, a live web dashboard
> with file manager and photo gallery, and full `apt-get` package management.

![EtrayZ Dashboard](screenshots/screenshot_dashboard.png)

![Settings Panel](screenshots/screenshot_settings.png)

![Personal Website](screenshots/screenshot_website.png)

![Web Terminal](screenshots/screenshot_webssh.png)



---

## ⚠ Security Warning

> **DO NOT expose this NAS directly to the internet.**
>
> The Linux 2.6.24 kernel (January 2009) contains **hundreds of known, unpatched CVEs**
> including privilege escalation, remote code execution, and information disclosure
> vulnerabilities. No kernel source code is available for the OX810SE platform, so these
> **cannot be fixed**.
>
> The Debian Squeeze userspace is also end-of-life (archived since 2016).
>
> **This device is safe for use on a trusted home LAN behind a NAT router.** Do not
> port-forward any services to it. If you need remote access, use a VPN on your router.

---

## Hardware

| Component       | Details                                              |
|-----------------|------------------------------------------------------|
| **Model**       | Xtreamer EtrayZ (XT-U33502)                          |
| **SoC**         | Oxford Semiconductor OX810SE                         |
| **CPU**         | ARM926EJ-S (ARMv5TEJ), single core, 183 MHz, no FPU |
| **RAM**         | 128 MB DDR (~123 MB usable)                          |
| **Storage**     | 1x SATA bay (ships with WD5002ABYS 500 GB)          |
| **Flash**       | 4 MB NOR (U-Boot bootloader — do not touch)          |
| **Ethernet**    | Gigabit (GMAC with dedicated coprocessor)            |
| **USB**         | 1x USB 2.0 (EHCI)                                   |
| **Fan**         | 40 mm, GPIO-controlled (thermAndFan kernel driver)   |
| **Serial**      | UART ttyS0 @ 115200 baud (internal header)           |
| **Power**       | External 12V DC adapter                              |

---

## Original Firmware

The factory firmware (version 1.0.4, February 2010) is **Gentoo Linux**-based:

- **Kernel:** Linux 2.6.24.4 (custom build by Macpower/PLX for OX810SE)
- **Userspace:** BusyBox + Gentoo portage layout + custom daemons
- **Web UI:** Apache + PHP 5 with bcompiler-encoded `.phb` files (cannot be modified)
- **Services:** Samba 3.x, ProFTPD, NFS, OpenSSH 5.x, rtorrent, mt-daapd, ushare
- **Init:** sysvinit with Red Hat-style rc.d scripts
- **Authentication:** SSH key-only (no password auth), custom web UI auth

The original firmware and installer are preserved in the `original_firmware/` directory.

---

## Why Not a Newer Kernel?

The OX810SE SoC requires **proprietary binary kernel modules** for critical hardware:

| Driver                | Function              | Source Available? |
|-----------------------|-----------------------|-------------------|
| `gmac.ko`            | Gigabit Ethernet      | No                |
| `gmac_copro_firmware` | Ethernet coprocessor  | No                |
| `ehci-hcd.ko`        | USB 2.0 host          | No (custom OXNAs) |
| `ox810sata`          | SATA controller       | No (built into kernel) |
| `thermAndFan`        | Fan/thermal control   | No (built into kernel) |

These modules are compiled for **kernel 2.6.24.4 only**. Loading them on any other kernel
version will fail. While open-source OX810SE kernel trees exist
([oxnas-oss/linux-oxnas](https://github.com/oxnas-oss/linux-oxnas)), building a working
kernel with SATA + Ethernet + fan control from source is a significant undertaking that
has not been completed.

**The kernel works. The userspace was the problem. We replaced the userspace.**

---

## What's Installed

### System
- Debian 6.0 Squeeze armel (glibc 2.11, compatible with kernel 2.6.24)
- sysvinit (systemd requires kernel 3.13+)
- Static `/dev` nodes (udev requires kernel 2.6.26+)
- `/sbin/hotplug` firmware helper (loads GMAC coprocessor firmware)
- `apt-get` package management (from `archive.debian.org`)

### Installed Packages
Beyond the core services, the firmware includes these tools:

| Package        | Purpose                                        |
|----------------|------------------------------------------------|
| `mc`           | Midnight Commander file manager (TUI)          |
| `tmux`         | Terminal multiplexer                           |
| `htop`         | Interactive process viewer                     |
| `nano`         | Simple text editor                             |
| `vim-tiny`     | Vi-compatible editor                           |
| `rsync`        | Efficient file transfer/backup                 |
| `aria2`        | Multi-protocol download manager (HTTP/FTP/BT)  |
| `curl` `wget`  | HTTP clients                                   |
| `smartmontools`| SMART disk health monitoring (`smartctl`)      |
| `hdparm`       | Disk parameter tuning                          |
| `ethtool`      | Ethernet diagnostics                           |
| `xfsprogs`     | XFS filesystem tools (`mkfs.xfs`, `xfs_repair`)|
| `mdadm`        | Software RAID management (md0)                 |
| `ntpdate`      | Network time synchronization                   |
| `logrotate`    | Log file rotation                              |
| `net-tools`    | `ifconfig`, `netstat`, `route`                 |
| `iproute`      | `ip` command suite                             |
| `dnsutils`     | `dig`, `nslookup`                              |
| `less`         | Pager for reading files/logs                   |

All packages installed from `archive.debian.org` (Squeeze, with Wheezy repo added temporarily for MiniDLNA and its libav/libjpeg dependencies).
New packages can be installed with `apt-get install`.

### Services
| Service              | Port  | Description                              |
|----------------------|-------|------------------------------------------|
| **SSH**              | 22    | OpenSSH server (password + key auth)     |
| **Samba**            | 445   | Windows file sharing (3 configurable shares) |
| **Transmission**     | 9091  | BitTorrent with web UI                   |
| **lighttpd**         | 70    | Dashboard + settings panel               |
| **lighttpd**         | 80    | Personal website (CRT retro terminal)    |
| **MiniDLNA**         | 8200  | UPnP/DLNA media server                  |
| **aria2**            | 6800  | Download manager (HTTP/FTP/BT/Magnet)    |
| **monit**            | 2812  | Service monitor (auto-restart)           |

### Samba Shares
| Share         | Path                       | Access         |
|---------------|----------------------------|----------------|
| `home`        | `/home`                    | sysadmin only  |
| `public`      | `/home/public`             | Guest read/write |
| `downloads`   | `/home/downloads/complete` | Guest read-only |

### Web Applications (port 70)
All accessible from the dashboard via service cards:

| App               | URL Path               | Description                                |
|-------------------|------------------------|--------------------------------------------|
| Dashboard         | `/`                    | System stats, service cards, disk bars     |
| Settings          | `/settings.html`       | Full NAS configuration UI                  |
| File Manager      | `/cgi-bin/filemgr.sh`  | Browse, upload, download, delete files     |
| Downloads (aria2) | `/cgi-bin/aria2-ui.sh` | Downloads with auth, cookies, premium support|
| Photo Gallery     | `/cgi-bin/gallery.sh`  | Thumbnail grid with lightbox viewer        |
| Monit             | `/cgi-bin/monit-proxy.sh` | Dark-themed process monitor             |
| System Logs       | `/cgi-bin/monit-logs.sh`  | Tail system/service logs with colors    |
| Web Terminal      | `/cgi-bin/webssh.sh`      | Browser-based shell with command history|

### Monitoring & Tuning
- **monit** (:2812) — process watchdog, checks every 60 seconds, auto-restarts crashed services
- **smartd** — SMART disk health monitoring
- **ntpdate** — time sync every 6 hours + on boot
- **hdparm** — write cache enabled, 10-minute spindown timer
- **sysctl** — tuned for NAS workload (swappiness=10, dirty ratio, network buffers)
- **tune2fs** — automatic fsck every 30 mounts or 90 days

**Monit monitored processes:**

| Process        | Check                          | Action on failure          |
|----------------|--------------------------------|----------------------------|
| `sshd`         | PID + port 22 SSH protocol     | Restart, timeout after 3x  |
| `smbd`         | PID file                       | Restart, timeout after 3x  |
| `nmbd`         | PID file                       | Restart, timeout after 3x  |
| `transmission` | PID file                       | Restart, timeout after 3x  |
| `lighttpd`     | PID + port 70 HTTP protocol    | Restart, timeout after 3x  |
| `minidlna`     | PID + port 8200 HTTP protocol  | Restart, timeout after 3x  |
| `aria2`        | PID file                       | Restart, timeout after 3x  |
| `usbcopy`      | PID file                       | Restart, timeout after 3x  |

**System alerts:** load average > 4, memory > 90%, rootfs > 85%, data > 90%

Web UI: `http://<NAS_IP>:70/cgi-bin/monit-proxy.sh` (dark-themed, no auth needed from LAN)

### GPIO — LEDs, Buzzer, Buttons

The Macpower GPIO driver exposes hardware controls via `/sys/gpio/devices/`.
Use `tee` for writes (shell redirect `>` won't work with sudo):

```bash
echo 1 | sudo tee /sys/gpio/devices/sys_led       # turn ON
echo 0 | sudo tee /sys/gpio/devices/sys_led       # turn OFF
```

**LEDs** (write `1` = on, `0` = off):

| File             | Controls               |
|------------------|------------------------|
| `sys_led`        | System/power LED (on at boot, stays on)      |
| `usb_led`        | USB LED (off by default, blinks during USB copy) |
| `sata1_err_led`  | SATA 1 error LED       |
| `sata2_err_led`  | SATA 2 error LED       |

**Other controls:**

| File          | Function                                      |
|---------------|-----------------------------------------------|
| `buzzer`      | Piezo buzzer (`1` = on, `0` = off)            |
| `power_off`   | Hardware power off (write `0` to shut down)   |

**Buttons** (read current state):

| File              | Value                          |
|-------------------|--------------------------------|
| `power_button`    | `1` = not pressed, `0` = pressed |
| `usbcopy_button`  | `0` = not pressed, `1` = pressed |
| `usbcopy_status`  | USB copy status                |

### USB Control

```bash
# Disable USB port
echo 0 | sudo tee /sys/bus/usb/devices/usb1/authorized

# Enable USB port
echo 1 | sudo tee /sys/bus/usb/devices/usb1/authorized

# Mount a USB drive (appears as /dev/sdb1 when plugged in)
sudo mount /dev/sdb1 /mnt/usb

# Unmount
sudo umount /mnt/usb
```

### Web Interface

The NAS serves two web interfaces on different ports:

**Port 70 — Dashboard & Web Apps**
- Live terminal-themed dashboard: CPU %, RAM, dual HDD temps, disk bars, status indicators
- Real-time clock (server-synced), internet connectivity, network info, live download/upload speed
- 10 service cards: Transmission, Samba, SSH, Settings, Website, aria2, Files, Gallery, Monit
- Reboot and shutdown buttons with confirmation
- **Settings panel** (`/settings.html`) — full NAS configuration with built-in CLI manuals
- **File Manager** — browse, upload, download, delete files in `/home`
- **Download Manager** — aria2 with HTTP/FTP/magnet downloads, premium hoster support (cookies, auth, referer)
- **Photo Gallery** — thumbnail grid with lightbox viewer for `/home/public/Pictures`
- **Monit** — dark-themed process monitor with system log viewer (10 log sources)
- **Web Terminal** — browser-based shell with command history, directory tracking, accessible from SSH card

**Port 80 — Personal Website**
- CRT retro terminal effect (scanlines, flicker, typing animation)
- Customizable — edit `/var/www-site/index.html` via SSH or Samba

### Settings System

All NAS configuration is managed through a web-based settings panel at `http://<NAS_IP>:70/settings.html`. Settings are stored in `/etc/etrayz/settings.conf` (shell-sourceable KEY=VALUE format) and applied automatically on save and at boot. The settings page also includes a **Manuals** section with detailed shell configuration guides for every service (SSH, Samba, Transmission, aria2, MiniDLNA, lighttpd, monit, and system administration).

**Configuration sections:**
| Section         | Settings                                                    |
|-----------------|-------------------------------------------------------------|
| **General**     | Timezone, dashboard password protection                     |
| **Buzzer**      | Startup beep, pattern selection (8 patterns), torrent alert |
| **Fan**         | Auto/manual mode, speed control (1-8)                       |
| **USB**         | Enable/disable port, automount, USB copy button target      |
| **Disk 2**      | Second SATA bay auto-detect, format, mount, Samba share     |
| **Samba**       | Workgroup, 3 shares (home/public/downloads) with guest/RO   |
| **Transmission**| Download dirs, speed limits, ratio, peer port, RPC whitelist|
| **DLNA**        | MiniDLNA media server, friendly name, media dir, port       |
| **aria2**       | Download manager, dirs, limits, RPC, premium accounts       |
| **SSH**         | Port, root login, password auth, authorized keys management |
| **Web**         | Dashboard port, website port, website title                 |
| **Development** | GCC, PHP, Python, SQLite versions, Dropbear SSH controls    |
| **Manuals**     | Built-in shell configuration guides for all services        |

**Buzzer patterns:** `single`, `double`, `triple`, `long`, `sos`, `startup`, `r2d2`, `imperial`

**Key files:**
| File                                    | Purpose                              |
|-----------------------------------------|--------------------------------------|
| `/etc/etrayz/defaults.conf`             | Factory default settings             |
| `/etc/etrayz/settings.conf`             | Active settings (writable by CGI)    |
| `/usr/local/bin/etrayz-apply`           | Applies settings to all services     |
| `/usr/local/bin/etrayz-buzzer`          | Plays GPIO buzzer patterns           |
| `/usr/local/bin/etrayz-usbcopy`        | USB copy button daemon               |
| `/var/www/cgi-bin/settings.sh`          | Settings CGI endpoint (GET/POST)     |
| `/var/www/cgi-bin/filemgr.sh`           | Web file manager CGI                 |
| `/var/www/cgi-bin/aria2-ui.sh`          | aria2 download manager web UI        |
| `/var/www/cgi-bin/gallery.sh`           | Photo gallery CGI                    |
| `/var/www/cgi-bin/monit-proxy.sh`       | Dark-themed monit proxy              |
| `/var/www/cgi-bin/monit-logs.sh`        | System log viewer                    |
| `/var/www/cgi-bin/webssh.sh`            | Web terminal (browser-based shell)   |
| `/var/www/settings.html`                | Settings web UI (with built-in manuals) |
| `/var/www-site/index.html`              | Personal website (port 80)           |
| `/etc/aria2/aria2.conf`                | aria2 download manager config        |
| `/etc/etrayz/aria2-accounts/`          | Premium file hoster accounts + cookies|
| `/etc/minidlna.conf`                   | MiniDLNA media server config         |
| `/etc/init.d/etrayz-disk2`             | Second disk auto-detect init script  |
| `/etc/init.d/aria2`                    | aria2 init script                    |

### Fan Control

The `thermAndFan` kernel driver controls the fan via `/sys/module/thermAndFan/parameters/`:

| Mode     | Behavior                                    |
|----------|---------------------------------------------|
| **Auto** | Driver manages fan speed (ratio 2–8)        |
| **Manual**| Fixed speed (min=max=chosen ratio)          |

Temperature and RPM readings from `/proc/therm-fan`.

### Second SATA Bay

The EtrayZ has two SATA bays. Bay 1 (`/dev/sda`) is the system disk. Bay 2 is
auto-detected at boot:

1. Insert HDD in bay 2, power on
2. `etrayz-disk2` init script detects `/sys/block/sdb` on the oxnassata.1 controller
3. If the disk has a filesystem — mounts at `/home2` (configurable)
4. If blank and auto-format is enabled — formats as XFS, then mounts
5. A Samba share (`storage`) appears automatically
6. Bay 2 LED lights up, dashboard shows Bay 2 temperature

The disk must be distinguished from USB devices — the init script checks the sysfs
device path to confirm it's on the SATA controller, not USB.

All disk 2 settings (mount point, auto-format, share name, guest access) are
configurable from the Settings panel under "Disk 2".

> **Important:** XFS must be formatted by the NAS kernel (v4 format). A modern PC
> creates XFS v5 which kernel 2.6.24 cannot read. Use the "Format as XFS" button
> in Settings, or format via SSH on the NAS.

### Samba Client (SMBv1)

The NAS runs Samba 3.x which only supports SMBv1. Modern clients disable SMBv1
by default:

**Linux** — add to `/etc/samba/smb.conf` under `[global]`:
```
client min protocol = NT1
```

**Windows 10/11** — enable "SMB 1.0/CIFS Client" in Windows Features
(Control Panel > Programs > Turn Windows features on or off).

### Downloading from Premium File Hosters

aria2 supports HTTPS, HTTP authentication, cookies, and custom headers — everything
needed to download from premium file hosting services (uploaded.net, 1fichier,
rapidgator, etc.). The web UI includes an expandable "Authentication & options" panel
with fields for credentials, cookies, referer, and output filename.

**Setting up accounts (one-time, in Settings > aria2 > Premium Accounts):**

1. Go to `http://<NAS_IP>:70/settings.html` and open the **aria2** section
2. Under **Premium Accounts**, click **+ Add Account**
3. Enter the service name (e.g. "uploaded.net"), username, password, and referer URL
4. For cookie-based login:
   - Install a cookie export extension in your browser:
     Firefox: "Cookie Quick Manager" or "cookies.txt",
     Chrome: "Get cookies.txt LOCALLY"
   - Log in to the file hosting site in your browser
   - Export cookies to text (Netscape/wget format)
   - Paste the cookie content into the **Cookies** field
5. Click **Save Accounts** — add as many services as you need

**Downloading (in the Download Manager web UI):**

1. Open the aria2 web UI at `http://<NAS_IP>:70/cgi-bin/aria2-ui.sh`
2. Click "Authentication & options" to expand the panel
3. Select your saved account from the **Account** dropdown (credentials auto-fill)
4. Paste the download link into the **URL** field
5. Click **+ Add**

**From the command line:**

```bash
# With cookies (for browser-based login sites):
aria2c --load-cookies=cookies.txt "https://uploaded.net/file/abc123"

# With HTTP auth (for sites with basic/digest auth):
aria2c --http-user=mylogin --http-passwd=mypass "https://example.com/file.zip"

# With referer (some hosters check this):
aria2c --referer="https://filehost.com/page" "https://filehost.com/dl/abc/file.zip"

# All options combined, 4 connections:
aria2c --load-cookies=cookies.txt --http-user=me --http-passwd=secret \
       --referer="https://host.com" -x 4 -s 4 "https://host.com/dl/file.zip"
```

> **Note:** aria2 handles the download itself — it does not parse file hoster web pages
> or solve captchas. You need a direct download link (or a premium account where the
> hoster provides direct links). For free accounts, get the direct link from your browser
> and pass it to aria2 along with the cookies.

---

## Compiling Software

The NAS has **GCC 4.4.5** installed. Complex packages (OpenSSL, curl, aria2, etc.)
should be compiled **natively on the NAS** — cross-compilation produces binaries that
segfault due to glibc version mismatch and missing kernel syscalls (kernel 2.6.24 is
missing several syscalls added in 2.6.27+).

```bash
# Transfer source to NAS and build natively
scp mypackage-1.0.tar.gz sysadmin@<NAS_IP>:~/
ssh sysadmin@<NAS_IP>
tar xf mypackage-1.0.tar.gz && cd mypackage-1.0
./configure --prefix=/usr/local CFLAGS="-march=armv5te -mtune=arm926ej-s -msoft-float -Os"
make -j1 && sudo make install
```

Key constraints: GCC 4.4.5 (no C++11 `nullptr`), kernel 2.6.24 (no `eventfd` flags,
no `getrandom`), glibc 2.11. See [HOWTO.md](HOWTO.md) for details and per-package build notes.

The `toolchain/` directory contains a Docker-based cross-compilation environment
(useful for kernel modules) but is **not recommended for userspace packages**.

---

## Default Credentials

| User        | Password  | Access                    |
|-------------|-----------|---------------------------|
| `sysadmin`  | `etrayz`  | sudo NOPASSWD, SSH, Samba |
| `root`      | `etrayz`  | Full root access          |

**Change these immediately after first boot:**
```bash
passwd
sudo passwd root
```

---

## SSH from a Modern System

Modern OpenSSH clients disable the legacy algorithms used by Debian Squeeze's SSH server.
Use these flags to connect:

```bash
ssh -o HostKeyAlgorithms=+ssh-rsa \
    -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    sysadmin@192.168.1.234
```

Or with `sshpass` for scripting:
```bash
sshpass -p etrayz ssh \
    -o HostKeyAlgorithms=+ssh-rsa \
    -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    sysadmin@192.168.1.234
```

To avoid typing the flags every time, add to `~/.ssh/config`:
```
Host etrayz
    HostName 192.168.1.234
    User sysadmin
    HostKeyAlgorithms +ssh-rsa
    PubkeyAcceptedAlgorithms +ssh-rsa
```

Then just: `ssh etrayz`

---

## Downloads

Large binary files are hosted on Google Drive to keep the git repository lightweight.

| File | Size | Description |
|------|------|-------------|
| `etrayz-system.img.xz` | 838 MB | **Complete disk image** — GPT + boot sectors + rootfs + swap (recommended) |
| `etrayz-rootfs.tar.xz` | 176 MB | Rootfs archive only — alternative for Path A deploy |
| `original_firmware/hdd.bin` | 665 MB | Original factory firmware disk image |
| `original_firmware/etrayz_1.0.4-official_installer.zip` | 210 MB | Original installer package |
| `original_firmware/user_manual_eng.pdf` | 11 MB | Original user manual |
| `original_firmware/eTRAYz_quick_eng.pdf` | 2.2 MB | Original quick start guide |
| `original_firmware/e-TRAYzConnector.exe` | 3.6 MB | Windows NAS discovery tool |
| `original_firmware/setup.exe` | 1.9 MB | Windows installer |
| `original_firmware/installglue` | 67 KB | Original disk setup script (reference) |

**Download link:** [Google Drive](https://drive.google.com/drive/folders/1uWRLUzy1yz7jQocOofOrtJKrjIi5J2ja?usp=sharing)

The easiest restore uses `etrayz-system.img.xz` — it contains everything including boot sectors and partition table. See [HOWTO.md](HOWTO.md) for restore instructions.

---

## Quick Start

There are three ways to deploy this firmware. See [HOWTO.md](HOWTO.md) for full details.

### Path A: Restore from Disk Image (Easiest)

The complete disk image includes GPT, boot sectors, rootfs and swap — just `dd` it to the disk.
Download `etrayz-system.img.xz` from Google Drive first.

```bash
git clone https://github.com/<user>/XtreamerEtrayZ.git
cd XtreamerEtrayZ
# Download etrayz-system.img.xz from Google Drive
sudo bash scripts/restore-from-image.sh etrayz-system.img.xz /dev/sdX
```

The script writes the image, then creates a fresh XFS `/home` partition on the remaining space.

### Path B: Deploy Pre-built Rootfs

Use the rootfs archive with the deploy script. Downloads `etrayz-rootfs.tar.xz` from Google Drive.

```bash
git clone https://github.com/<user>/XtreamerEtrayZ.git
cd XtreamerEtrayZ
# Download etrayz-rootfs.tar.xz from Google Drive and place in rootfs/
sudo ./scripts/deploy-prebuilt.sh /dev/sdX
```

### Path C: Build from Scratch

Build the entire rootfs yourself. Requires `debootstrap` and `qemu-user-static`.
Does **not** require a running NAS — all kernel modules and firmware are included
in this repository.

```bash
git clone https://github.com/<user>/XtreamerEtrayZ.git
cd XtreamerEtrayZ
sudo ./scripts/build-from-scratch.sh
sudo ./scripts/deploy-prebuilt.sh /dev/sdX
```

---

## Disk Layout

```
/dev/sda (500 GB)
  ├─ [sectors 0-33]     GPT header + partition table
  ├─ [sector 34]        stage1.wrapped (bootloader stage 1)
  ├─ [sector 36]        u-boot.wrapped (U-Boot)
  ├─ [sector 290]       uImage (Linux kernel, primary)
  ├─ [sector 8482]      uImage.1 (kernel backup)
  ├─ [sector 16674]     uUpgradeRootfs (recovery ramdisk)
  ├─ sda1 (16-2064 MB)  → md0 RAID1 → ext3 rootfs (~2 GB)
  ├─ sda2 (2064-2576 MB)→ md1 RAID1 → swap (~500 MB)
  └─ sda3 (2576 MB-end) → XFS /home (data partition)

/dev/mtd0 (4 MB NOR flash) = U-Boot — NEVER TOUCH
```

Boot files are written at **raw sector offsets** in the GPT gap before partition 1.
U-Boot reads the kernel directly from these sectors, not from any filesystem.
The md arrays are single-disk RAID1 (degraded) because the kernel command line
has `root=/dev/md0` hardcoded in U-Boot — this cannot be changed without reflashing
the NOR flash.

---

## Repository Contents

```
├── boot_files/              Bootloader + kernel images (from NAS)
│   ├── stage1.wrapped       First stage bootloader (456 bytes)
│   ├── u-boot.wrapped       U-Boot bootloader (111 KB)
│   ├── uImage               Linux 2.6.24.4 kernel (1.9 MB)
│   ├── uImage.1             Backup kernel (948 KB)
│   └── uUpgradeRootfs       Recovery ramdisk (247 KB)
│
├── nas_files/
│   ├── nas_modules_fw.tar.gz   Kernel modules + firmware blobs
│   └── settings/               Settings system scripts & templates
│       ├── defaults.conf        Factory default settings
│       ├── etrayz-apply         Master settings apply script
│       ├── etrayz-buzzer        GPIO buzzer pattern player
│       ├── etrayz-usbcopy       USB copy button daemon
│       ├── etrayz-disk2         Second SATA bay auto-detect script
│       ├── etrayz-settings-init Boot-time settings init script
│       ├── settings-cgi.sh      Settings CGI endpoint
│       ├── aria2-ui.sh          aria2 download manager web UI
│       ├── filemgr.sh           Web file manager CGI
│       ├── gallery.sh           Photo gallery CGI
│       ├── monit-proxy.sh       Dark-themed monit reverse proxy
│       ├── monit-logs.sh        System log viewer CGI
│       ├── webssh.sh            Web terminal CGI
│       ├── site-index.html      Personal website template
│       └── dropbear             Dropbear SSH init script
│
├── rom_codes                Disk signature (444 bytes, RAID identification)
│
├── rootfs/
│   └── index.html           Dashboard HTML template
│   └── settings.html        Settings page HTML template
│   (etrayz-rootfs.tar.xz is on Google Drive — too large for git)
│
├── scripts/
│   ├── restore-from-image.sh   Restore complete disk image (Path A)
│   ├── deploy-prebuilt.sh      Deploy rootfs archive to HDD (Path B)
│   └── build-from-scratch.sh  Build rootfs from scratch (Path C)
│
├── toolchain/               Docker cross-compilation (kernel modules only)
│   ├── Dockerfile           Extracts ARM toolchain from original firmware
│   ├── build.sh             Builds the Docker image
│   ├── run.sh               Launches the toolchain container
│   ├── etrayz-run           Environment wrapper script
│   ├── etrayz-toolchain.sh  Shell profile for interactive use
│   └── test-hello.c         Test program for verification
│   NOTE: Not suitable for userspace packages — use native NAS compilation
│
│   (original_firmware/ is on Google Drive — too large for git)
│
├── screenshot.png           Dashboard screenshot
├── screenshot_settings.png  Settings panel screenshot
├── screenshot_website.png   Personal website screenshot
├── HOWTO.md                 Detailed deployment guide
├── SESSION_STATE.md         Project development notes
└── LICENSE                  MIT (scripts/docs) + proprietary notice
```

---

## Kernel Limitations

This kernel is from January 2009. The following modern features are **not available**:

| Feature              | Status | Minimum Kernel |
|----------------------|--------|----------------|
| Docker / containers  | No     | 3.10+          |
| systemd              | No     | 3.13+          |
| udev                 | No     | 2.6.26+        |
| ext4                 | No     | 2.6.28+        |
| WireGuard            | No     | 3.10+          |
| nftables             | No     | 3.13+          |
| btrfs                | No     | 3.x+           |
| OverlayFS            | No     | 3.18+          |
| inotify              | Yes    | 2.6.13+        |
| epoll                | Yes    | 2.6+           |
| ext3 / XFS (v4)      | Yes    | 2.6+           |

---

## Troubleshooting

**NAS doesn't respond after boot:**
1. Wait 3 full minutes (183 MHz ARM is slow)
2. Check router DHCP leases for the NAS IP
3. If still nothing: pull HDD, mount on laptop, check `/var/log/`

**Network not working:**
- GMAC needs CoPro firmware loaded via `/sbin/hotplug`
- Check: `lsmod | grep gmac` and `dmesg | grep -i gmac`

**SSH connection refused:**
- Modern SSH clients need legacy algorithm flags (see SSH section above)

**XFS partition not mounting:**
- XFS v4 format required (kernel 2.6.24 can't read v5/CRC format)
- Format from the NAS itself, not from a modern Linux PC

---

## Future Upgrade Path

If someone builds a working kernel from the [OX810SE open-source trees](https://github.com/oxnas-oss/linux-oxnas):

- Kernel 4.x/5.x would allow Debian 12 Bookworm (modern glibc, systemd, ext4)
- All modern packages and security updates
- Fan control needs porting from vendor `thermAndFan` to mainline `gpio-fan`
- U-Boot source: [oxnas-oss/u-boot-oxnas](https://github.com/oxnas-oss/u-boot-oxnas)

---

## Acknowledgments

- Oxford Semiconductor / PLX Technology for the OX810SE SoC
- Macpower / Xtreamer for the original firmware
- The Debian project for maintaining the Squeeze archive
- [oxnas-oss](https://github.com/oxnas-oss) for open-source OX810SE kernel work
