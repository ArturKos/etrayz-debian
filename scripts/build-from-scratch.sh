#!/bin/bash
# =============================================================================
# EtrayZ Build Script — Path B: Build Rootfs from Scratch
# =============================================================================
# Builds a complete Debian 6 Squeeze armel rootfs for the EtrayZ NAS.
#
# This script does NOT require a running NAS. All proprietary kernel modules
# and firmware are included in this repository (nas_files/nas_modules_fw.tar.gz).
#
# The output is rootfs/etrayz-rootfs.tar.xz which can then be deployed to
# the HDD using scripts/deploy-prebuilt.sh.
#
# Prerequisites (Debian/Ubuntu x86_64 build host):
#   sudo apt-get install debootstrap qemu-user-static binfmt-support
#
# Usage:
#   sudo ./build-from-scratch.sh
#
# Output:
#   rootfs/etrayz-rootfs.tar.xz
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
BUILD_DIR="${REPO_DIR}/build"
ROOTFS="${BUILD_DIR}/rootfs"
OUTPUT="${REPO_DIR}/rootfs/etrayz-rootfs.tar.xz"
MODULES_ARCHIVE="${REPO_DIR}/nas_files/nas_modules_fw.tar.gz"

# --- Checks ------------------------------------------------------------------

[[ $EUID -ne 0 ]] && error "This script must be run as root (sudo)."
command -v debootstrap    >/dev/null || error "debootstrap not found. Install: sudo apt-get install debootstrap"
command -v qemu-arm-static >/dev/null || error "qemu-arm-static not found. Install: sudo apt-get install qemu-user-static binfmt-support"
[[ -f "$MODULES_ARCHIVE" ]] || error "Kernel modules archive not found: $MODULES_ARCHIVE"

# --- Cleanup function --------------------------------------------------------

cleanup() {
    info "Cleaning up mounts..."
    for mp in "${ROOTFS}/dev/pts" "${ROOTFS}/dev" "${ROOTFS}/sys" "${ROOTFS}/proc"; do
        mountpoint -q "$mp" 2>/dev/null && umount -lf "$mp" 2>/dev/null || true
    done
}
trap cleanup EXIT

# =============================================================================
step "Step 1: Debootstrap Debian 6 Squeeze armel"
# =============================================================================

mkdir -p "$ROOTFS"

if [[ -f "${ROOTFS}/bin/bash" ]]; then
    info "Existing rootfs found. Reusing (delete ${ROOTFS} to rebuild from scratch)."
else
    info "Running debootstrap first stage..."
    debootstrap --arch=armel --foreign \
        squeeze "$ROOTFS" http://archive.debian.org/debian/

    info "Copying qemu-arm-static..."
    cp "$(which qemu-arm-static)" "${ROOTFS}/usr/bin/"

    info "Running debootstrap second stage (this takes several minutes)..."
    chroot "$ROOTFS" /debootstrap/debootstrap --second-stage
fi

# =============================================================================
step "Step 2: Configure APT and install packages"
# =============================================================================

# APT sources for archived Squeeze
cat > "${ROOTFS}/etc/apt/sources.list" <<'APT'
deb http://archive.debian.org/debian/ squeeze main contrib non-free
APT

# Prevent service starts during install
cat > "${ROOTFS}/usr/sbin/policy-rc.d" <<'POLICY'
#!/bin/sh
exit 101
POLICY
chmod +x "${ROOTFS}/usr/sbin/policy-rc.d"

# Mount virtual filesystems for chroot
mount -t proc proc "${ROOTFS}/proc"
mount -t sysfs sysfs "${ROOTFS}/sys"
mount -o bind /dev "${ROOTFS}/dev"
mount -o bind /dev/pts "${ROOTFS}/dev/pts"

info "Updating package lists..."
chroot "$ROOTFS" apt-get update -o Acquire::Check-Valid-Until=false 2>&1 | tail -3

info "Installing packages (this takes a while on ARM emulation)..."
chroot "$ROOTFS" apt-get install -y --force-yes \
    openssh-server openssh-client \
    samba smbclient \
    transmission-daemon \
    aria2 \
    lighttpd \
    monit \
    sudo \
    rsync \
    htop \
    curl wget \
    mdadm \
    xfsprogs \
    smartmontools \
    hdparm ethtool \
    ntpdate \
    logrotate rsyslog cron \
    nano vim-tiny less \
    net-tools iproute iputils-ping traceroute dnsutils \
    mc tmux \
    sysvinit sysvinit-utils \
    2>&1 | tail -20

rm -f "${ROOTFS}/usr/sbin/policy-rc.d"

# Install minidlna from Wheezy (not in Squeeze repos)
info "Adding Wheezy repo for minidlna..."
echo "deb http://archive.debian.org/debian/ wheezy main" > "${ROOTFS}/etc/apt/sources.list.d/wheezy.list"
chroot "$ROOTFS" apt-get update 2>&1 | tail -5
chroot "$ROOTFS" apt-get install -y --force-yes minidlna 2>&1 | tail -10
rm -f "${ROOTFS}/etc/apt/sources.list.d/wheezy.list"
chroot "$ROOTFS" apt-get update 2>&1 | tail -3
# Fix init script for Squeeze: /run -> /var/run
sed -i 's|PIDDIR=/run/|PIDDIR=/var/run/|' "${ROOTFS}/etc/init.d/minidlna"

