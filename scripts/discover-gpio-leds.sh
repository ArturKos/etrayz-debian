#!/bin/bash
# discover-gpio-leds.sh — Probe OX810SE GPIO registers for LED control
# Run as root on the NAS: sudo ./discover-gpio-leds.sh
#
# OX810SE has two GPIO banks (A and B), each with 32 pins.
# LEDs are typically on GPIO A or B, directly memory-mapped.

set -e

# OX810SE GPIO register base addresses
GPIOA_BASE=0x44000000
GPIOB_BASE=0x44100000

# Register offsets within each bank
# 0x00 = input data (read pin state)
# 0x04 = output enable set (write 1 = make output)
# 0x08 = output enable clear (write 1 = make input)
# 0x0C = output enable status (read which are outputs)
# 0x10 = output data (read current output values)
# 0x14 = output set (write 1 = set pin high)
# 0x18 = output clear (write 1 = set pin low)
# 0x1C = debounce enable
# 0x20 = RE interrupt enable
# 0x24 = FE interrupt enable
# 0x28 = interrupt status

# --- Build devmem2 if not available ---
build_devmem2() {
    if command -v devmem2 >/dev/null 2>&1; then
        return 0
    fi

    echo "[*] devmem2 not found, building it..."

    if ! command -v gcc >/dev/null 2>&1; then
        echo "[!] No gcc available. Trying /dev/mem with dd fallback."
        return 1
    fi

    cat > /tmp/devmem2.c << 'CSRC'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>

#define MAP_SIZE 4096UL
#define MAP_MASK (MAP_SIZE - 1)

int main(int argc, char **argv) {
    int fd;
    void *map_base, *virt_addr;
    unsigned long read_result, target;
    unsigned long writeval = 0;
    int do_write = 0;

    if (argc < 2) {
        fprintf(stderr, "Usage: devmem2 address [w value]\n");
        return 1;
    }

    target = strtoul(argv[1], 0, 0);
    if (argc > 2 && argv[2][0] == 'w') {
        do_write = 1;
        writeval = strtoul(argv[3], 0, 0);
    }

    fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) { perror("/dev/mem"); return 1; }

    map_base = mmap(0, MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED,
                    fd, target & ~MAP_MASK);
    if (map_base == MAP_FAILED) { perror("mmap"); return 1; }

    virt_addr = map_base + (target & MAP_MASK);
    read_result = *((unsigned long *) virt_addr);
    printf("0x%08lX: 0x%08lX\n", target, read_result);

    if (do_write) {
        *((unsigned long *) virt_addr) = writeval;
        read_result = *((unsigned long *) virt_addr);
        printf("wrote 0x%08lX, readback: 0x%08lX\n", writeval, read_result);
    }

    munmap(map_base, MAP_SIZE);
    close(fd);
    return 0;
}
CSRC
    gcc -o /tmp/devmem2 /tmp/devmem2.c
    echo "[+] devmem2 built at /tmp/devmem2"
    PATH="/tmp:$PATH"
    return 0
}

# --- Read a register ---
read_reg() {
    local addr=$1
    if command -v devmem2 >/dev/null 2>&1; then
        devmem2 "$addr" 2>/dev/null | grep "^0x" | awk '{print $2}'
    else
        echo "N/A"
    fi
}

echo "========================================"
echo "  EtrayZ OX810SE GPIO/LED Discovery"
echo "  $(date)"
echo "========================================"

build_devmem2
HAS_DEVMEM=$?

if [ $HAS_DEVMEM -ne 0 ]; then
    echo ""
    echo "[!] Cannot read registers without devmem2 or gcc."
    echo "    Install gcc: apt-get install gcc"
    echo "    Or copy a prebuilt devmem2 binary to the NAS."
    echo ""
fi

# --- Read GPIO registers ---
echo ""
echo "=== GPIO BANK A (base $GPIOA_BASE) ==="
echo "  Input data (pin state):  $(read_reg 0x44000000)"
echo "  Output enable status:    $(read_reg 0x4400000C)"
echo "  Output data:             $(read_reg 0x44000010)"
echo "  Debounce enable:         $(read_reg 0x4400001C)"
echo "  RE irq enable:           $(read_reg 0x44000020)"
echo "  FE irq enable:           $(read_reg 0x44000024)"

echo ""
echo "=== GPIO BANK B (base $GPIOB_BASE) ==="
echo "  Input data (pin state):  $(read_reg 0x44100000)"
echo "  Output enable status:    $(read_reg 0x4410000C)"
echo "  Output data:             $(read_reg 0x44100010)"
echo "  Debounce enable:         $(read_reg 0x4410001C)"
echo "  RE irq enable:           $(read_reg 0x44100020)"
echo "  FE irq enable:           $(read_reg 0x44100024)"

