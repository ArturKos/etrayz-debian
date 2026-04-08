#!/bin/bash
# build-dropbear.sh — Build Dropbear 2025.89 natively on EtrayZ NAS
#
# Target:  OX810SE ARM926EJ-S 183MHz, kernel 2.6.24.4, GCC 4.4.5
# Result:  /usr/local/sbin/dropbear
#          /usr/local/bin/{dbclient,dropbearkey,dropbearconvert}
#          /etc/init.d/dropbear  (init script)
#          /etc/dropbear/        (host keys generated on first start)
#
# Why Dropbear?  The Squeeze openssh-server uses only legacy SSH algorithms
#               (ssh-rsa with SHA-1) that modern clients reject by default.
#               Dropbear 2025.89 supports ed25519, ECDSA, ChaCha20-Poly1305
#               and connects from any modern OpenSSH client without flags.
#
# CRITICAL FIX: getrandom() and getentropy() require kernel 3.17+.
#               This NAS has kernel 2.6.24.4 — calling them causes SIGILL.
#               Disable them at configure time so Dropbear falls back to
#               reading /dev/urandom instead.
#
# After install, OpenSSH is disabled and Dropbear takes over port 22.
#
# Usage: bash build-dropbear.sh
# Time:  ~10 minutes on 183 MHz ARM

set -e

VERSION="2025.89"
SRC_DIR="/home/sysadmin/dropbear-${VERSION}"
INSTALL_SBIN="/usr/local/sbin"
INSTALL_BIN="/usr/local/bin"
KEYS_DIR="/etc/dropbear"

echo "=== Building Dropbear ${VERSION} natively on EtrayZ ==="
echo ""

# ---- Download ----
if [[ ! -d "$SRC_DIR" ]]; then
    cd /home/sysadmin
    echo "[1/5] Downloading Dropbear ${VERSION}..."
    wget -q "https://matt.ucc.asn.au/dropbear/releases/dropbear-${VERSION}.tar.bz2" \
        -O "dropbear-${VERSION}.tar.bz2"
    tar xf "dropbear-${VERSION}.tar.bz2"
    rm "dropbear-${VERSION}.tar.bz2"
else
    echo "[1/5] Source already present: $SRC_DIR"
fi

cd "$SRC_DIR"

# ---- Configure ----
echo "[2/5] Configuring..."
# ac_cv_func_getrandom=no  — getrandom() added in kernel 3.17; 2.6.24 lacks it
# ac_cv_func_getentropy=no — getentropy() added in glibc 2.25 + kernel 3.17
# Without these, Dropbear calls getrandom() and gets SIGILL on old kernels.
ac_cv_func_getrandom=no \
ac_cv_func_getentropy=no \
./configure \
    --prefix=/usr/local \
    --disable-syslog

# ---- Build ----
echo "[3/5] Building..."
make -j1 PROGRAMS="dropbear dbclient dropbearkey dropbearconvert"

# ---- Install binaries ----
echo "[4/5] Installing binaries..."
install -m 755 dropbear   "$INSTALL_SBIN/dropbear"
install -m 755 dbclient   "$INSTALL_BIN/dbclient"
install -m 755 dropbearkey "$INSTALL_BIN/dropbearkey"
install -m 755 dropbearconvert "$INSTALL_BIN/dropbearconvert"

# ---- Generate host keys (if not already present) ----
mkdir -p "$KEYS_DIR"
if [[ ! -f "$KEYS_DIR/dropbear_ed25519_host_key" ]]; then
    echo "    Generating ed25519 host key..."
    "$INSTALL_BIN/dropbearkey" -t ed25519 -f "$KEYS_DIR/dropbear_ed25519_host_key"
fi
if [[ ! -f "$KEYS_DIR/dropbear_ecdsa_host_key" ]]; then
    echo "    Generating ecdsa host key..."
    "$INSTALL_BIN/dropbearkey" -t ecdsa -f "$KEYS_DIR/dropbear_ecdsa_host_key"
fi
if [[ ! -f "$KEYS_DIR/dropbear_rsa_host_key" ]]; then
    echo "    Generating rsa host key..."
    "$INSTALL_BIN/dropbearkey" -t rsa -f "$KEYS_DIR/dropbear_rsa_host_key"
fi

# ---- Install init script ----
echo "[5/5] Installing init script..."
cat > /etc/init.d/dropbear <<'INITEOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          dropbear
# Required-Start:    $network
# Required-Stop:     $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Dropbear SSH server
### END INIT INFO

DAEMON=/usr/local/sbin/dropbear
KEYS_DIR=/etc/dropbear
PID_FILE=/var/run/dropbear.pid

case "$1" in
  start)
    echo -n "Starting Dropbear SSH server: "
    $DAEMON -d $KEYS_DIR/dropbear_dss_host_key \
            -r $KEYS_DIR/dropbear_rsa_host_key \
            -r $KEYS_DIR/dropbear_ecdsa_host_key \
            -r $KEYS_DIR/dropbear_ed25519_host_key \
            -p 22 -P $PID_FILE -B 2>/dev/null || true
    echo "dropbear"
    ;;
  stop)
    echo -n "Stopping Dropbear SSH server: "
    if [[ -f $PID_FILE ]]; then
        kill $(cat $PID_FILE) 2>/dev/null || true
        rm -f $PID_FILE
    fi
    echo "dropbear"
    ;;
  restart|force-reload)
    $0 stop
    sleep 1
    $0 start
    ;;
  status)
    if [[ -f $PID_FILE ]] && kill -0 $(cat $PID_FILE) 2>/dev/null; then
        echo "Dropbear is running (PID $(cat $PID_FILE))"
    else
        echo "Dropbear is not running"
        exit 1
    fi
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
exit 0
INITEOF
chmod 755 /etc/init.d/dropbear

# ---- Disable OpenSSH, enable Dropbear ----
echo ""
echo "    Disabling OpenSSH..."
if [[ -f /etc/init.d/ssh ]]; then
    update-rc.d ssh disable 2>/dev/null || true
    mv /etc/init.d/ssh /etc/init.d/ssh.disabled
fi
echo "    Enabling Dropbear at boot..."
update-rc.d dropbear defaults

echo ""
echo "    Restarting SSH service (switching from OpenSSH to Dropbear)..."
/etc/init.d/dropbear start

echo ""
echo "=== Done ==="
echo "    Daemon:  $INSTALL_SBIN/dropbear"
echo "    Client:  $INSTALL_BIN/dbclient"
echo "    Keys:    $KEYS_DIR/"
echo ""
echo "    Connect: ssh sysadmin@<NAS_IP>  (no legacy flags needed)"
echo ""
echo "    IMPORTANT: If you are currently connected via SSH, your session"
echo "               remains active. New connections will use Dropbear."