# =============================================================================
step "Step 3: Install kernel modules and firmware"
# =============================================================================

info "Extracting kernel modules and firmware from archive..."
tar xzf "$MODULES_ARCHIVE" -C "$ROOTFS"

# Run depmod
chroot "$ROOTFS" depmod -a 2.6.24.4 2>/dev/null || true

# =============================================================================
step "Step 4: Create static /dev nodes"
# =============================================================================

info "Creating essential device nodes..."
# This kernel has no udev (needs 2.6.26+), so we need static /dev
cd "${ROOTFS}/dev"

# Core devices
[[ -e null ]]    || mknod -m 666 null c 1 3
[[ -e zero ]]    || mknod -m 666 zero c 1 5
[[ -e random ]]  || mknod -m 666 random c 1 8
[[ -e urandom ]] || mknod -m 666 urandom c 1 9
[[ -e console ]] || mknod -m 600 console c 5 1
[[ -e tty ]]     || mknod -m 666 tty c 5 0
[[ -e ptmx ]]    || mknod -m 666 ptmx c 5 2

# Serial console
for i in 0 1; do
    [[ -e ttyS$i ]] || mknod -m 660 ttyS$i c 4 $((64+i))
done

# TTYs
for i in $(seq 0 7); do
    [[ -e tty$i ]] || mknod -m 660 tty$i c 4 $i
done

# PTYs
mkdir -p pts
for i in $(seq 0 15); do
    [[ -e ptyp$i ]]  || mknod -m 660 ptyp$i c 2 $i
    [[ -e ttyp$i ]]  || mknod -m 660 ttyp$i c 3 $i
done

# Block devices — SATA disk
for i in $(seq 0 3); do
    local_prefix=""
    for letter in a b c d; do
        dev_num=$((i * 4))
        case $letter in
            a) dev_num=0 ;; b) dev_num=16 ;; c) dev_num=32 ;; d) dev_num=48 ;;
        esac
        [[ -e sd${letter} ]] || mknod -m 660 sd${letter} b 8 $dev_num
        for p in 1 2 3 4 5; do
            [[ -e sd${letter}$p ]] || mknod -m 660 sd${letter}$p b 8 $((dev_num+p))
        done
    done
    break  # Only need sda-sdd
done

# MD RAID
for i in 0 1 2 3; do
    [[ -e md$i ]] || mknod -m 660 md$i b 9 $i
done

# MTD flash
for i in 0 1; do
    [[ -e mtdblock$i ]] || mknod -m 660 mtdblock$i b 31 $i
    [[ -e mtd$i ]]      || mknod -m 660 mtd$i c 90 $((i*2))
done

# Loop devices
for i in $(seq 0 7); do
    [[ -e loop$i ]] || mknod -m 660 loop$i b 7 $i
done

# USB
mkdir -p bus/usb

# Misc
[[ -e mem ]]     || mknod -m 640 mem c 1 1
[[ -e kmem ]]    || mknod -m 640 kmem c 1 2
[[ -e full ]]    || mknod -m 666 full c 1 7
[[ -e kmsg ]]    || mknod -m 660 kmsg c 1 11
mkdir -p net
[[ -e net/tun ]] || mknod -m 660 net/tun c 10 200

# Symlinks
ln -sf /proc/self/fd fd
ln -sf /proc/self/fd/0 stdin
ln -sf /proc/self/fd/1 stdout
ln -sf /proc/self/fd/2 stderr

cd "$REPO_DIR"

# =============================================================================
step "Step 5: System configuration"
# =============================================================================

# --- Hostname ----------------------------------------------------------------
echo "etrayz" > "${ROOTFS}/etc/hostname"
cat > "${ROOTFS}/etc/hosts" <<'HOSTS'
127.0.0.1   localhost
127.0.1.1   etrayz
HOSTS

# --- fstab -------------------------------------------------------------------
cat > "${ROOTFS}/etc/fstab" <<'FSTAB'
/dev/md0    /           ext3    rw,noatime,nodiratime   0 1
/dev/md1    none        swap    sw                      0 0
/dev/sda3   /home       xfs     rw,noatime,nodiratime,nofail   0 0
none        /dev/pts    devpts  gid=5,mode=620          0 0
none        /dev/shm    ramfs   defaults                0 0
none        /proc       proc    defaults                0 0
none        /sys        sysfs   defaults                0 0
none        /tmp        ramfs   defaults                0 0
FSTAB

# --- inittab -----------------------------------------------------------------
cat > "${ROOTFS}/etc/inittab" <<'INITTAB'
id:3:initdefault:
si::sysinit:/etc/init.d/rcS
l0:0:wait:/etc/init.d/rc 0
l3:3:wait:/etc/init.d/rc 3
l6:6:wait:/etc/init.d/rc 6
ca:12345:ctrlaltdel:/sbin/shutdown -r now
T0:23:respawn:/sbin/getty -L ttyS0 115200 vt100
INITTAB

# --- Network -----------------------------------------------------------------
cat > "${ROOTFS}/etc/network/interfaces" <<'IFACES'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
    hwaddress ether 00:1c:85:20:4e:45
IFACES