# --- Scan init scripts for LED/GPIO clues ---
echo ""
echo "=== INIT SCRIPT SCAN ==="
for f in /etc/init.d/*; do
    [ -f "$f" ] || continue
    matches=$(grep -inE 'led|gpio|devmem|0x4[45][01]|usb.*mount|automount' "$f" 2>/dev/null) || true
    if [ -n "$matches" ]; then
        echo "-- $f:"
        echo "$matches"
    fi
done

# --- Check for Macpower GPIO driver proc/sys entries ---
echo ""
echo "=== CUSTOM GPIO DRIVER ENTRIES ==="
echo "-- /proc:"
ls /proc/ | grep -iE 'gpio|led|mac' 2>/dev/null || echo "  (none)"
echo "-- /sys/devices/platform:"
ls /sys/devices/platform/ 2>/dev/null || echo "  (not available)"
echo "-- /sys/class:"
ls /sys/class/ | grep -iE 'gpio|led|mac' 2>/dev/null || echo "  (none matching)"
echo "-- /sys/bus/platform/drivers:"
ls /sys/bus/platform/drivers/ 2>/dev/null || echo "  (not available)"

# --- Try to find the GPIO kernel module ---
echo ""
echo "=== GPIO KERNEL MODULE ==="
# The "Macpower NT2-GIGA-NAS" GPIO driver may be built-in or a module
lsmod | grep -iE 'gpio|mac' || echo "  (not a loadable module — likely built into kernel)"
# Look for any proc entries created by the driver
find /proc -maxdepth 1 -type f 2>/dev/null | while read f; do
    name=$(basename "$f")
    case "$name" in
        gpio*|led*|GPIO*|LED*) echo "  Found: $f" ;;
    esac
done

# --- LED toggle test (if devmem2 available) ---
if command -v devmem2 >/dev/null 2>&1; then
    echo ""
    echo "=== LED TOGGLE TEST ==="
    echo "This will try toggling each GPIO output bit to find LEDs."
    echo "Watch the front panel LEDs while this runs!"
    echo ""
    echo "Reading current GPIO A output state..."
    ORIG_A=$(read_reg 0x44000010)
    echo "  GPIO A outputs: $ORIG_A"

    echo "Reading current GPIO B output state..."
    ORIG_B=$(read_reg 0x44100010)
    echo "  GPIO B outputs: $ORIG_B"

    # Read which pins are configured as outputs
    OE_A=$(read_reg 0x4400000C)
    OE_B=$(read_reg 0x4410000C)
    echo "  GPIO A output-enabled mask: $OE_A"
    echo "  GPIO B output-enabled mask: $OE_B"

    echo ""
    echo "Will toggle each OUTPUT pin for 1 second. Watch the LEDs!"
    echo "Press Ctrl+C to abort at any time."
    echo ""
    sleep 2

    # Toggle GPIO A output pins one by one
    oe_a_val=$(printf '%d' "$OE_A" 2>/dev/null) || oe_a_val=0
    if [ "$oe_a_val" -ne 0 ] 2>/dev/null; then
        for bit in $(seq 0 31); do
            mask=$((1 << bit))
            if [ $((oe_a_val & mask)) -ne 0 ]; then
                echo -n "  Toggle GPIO A bit $bit (mask 0x$(printf '%08X' $mask))... "
                # Toggle: if currently set, clear it; if clear, set it
                cur=$(printf '%d' "$(read_reg 0x44000010)") || cur=0
                if [ $((cur & mask)) -ne 0 ]; then
                    devmem2 0x44000018 w "0x$(printf '%X' $mask)" >/dev/null 2>&1  # clear
                    sleep 1
                    devmem2 0x44000014 w "0x$(printf '%X' $mask)" >/dev/null 2>&1  # restore
                else
                    devmem2 0x44000014 w "0x$(printf '%X' $mask)" >/dev/null 2>&1  # set
                    sleep 1
                    devmem2 0x44000018 w "0x$(printf '%X' $mask)" >/dev/null 2>&1  # restore
                fi
                echo "done"
            fi
        done
    else
        echo "  No GPIO A pins configured as output (or couldn't read)"
    fi

    # Toggle GPIO B output pins one by one
    oe_b_val=$(printf '%d' "$OE_B" 2>/dev/null) || oe_b_val=0
    if [ "$oe_b_val" -ne 0 ] 2>/dev/null; then
        for bit in $(seq 0 31); do
            mask=$((1 << bit))
            if [ $((oe_b_val & mask)) -ne 0 ]; then
                echo -n "  Toggle GPIO B bit $bit (mask 0x$(printf '%08X' $mask))... "
                cur=$(printf '%d' "$(read_reg 0x44100010)") || cur=0
                if [ $((cur & mask)) -ne 0 ]; then
                    devmem2 0x44100018 w "0x$(printf '%X' $mask)" >/dev/null 2>&1
                    sleep 1
                    devmem2 0x44100014 w "0x$(printf '%X' $mask)" >/dev/null 2>&1
                else
                    devmem2 0x44100014 w "0x$(printf '%X' $mask)" >/dev/null 2>&1
                    sleep 1
                    devmem2 0x44100018 w "0x$(printf '%X' $mask)" >/dev/null 2>&1
                fi
                echo "done"
            fi
        done
    else
        echo "  No GPIO B pins configured as output (or couldn't read)"
    fi

    echo ""
    echo "Toggle test complete. All pins restored to original state."
fi

echo ""
echo "=== USB CONTROL ==="
echo "To disable USB port:  echo 0 > /sys/bus/usb/devices/usb1/authorized"
echo "To enable USB port:   echo 1 > /sys/bus/usb/devices/usb1/authorized"
echo "To reload USB stack:  rmmod ehci_hcd && modprobe ehci_hcd"

echo ""
echo "========================================"
echo "  Done. Share this output for analysis."
echo "========================================"
