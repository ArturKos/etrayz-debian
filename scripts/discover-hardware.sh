#!/bin/bash
# discover-hardware.sh — Probe EtrayZ OX810SE for LED, GPIO, and USB control interfaces
# Run as root on the NAS: sudo ./discover-hardware.sh
# Output saved to /tmp/hw-discovery.log

LOG="/tmp/hw-discovery.log"
exec > >(tee "$LOG") 2>&1

echo "========================================"
echo "  EtrayZ Hardware Discovery"
echo "  $(date)"
echo "========================================"

# --- LEDs ---
echo ""
echo "=== LED SUBSYSTEM ==="
if [ -d /sys/class/leds ]; then
    echo "-- /sys/class/leds/ contents:"
    ls -la /sys/class/leds/
    for led in /sys/class/leds/*/; do
        [ -d "$led" ] || continue
        name=$(basename "$led")
        echo "-- LED: $name"
        [ -f "$led/brightness" ] && echo "   brightness: $(cat "$led/brightness")"
        [ -f "$led/max_brightness" ] && echo "   max_brightness: $(cat "$led/max_brightness")"
        [ -f "$led/trigger" ] && echo "   trigger: $(cat "$led/trigger")"
    done
else
    echo "/sys/class/leds/ does not exist"
fi

# --- GPIO ---
echo ""
echo "=== GPIO SUBSYSTEM ==="
if [ -d /sys/class/gpio ]; then
    echo "-- /sys/class/gpio/ contents:"
    ls -la /sys/class/gpio/
    for gp in /sys/class/gpio/gpio*/; do
        [ -d "$gp" ] || continue
        name=$(basename "$gp")
        echo "-- $name"
        [ -f "$gp/direction" ] && echo "   direction: $(cat "$gp/direction")"
        [ -f "$gp/value" ] && echo "   value: $(cat "$gp/value")"
    done
    [ -f /sys/class/gpio/gpiochip0/ngpio ] && echo "-- gpiochip0 ngpio: $(cat /sys/class/gpio/gpiochip0/ngpio)"
    [ -f /sys/class/gpio/gpiochip0/base ] && echo "-- gpiochip0 base: $(cat /sys/class/gpio/gpiochip0/base)"
    [ -f /sys/class/gpio/gpiochip0/label ] && echo "-- gpiochip0 label: $(cat /sys/class/gpio/gpiochip0/label)"
else
    echo "/sys/class/gpio/ does not exist"
fi

# Try exporting GPIOs 0-31 to discover active pins
echo ""
echo "=== GPIO PROBE (export 0-31) ==="
for i in $(seq 0 31); do
    echo "$i" > /sys/class/gpio/export 2>/dev/null
    if [ -d "/sys/class/gpio/gpio${i}" ]; then
        dir=$(cat "/sys/class/gpio/gpio${i}/direction" 2>/dev/null)
        val=$(cat "/sys/class/gpio/gpio${i}/value" 2>/dev/null)
        echo "  gpio${i}: direction=$dir value=$val"
        # Unexport to leave things clean
        echo "$i" > /sys/class/gpio/unexport 2>/dev/null
    fi
done

# --- Kernel config (LED/GPIO support) ---
echo ""
echo "=== KERNEL CONFIG (LED/GPIO) ==="
if [ -f /proc/config.gz ]; then
    zcat /proc/config.gz | grep -iE 'LED|GPIO'
else
    echo "/proc/config.gz not available"
    # Try module list instead
    echo "-- Checking loaded modules:"
    lsmod | grep -iE 'led|gpio' || echo "  (no led/gpio modules loaded)"
    echo "-- Checking available modules:"
    find /lib/modules/ -name '*led*' -o -name '*gpio*' 2>/dev/null || echo "  (none found)"
fi

# --- dmesg LED/GPIO references ---
echo ""
echo "=== DMESG (LED/GPIO/fan) ==="
dmesg | grep -iE 'led|gpio|fan|therm' || echo "(no matches)"