# DHCP gateway fix
mkdir -p "${ROOTFS}/etc/dhcp/dhclient-exit-hooks.d"
cat > "${ROOTFS}/etc/dhcp/dhclient-exit-hooks.d/set-gateway" <<'GWFIX'
if [ -n "$new_routers" ]; then
    ip route replace default via $new_routers
fi
GWFIX

# --- /sbin/hotplug (CRITICAL for CoPro firmware loading) --------------------
cat > "${ROOTFS}/sbin/hotplug" <<'HOTPLUG'
#!/bin/sh
if [ "$1" = "firmware" ]; then
    FIRMWARE_DIR="/lib/firmware"
    SYSFS_PATH="/sys${DEVPATH}"
    if [ -f "${FIRMWARE_DIR}/${FIRMWARE}" ]; then
        echo 1 > "${SYSFS_PATH}/loading"
        cat "${FIRMWARE_DIR}/${FIRMWARE}" > "${SYSFS_PATH}/data"
        echo 0 > "${SYSFS_PATH}/loading"
    else
        echo -1 > "${SYSFS_PATH}/loading"
    fi
fi
HOTPLUG
chmod 755 "${ROOTFS}/sbin/hotplug"

# --- Module loading init script ----------------------------------------------
cat > "${ROOTFS}/etc/init.d/load-modules" <<'LOADMOD'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          load-modules
# Required-Start:    mountkernfs
# Required-Stop:
# Default-Start:     S
# Default-Stop:
# Short-Description: Load kernel modules for NAS hardware
### END INIT INFO
case "$1" in
  start)
    echo "Setting up firmware loader..."
    echo "/sbin/hotplug" > /proc/sys/kernel/hotplug
    echo "Loading NAS kernel modules..."
    /sbin/modprobe gmac
    /sbin/modprobe ehci-hcd
    ;;
  stop) ;;
  *) echo "Usage: $0 {start|stop}"; exit 1 ;;
esac
exit 0
LOADMOD
chmod 755 "${ROOTFS}/etc/init.d/load-modules"
chroot "$ROOTFS" update-rc.d load-modules defaults 01 99

# --- Fallback network script -------------------------------------------------
cat > "${ROOTFS}/etc/init.d/fixnet" <<'FIXNET'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          fixnet
# Required-Start:    networking
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:
# Short-Description: Ensure network connectivity and default gateway
### END INIT INFO
case "$1" in
  start)
    sleep 3
    # Retry DHCP if no IP yet
    if ! ip addr show eth0 | grep -q "inet "; then
        echo "DHCP failed, trying dhclient again..."
        dhclient -1 eth0 2>/dev/null
        sleep 5
    fi
    # Static fallback if still no IP
    if ! ip addr show eth0 | grep -q "inet "; then
        echo "Setting fallback static IP 192.168.1.234/24"
        ip addr add 192.168.1.234/24 dev eth0
    fi
    # Ensure default gateway is set (dhclient-script often misses it on this kernel)
    if ! ip route show | grep -q "^default"; then
        gw=$(grep 'option routers' /var/lib/dhcp/dhclient.eth0.leases 2>/dev/null | tail -1 | sed 's/.*routers \(.*\);/\1/')
        if [ -n "$gw" ]; then
            echo "Adding default gateway $gw from DHCP lease"
            ip route add default via "$gw" dev eth0
        else
            echo "Adding fallback gateway 192.168.1.1"
            ip route add default via 192.168.1.1 dev eth0
        fi
    fi
    echo "Network status:" >> /var/log/bootdebug.log
    ip addr show eth0 >> /var/log/bootdebug.log 2>&1
    ip route >> /var/log/bootdebug.log 2>&1
    ;;
esac
exit 0
FIXNET
chmod 755 "${ROOTFS}/etc/init.d/fixnet"
chroot "$ROOTFS" update-rc.d fixnet defaults 90

# --- LED init script ----------------------------------------------------------
cat > "${ROOTFS}/etc/init.d/leds" <<'LEDINIT'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          leds
# Required-Start:    $all
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:
# Short-Description: Set LED states based on hardware presence
### END INIT INFO
case "$1" in
  start)
    echo 1 > /sys/gpio/devices/sys_led
    # USB LED off at boot — only blinks during USB copy
    echo 0 > /sys/gpio/devices/usb_led
    # SATA bay LEDs — on if disk present on that port
    # sda = oxnassata.0 (bay 1), sdb = oxnassata.1 (bay 2)
    if [ -d /sys/block/sda ]; then
        echo 1 > /sys/gpio/devices/sata1_err_led
    else
        echo 0 > /sys/gpio/devices/sata1_err_led
    fi
    if [ -d /sys/block/sdb ]; then
        echo 1 > /sys/gpio/devices/sata2_err_led
    else
        echo 0 > /sys/gpio/devices/sata2_err_led
    fi
    ;;
  stop)
    echo 0 > /sys/gpio/devices/sys_led
    echo 0 > /sys/gpio/devices/usb_led
    echo 0 > /sys/gpio/devices/sata1_err_led
    echo 0 > /sys/gpio/devices/sata2_err_led
    ;;
esac
exit 0
LEDINIT
chmod 755 "${ROOTFS}/etc/init.d/leds"
chroot "$ROOTFS" update-rc.d leds defaults 95

# --- EtrayZ Settings System --------------------------------------------------
info "Installing EtrayZ settings system..."

SETTINGS_SRC="${REPO_DIR}/nas_files/settings"

# Defaults config
mkdir -p "${ROOTFS}/etc/etrayz"
cp "${SETTINGS_SRC}/defaults.conf" "${ROOTFS}/etc/etrayz/defaults.conf"
cp "${ROOTFS}/etc/etrayz/defaults.conf" "${ROOTFS}/etc/etrayz/settings.conf"
chroot "$ROOTFS" chown www-data:www-data /etc/etrayz/settings.conf

# Apply script
cp "${SETTINGS_SRC}/etrayz-apply" "${ROOTFS}/usr/local/bin/etrayz-apply"
chmod 755 "${ROOTFS}/usr/local/bin/etrayz-apply"

# Buzzer script
cp "${SETTINGS_SRC}/etrayz-buzzer" "${ROOTFS}/usr/local/bin/etrayz-buzzer"
chmod 755 "${ROOTFS}/usr/local/bin/etrayz-buzzer"

# USB copy daemon
cp "${SETTINGS_SRC}/etrayz-usbcopy" "${ROOTFS}/usr/local/bin/etrayz-usbcopy"
chmod 755 "${ROOTFS}/usr/local/bin/etrayz-usbcopy"

# Settings CGI
cp "${SETTINGS_SRC}/settings-cgi.sh" "${ROOTFS}/var/www/cgi-bin/settings.sh"
chmod 755 "${ROOTFS}/var/www/cgi-bin/settings.sh"

# Monit proxy and log viewer CGI
cp "${SETTINGS_SRC}/monit-proxy.sh" "${ROOTFS}/var/www/cgi-bin/monit-proxy.sh"
cp "${SETTINGS_SRC}/monit-logs.sh" "${ROOTFS}/var/www/cgi-bin/monit-logs.sh"
cp "${SETTINGS_SRC}/aria2-ui.sh" "${ROOTFS}/var/www/cgi-bin/aria2-ui.sh"
cp "${SETTINGS_SRC}/filemgr.sh" "${ROOTFS}/var/www/cgi-bin/filemgr.sh"
cp "${SETTINGS_SRC}/gallery.sh" "${ROOTFS}/var/www/cgi-bin/gallery.sh"
cp "${SETTINGS_SRC}/webssh.sh" "${ROOTFS}/var/www/cgi-bin/webssh.sh"
chmod 755 "${ROOTFS}/var/www/cgi-bin/monit-proxy.sh" "${ROOTFS}/var/www/cgi-bin/monit-logs.sh" \
          "${ROOTFS}/var/www/cgi-bin/aria2-ui.sh" "${ROOTFS}/var/www/cgi-bin/filemgr.sh" \
          "${ROOTFS}/var/www/cgi-bin/gallery.sh" "${ROOTFS}/var/www/cgi-bin/webssh.sh"

# Allow www-data to read system logs
chroot "$ROOTFS" adduser www-data adm 2>/dev/null || true

# Settings page HTML
SETTINGS_HTML="${REPO_DIR}/rootfs/settings.html"
if [[ -f "$SETTINGS_HTML" ]]; then
    cp "$SETTINGS_HTML" "${ROOTFS}/var/www/settings.html"
fi

# Personal website (port 80)
mkdir -p "${ROOTFS}/var/www-site"
cp "${SETTINGS_SRC}/site-index.html" "${ROOTFS}/var/www-site/index.html"

# Settings init script
cp "${SETTINGS_SRC}/etrayz-settings-init" "${ROOTFS}/etc/init.d/etrayz-settings"
chmod 755 "${ROOTFS}/etc/init.d/etrayz-settings"
chroot "$ROOTFS" update-rc.d etrayz-settings defaults 99

# Disk 2 auto-detection init script
cp "${SETTINGS_SRC}/etrayz-disk2" "${ROOTFS}/etc/init.d/etrayz-disk2"
chmod 755 "${ROOTFS}/etc/init.d/etrayz-disk2"
chroot "$ROOTFS" update-rc.d etrayz-disk2 defaults 96

# Sudo rules for settings CGI (etrayz-apply, buzzer, mount, umount, cp)
cat > "${ROOTFS}/etc/sudoers.d/etrayz" <<'ETZSUDO'
www-data ALL=(ALL) NOPASSWD: /usr/local/bin/etrayz-apply, /usr/local/bin/etrayz-buzzer, /bin/mount, /bin/umount, /bin/cp, /sbin/mkfs.xfs, /etc/init.d/etrayz-disk2, /etc/init.d/minidlna, /etc/init.d/aria2
ETZSUDO
chmod 440 "${ROOTFS}/etc/sudoers.d/etrayz"

# USB mount point
mkdir -p "${ROOTFS}/mnt/usb"

# --- Users -------------------------------------------------------------------
info "Creating users..."
chroot "$ROOTFS" bash -c "
    echo 'root:etrayz' | chpasswd
    id sysadmin >/dev/null 2>&1 || useradd -m -u 500 -s /bin/bash -G sudo sysadmin
    echo 'sysadmin:etrayz' | chpasswd
    echo 'sysadmin ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/sysadmin
    chmod 440 /etc/sudoers.d/sysadmin
"