# --- USB ---
echo ""
echo "=== USB SUBSYSTEM ==="
echo "-- lsmod (usb):"
lsmod | grep -iE 'usb|hci|ehci' || echo "  (no usb modules)"

echo ""
echo "-- /proc/bus/usb/devices:"
cat /proc/bus/usb/devices 2>/dev/null || echo "  (not available)"

echo ""
echo "-- USB sysfs tree:"
if [ -d /sys/bus/usb/devices ]; then
    for dev in /sys/bus/usb/devices/*/; do
        [ -d "$dev" ] || continue
        name=$(basename "$dev")
        product=$(cat "$dev/product" 2>/dev/null)
        manufacturer=$(cat "$dev/manufacturer" 2>/dev/null)
        authorized=$(cat "$dev/authorized" 2>/dev/null)
        [ -n "$product" ] && echo "  $name: $manufacturer $product (authorized=$authorized)"
    done
else
    echo "  /sys/bus/usb/devices/ does not exist"
fi

echo ""
echo "-- USB power control:"
for dev in /sys/bus/usb/devices/usb*/; do
    [ -d "$dev" ] || continue
    name=$(basename "$dev")
    [ -f "$dev/authorized" ] && echo "  $name/authorized = $(cat "$dev/authorized")"
    [ -f "$dev/power/level" ] && echo "  $name/power/level = $(cat "$dev/power/level")"
    [ -f "$dev/power/autosuspend" ] && echo "  $name/power/autosuspend = $(cat "$dev/power/autosuspend")"
done

echo ""
echo "-- Block devices (for USB storage detection):"
cat /proc/partitions

echo ""
echo "-- Current mounts:"
mount

# --- /proc/iomem for hardware registers ---
echo ""
echo "=== MEMORY MAP (iomem) ==="
cat /proc/iomem

# --- /proc/ioports ---
echo ""
echo "=== IO PORTS ==="
cat /proc/ioports 2>/dev/null || echo "(not available)"

# --- Original firmware init scripts (LED/GPIO clues) ---
echo ""
echo "=== INIT SCRIPT SCAN (led/gpio/devmem/usb) ==="
for f in /etc/init.d/* /etc/rc.d/init.d/* /etc/rc.d/rc.sysinit 2>/dev/null; do
    [ -f "$f" ] || continue
    matches=$(grep -inE 'led|gpio|devmem|0x[0-9a-fA-F]+.*write|usb.*mount|automount' "$f" 2>/dev/null)
    if [ -n "$matches" ]; then
        echo "-- $f:"
        echo "$matches"
    fi
done

# --- Check for devmem / mmap tools ---
echo ""
echo "=== AVAILABLE TOOLS ==="
for cmd in devmem devmem2 io mmap lsusb usbutils hdparm; do
    path=$(which "$cmd" 2>/dev/null)
    [ -n "$path" ] && echo "  $cmd: $path" || echo "  $cmd: NOT FOUND"
done

# --- thermAndFan (fan/GPIO driver — may share GPIO bank with LEDs) ---
echo ""
echo "=== thermAndFan DRIVER ==="
if [ -d /proc/therm_fan ] || [ -d /sys/class/therm_fan ]; then
    echo "-- /proc/therm_fan:"
    ls /proc/therm_fan/ 2>/dev/null && cat /proc/therm_fan/* 2>/dev/null
    echo "-- /sys/class/therm_fan:"
    ls /sys/class/therm_fan/ 2>/dev/null
else
    echo "  No therm_fan proc/sys entries found"
    echo "-- Checking /proc for anything thermal:"
    ls /proc/ | grep -iE 'therm|fan|temp' || echo "  (none)"
fi

# --- Sysfs platform devices ---
echo ""
echo "=== PLATFORM DEVICES ==="
ls /sys/devices/platform/ 2>/dev/null || echo "(not available)"

# --- Summary ---
echo ""
echo "========================================"
echo "  Discovery complete. Log saved to $LOG"
echo "  Transfer with: scp sysadmin@etrayz:$LOG ."
echo "========================================"