# --- SSH ---------------------------------------------------------------------
info "Configuring SSH..."
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "${ROOTFS}/etc/ssh/sshd_config"
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "${ROOTFS}/etc/ssh/sshd_config"

# --- Samba -------------------------------------------------------------------
info "Configuring Samba..."
mkdir -p "${ROOTFS}/var/log/samba"
cat > "${ROOTFS}/etc/samba/smb.conf" <<'SAMBA'
[global]
   workgroup = WORKGROUP
   server string = EtrayZ NAS
   security = user
   map to guest = Bad Password
   log file = /var/log/samba/%m.log
   max log size = 50
   socket options = TCP_NODELAY SO_RCVBUF=65536 SO_SNDBUF=65536

[home]
   path = /home
   browseable = yes
   writable = yes
   guest ok = no
   valid users = sysadmin
   create mask = 0664
   directory mask = 0775

[public]
   path = /home/public
   browseable = yes
   writable = yes
   guest ok = yes
   force user = sysadmin
   create mask = 0666
   directory mask = 0777

[downloads]
   path = /home/downloads/complete
   browseable = yes
   writable = no
   guest ok = yes
   force user = sysadmin
SAMBA
chroot "$ROOTFS" bash -c "echo -e 'etrayz\netrayz' | smbpasswd -a -s sysadmin 2>/dev/null || true"

# --- Transmission ------------------------------------------------------------
info "Configuring Transmission..."
mkdir -p "${ROOTFS}/home/downloads/"{complete,incomplete,watch}
mkdir -p "${ROOTFS}/home/public"
chroot "$ROOTFS" chown -R sysadmin:sysadmin /home/downloads /home/public 2>/dev/null || true

# Transmission config will be created on first run; set defaults via init
mkdir -p "${ROOTFS}/var/lib/transmission-daemon/info"
cat > "${ROOTFS}/var/lib/transmission-daemon/info/settings.json" <<'TXCONF'
{
    "download-dir": "/home/downloads/complete",
    "incomplete-dir": "/home/downloads/incomplete",
    "incomplete-dir-enabled": true,
    "watch-dir": "/home/downloads/watch",
    "watch-dir-enabled": true,
    "rpc-whitelist": "127.0.0.1,192.168.*.*",
    "rpc-whitelist-enabled": true,
    "rpc-authentication-required": false,
    "speed-limit-up": 500,
    "speed-limit-up-enabled": true,
    "ratio-limit": 2.0,
    "ratio-limit-enabled": true,
    "peer-port": 51413,
    "encryption": 1
}
TXCONF
chroot "$ROOTFS" chown -R debian-transmission:debian-transmission /var/lib/transmission-daemon 2>/dev/null || true

# Patch transmission init script to create PID file (needed for monit)
sed -i '/--exec $DAEMON -- $OPTIONS/{
a\        PID=$(pgrep -f /usr/bin/transmission-daemon)\
        if [ -n "$PID" ]; then\
            mkdir -p /var/run/transmission-daemon\
            echo "$PID" > /var/run/transmission-daemon/transmission-daemon.pid\
        fi
}' "${ROOTFS}/etc/init.d/transmission-daemon"

# --- MiniDLNA ----------------------------------------------------------------
info "Configuring MiniDLNA..."
mkdir -p "${ROOTFS}/home/public/Music" "${ROOTFS}/home/public/Videos" "${ROOTFS}/home/public/Pictures"
mkdir -p "${ROOTFS}/var/lib/minidlna" "${ROOTFS}/var/run/minidlna"
cat > "${ROOTFS}/etc/minidlna.conf" <<'DLNACONF'
media_dir=A,/home/public/Music
media_dir=V,/home/public/Videos
media_dir=P,/home/public/Pictures
media_dir=/home/public
db_dir=/var/lib/minidlna
log_dir=/var/log
log_level=warn
port=8200
friendly_name=EtrayZ NAS
serial=12345678
model_number=1
inotify=yes
album_art_names=Cover.jpg/cover.jpg/AlbumArtSmall.jpg/albumartsmall.jpg/AlbumArt.jpg/albumart.jpg/Album.jpg/album.jpg/Folder.jpg/folder.jpg/Thumb.jpg/thumb.jpg
DLNACONF

# --- aria2 download manager --------------------------------------------------
info "Configuring aria2..."
mkdir -p "${ROOTFS}/etc/aria2"
mkdir -p "${ROOTFS}/etc/etrayz/aria2-accounts"
chroot "$ROOTFS" chown www-data:www-data /etc/etrayz/aria2-accounts
cat > "${ROOTFS}/etc/aria2/aria2.conf" <<'ARIA2CONF'
dir=/home/downloads/complete
log=/var/log/aria2.log
log-level=warn
enable-xml-rpc=true
xml-rpc-listen-all=true
xml-rpc-listen-port=6800
max-concurrent-downloads=3
max-connection-per-server=4
min-split-size=5M
split=4
continue=true
max-overall-upload-limit=100K
seed-ratio=0
input-file=/etc/aria2/aria2.session
save-session=/etc/aria2/aria2.session
save-session-interval=60
ARIA2CONF
touch "${ROOTFS}/etc/aria2/aria2.session"
touch "${ROOTFS}/var/log/aria2.log"
chroot "$ROOTFS" chown -R sysadmin:sysadmin /etc/aria2 /var/log/aria2.log 2>/dev/null || true

# aria2 init script
cat > "${ROOTFS}/etc/init.d/aria2" <<'ARIA2INIT'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          aria2
# Required-Start:    $local_fs $remote_fs $network
# Required-Stop:     $local_fs $remote_fs $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: aria2 download manager
### END INIT INFO
NAME=aria2c
DAEMON=/usr/bin/aria2c
CONF=/etc/aria2/aria2.conf
PIDFILE=/var/run/aria2.pid
USER=sysadmin
case "$1" in
  start) echo -n "Starting aria2: "; start-stop-daemon --start --background --make-pidfile --pidfile $PIDFILE --chuid $USER --exec $DAEMON -- --conf-path=$CONF; echo "done" ;;
  stop) echo -n "Stopping aria2: "; start-stop-daemon --stop --pidfile $PIDFILE --oknodo; rm -f $PIDFILE; echo "done" ;;
  restart) $0 stop; sleep 1; $0 start ;;
  status) [ -f $PIDFILE ] && kill -0 $(cat $PIDFILE) 2>/dev/null && echo "aria2 running" || { echo "aria2 not running"; exit 1; } ;;
  *) echo "Usage: $0 {start|stop|restart|status}"; exit 1 ;;
esac
ARIA2INIT
chmod 755 "${ROOTFS}/etc/init.d/aria2"
chroot "$ROOTFS" update-rc.d aria2 defaults 2>/dev/null || true

# Thumbnail cache for gallery
mkdir -p "${ROOTFS}/var/lib/etrayz/thumbs"

# --- lighttpd + dashboard ----------------------------------------------------
info "Configuring lighttpd..."

# Enable CGI
chroot "$ROOTFS" bash -c "lighttpd-enable-mod cgi 2>/dev/null || true"

# Set main server port to 70 (dashboard), port 80 for personal website
sed -i 's/^server.port.*/server.port = 70/' "${ROOTFS}/etc/lighttpd/lighttpd.conf" 2>/dev/null || true

# Dual-port config: port 80 serves personal website
cat > "${ROOTFS}/etc/lighttpd/conf-enabled/20-etrayz.conf" <<'DUALPORT'
# EtrayZ dual-port configuration
# Dashboard on port 70, website on port 80
$SERVER["socket"] == ":80" {
    server.document-root = "/var/www-site"
    index-file.names = ( "index.html" )
}
DUALPORT

mkdir -p "${ROOTFS}/var/www/cgi-bin"

# Status CGI
cat > "${ROOTFS}/var/www/cgi-bin/status.sh" <<'STATCGI'
#!/bin/sh
echo "Content-Type: application/json"
echo ""
STAT1=$(head -1 /proc/stat)
set -- $STAT1
u1=$2; n1=$3; s1=$4; i1=$5; w1=$6; q1=$7; sq1=$8
CPU1=$((u1+n1+s1+i1+w1+q1+sq1))
IDLE1=$i1
sleep 1
STAT2=$(head -1 /proc/stat)
set -- $STAT2
u2=$2; n2=$3; s2=$4; i2=$5; w2=$6; q2=$7; sq2=$8
CPU2=$((u2+n2+s2+i2+w2+q2+sq2))
IDLE2=$i2
TOTAL=$((CPU2-CPU1))
IDLE=$((IDLE2-IDLE1))
if [ $TOTAL -gt 0 ]; then
  CPU_PCT=$(( (TOTAL-IDLE)*100/TOTAL ))
else
  CPU_PCT=0
fi
MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk "{print int(\$2/1024)}")
MEM_FREE=$(grep -E "MemFree|Buffers|^Cached" /proc/meminfo | awk "{s+=\$2}END{print int(s/1024)}")
MEM_USED=$((MEM_TOTAL - MEM_FREE))
DISK=$(df -h /home 2>/dev/null | tail -1 | awk "{print \$3\"/\"\$2}")
DISK_PCT=$(df /home 2>/dev/null | tail -1 | awk "{print \$5}" | tr -d "%")
UPTIME=$(uptime | sed "s/.*up //" | sed "s/,.*//" | sed "s/^ *//" )
TEMP=$(sudo smartctl -d sat -A /dev/sda 2>/dev/null | awk "/Temperature_Celsius/{print \$10}")
[ -z "$TEMP" ] && TEMP=""
TEMP2=$(sudo smartctl -d sat -A /dev/sdb 2>/dev/null | awk "/Temperature_Celsius/{print \$10}")
[ -z "$TEMP2" ] && TEMP2=""
DISK_ROOT=$(df -h / 2>/dev/null | tail -1 | awk "{print \$3\"/\"\$2}")
DISK_ROOT_PCT=$(df / 2>/dev/null | tail -1 | awk "{print \$5}" | tr -d "%")
GW=$(ip route | awk "/default/{print \$3}")
[ -z "$GW" ] && GW="--"
DNS=$(awk "/^nameserver/{print \$2}" /etc/resolv.conf | head -1)
[ -z "$DNS" ] && DNS="--"
IPMASK=$(ip addr show eth0 2>/dev/null | awk "/inet /{print \$2}")
[ -z "$IPMASK" ] && IPMASK="--"
ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 && INET="1" || INET="0"
DATETIME=$(date "+%Y-%m-%d %H:%M:%S %Z")
# Network bytes from /proc/net/dev (eth0)
NET_LINE=$(grep eth0 /proc/net/dev 2>/dev/null)
NET_RX=$(echo "$NET_LINE" | awk -F: "{split(\$2,a,\" \"); print a[1]}")
NET_TX=$(echo "$NET_LINE" | awk -F: "{split(\$2,a,\" \"); print a[9]}")
[ -z "$NET_RX" ] && NET_RX="0"
[ -z "$NET_TX" ] && NET_TX="0"
# System LED: always 1 (if this CGI responds, system is running)
LED_SYS="1"
# USB: show port enabled/disabled state, not the physical LED
LED_USB=$(cat /sys/bus/usb/devices/usb1/authorized 2>/dev/null | tr -d ' \n')
LED_SATA1=$(cat /sys/gpio/devices/sata1_err_led 2>/dev/null | tr -d ' \n')
LED_SATA2=$(cat /sys/gpio/devices/sata2_err_led 2>/dev/null | tr -d ' \n')
echo "{\"cpu\":\"$CPU_PCT\",\"mem_used\":\"${MEM_USED}M\",\"mem_total\":\"${MEM_TOTAL}M\",\"disk\":\"$DISK\",\"disk_pct\":\"$DISK_PCT\",\"disk_root\":\"$DISK_ROOT\",\"disk_root_pct\":\"$DISK_ROOT_PCT\",\"uptime\":\"$UPTIME\",\"temp\":\"$TEMP\",\"temp2\":\"$TEMP2\",\"gw\":\"$GW\",\"dns\":\"$DNS\",\"ipmask\":\"$IPMASK\",\"inet\":\"$INET\",\"datetime\":\"$DATETIME\",\"led_sys\":\"$LED_SYS\",\"led_usb\":\"$LED_USB\",\"led_sata1\":\"$LED_SATA1\",\"led_sata2\":\"$LED_SATA2\",\"net_rx\":\"$NET_RX\",\"net_tx\":\"$NET_TX\"}"
STATCGI
chmod 755 "${ROOTFS}/var/www/cgi-bin/status.sh"

# Power CGI
cat > "${ROOTFS}/var/www/cgi-bin/power.sh" <<'POWERCGI'
#!/bin/sh
echo "Content-Type: application/json"
echo ""
read BODY
ACTION=$(echo "$BODY" | sed -n "s/.*action=\([a-z]*\).*/\1/p")
case "$ACTION" in
  reboot)   echo "{\"status\":\"ok\",\"action\":\"reboot\"}";   sudo /sbin/reboot & ;;
  shutdown) echo "{\"status\":\"ok\",\"action\":\"shutdown\"}"; sudo /sbin/poweroff & ;;
  *)        echo "{\"status\":\"error\",\"msg\":\"invalid action\"}" ;;
esac
POWERCGI
chmod 755 "${ROOTFS}/var/www/cgi-bin/power.sh"

# Sudo rules for www-data (CGI scripts)
echo "www-data ALL=(ALL) NOPASSWD: /sbin/reboot, /sbin/poweroff, /usr/sbin/smartctl" \
    > "${ROOTFS}/etc/sudoers.d/power"
chmod 440 "${ROOTFS}/etc/sudoers.d/power"

# Dashboard HTML (written from repo copy or inline)
DASHBOARD_SRC="${REPO_DIR}/rootfs/index.html"
if [[ -f "$DASHBOARD_SRC" ]]; then
    cp "$DASHBOARD_SRC" "${ROOTFS}/var/www/index.html"
else
    info "Dashboard HTML template not found, will use NAS copy from rootfs archive."
fi

# --- monit -------------------------------------------------------------------
info "Configuring monit..."
cat > "${ROOTFS}/etc/monit/monitrc" <<'MONIT'
set daemon 60
set logfile /var/log/monit.log
set httpd port 2812
    allow 192.168.0.0/16
    allow admin:monit

check system etrayz
    if loadavg (5min) > 4 then alert
    if memory usage > 90% then alert

check process dropbear with pidfile /var/run/dropbear.pid
    start program = "/etc/init.d/dropbear start"
    stop program  = "/etc/init.d/dropbear stop"
    if failed port 22 protocol ssh then restart
    if 3 restarts within 5 cycles then timeout

check process smbd with pidfile /var/run/samba/smbd.pid
    start program = "/etc/init.d/samba start"
    stop program  = "/etc/init.d/samba stop"
    if 3 restarts within 5 cycles then timeout

check process nmbd with pidfile /var/run/samba/nmbd.pid
    start program = "/etc/init.d/samba start"
    stop program  = "/etc/init.d/samba stop"
    if 3 restarts within 5 cycles then timeout

check process transmission with pidfile /var/run/transmission-daemon/transmission-daemon.pid
    start program = "/etc/init.d/transmission-daemon start"
    stop program  = "/etc/init.d/transmission-daemon stop"
    if 3 restarts within 5 cycles then timeout

check process lighttpd with pidfile /var/run/lighttpd.pid
    start program = "/etc/init.d/lighttpd start"
    stop program  = "/etc/init.d/lighttpd stop"
    if failed port 70 protocol http then restart
    if 3 restarts within 5 cycles then timeout

check process aria2 with pidfile /var/run/aria2.pid
    start program = "/etc/init.d/aria2 start"
    stop program  = "/etc/init.d/aria2 stop"
    if 3 restarts within 5 cycles then timeout

check process minidlna with pidfile /var/run/minidlna/minidlna.pid
    start program = "/etc/init.d/minidlna start"
    stop program  = "/etc/init.d/minidlna stop"
    if failed port 8200 protocol http then restart
    if 3 restarts within 5 cycles then timeout

check process usbcopy with pidfile /var/run/etrayz-usbcopy.pid
    start program = "/etc/init.d/etrayz-settings start"
    stop program  = "/etc/init.d/etrayz-settings stop"
    if 3 restarts within 5 cycles then timeout

check filesystem rootfs with path /dev/md0
    if space usage > 85% then alert

check filesystem datafs with path /dev/sda3
    if space usage > 90% then alert
MONIT
chmod 600 "${ROOTFS}/etc/monit/monitrc"

# --- sysctl tuning -----------------------------------------------------------
mkdir -p "${ROOTFS}/etc/sysctl.d"
cat > "${ROOTFS}/etc/sysctl.d/nas.conf" <<'SYSCTL'
vm.swappiness = 10
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
SYSCTL

# --- hdparm ------------------------------------------------------------------
cat > "${ROOTFS}/etc/init.d/hdparm-tune" <<'HDPARM'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          hdparm-tune
# Required-Start:    $local_fs
# Required-Stop:
# Default-Start:     3
# Default-Stop:
# Short-Description: Tune HDD power settings
### END INIT INFO
case "$1" in
  start) hdparm -W1 -S120 /dev/sda 2>/dev/null || true ;;
  stop) ;;
esac
exit 0
HDPARM
chmod 755 "${ROOTFS}/etc/init.d/hdparm-tune"
chroot "$ROOTFS" update-rc.d hdparm-tune defaults 95

# --- ntpdate cron ------------------------------------------------------------
mkdir -p "${ROOTFS}/etc/cron.d"
cat > "${ROOTFS}/etc/cron.d/ntpsync" <<'NTP'
0 */6 * * * root /usr/sbin/ntpdate -s pool.ntp.org
@reboot root sleep 30 && /usr/sbin/ntpdate -s pool.ntp.org
NTP

# --- tune2fs scheduled fsck --------------------------------------------------
# Will be applied to md0 on first boot via rc.local
cat > "${ROOTFS}/etc/rc.local" <<'RCLOCAL'
#!/bin/sh
tune2fs -c 30 -i 90d /dev/md0 2>/dev/null || true
exit 0
RCLOCAL
chmod 755 "${ROOTFS}/etc/rc.local"

# --- FSCKFIX (no serial console to interact) ---------------------------------
sed -i 's/^#*FSCKFIX=.*/FSCKFIX=yes/' "${ROOTFS}/etc/default/rcS" 2>/dev/null || \
    echo "FSCKFIX=yes" >> "${ROOTFS}/etc/default/rcS"

# --- Boot debug logging ------------------------------------------------------
cat > "${ROOTFS}/etc/init.d/bootdebug" <<'BOOTDEBUG'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          bootdebug
# Required-Start:    $all
# Required-Stop:
# Default-Start:     3
# Default-Stop:
# Short-Description: Log boot debug info
### END INIT INFO
case "$1" in
  start)
    {
        echo "=== Boot debug $(date) ==="
        echo "--- uname ---"
        uname -a
        echo "--- ip addr ---"
        ip addr
        echo "--- ip route ---"
        ip route
        echo "--- lsmod ---"
        lsmod
        echo "--- mount ---"
        mount
        echo "--- dmesg tail ---"
        dmesg | tail -30
    } >> /var/log/bootdebug.log
    ;;
  stop) ;;
esac
exit 0
BOOTDEBUG
chmod 755 "${ROOTFS}/etc/init.d/bootdebug"
chroot "$ROOTFS" update-rc.d bootdebug defaults 99

# =============================================================================
step "Step 6: Clean up"
# =============================================================================

info "Cleaning up..."
rm -f "${ROOTFS}/usr/bin/qemu-arm-static"
chroot "$ROOTFS" apt-get clean 2>/dev/null || true
rm -rf "${ROOTFS}/var/lib/apt/lists/"*
rm -rf "${ROOTFS}/tmp/"*
rm -f "${ROOTFS}/var/log/"*.log
rm -f "${ROOTFS}/var/log/"*.gz

cleanup
trap - EXIT

# =============================================================================
step "Step 7: Create rootfs archive"
# =============================================================================

mkdir -p "${REPO_DIR}/rootfs"

ROOTFS_SIZE=$(du -sm "$ROOTFS" | awk '{print $1}')
info "Rootfs size: ${ROOTFS_SIZE} MB"
info "Creating tar.xz archive (this takes several minutes)..."

tar cJf "$OUTPUT" -C "$ROOTFS" .

OUTPUT_SIZE=$(du -sh "$OUTPUT" | awk '{print $1}')
info "Archive created: ${OUTPUT} (${OUTPUT_SIZE})"

echo ""
info "============================================"
info "  BUILD COMPLETE"
info "============================================"
info ""
info "Output: ${OUTPUT}"
info ""
info "To deploy to a disk:"
info "  sudo ./scripts/deploy-prebuilt.sh /dev/sdX"
