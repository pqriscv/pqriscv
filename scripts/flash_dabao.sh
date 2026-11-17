#!/usr/bin/env bash
# scripts/flash_dabao.sh — Copy a pqriscv .uf2 image onto a Dabao board.
#
# The board must be in boot1 (bootloader) mode: it then shows up as a USB
# mass-storage drive labelled BAOCHIP. Boards ship that way ("bootwait"
# enabled); otherwise hold PROG while pressing RESET.
#
# Usage:
#   ./scripts/flash_dabao.sh build/ml-kem-768/test.uf2
#   ./scripts/flash_dabao.sh build/ml-kem-768/test.uf2 /run/media/$USER/BAOCHIP
#
# Or via Make:
#   make PLATFORM=dabao SCHEME=ml-kem-768 flash-test [DABAO_MOUNT=/path]

set -euo pipefail

UF2="${1:-}"
MNT="${2:-}"
LABEL=BAOCHIP

usage() {
    echo "Usage: $0 <image.uf2> [mount point of the $LABEL drive]"
    echo ""
    echo "  image.uf2 : produced by 'make PLATFORM=dabao SCHEME=<s> bin-test'"
    echo "  mount     : optional; found by volume label when omitted"
    exit 1
}

[ -z "$UF2" ] && usage
[ ! -f "$UF2" ] && { echo "Error: $UF2 not found"; exit 1; }

# Locate the drive by label; mount it through udisks if the desktop has not.
if [ -z "$MNT" ]; then
    MNT="$(findmnt -rn -S LABEL=$LABEL -o TARGET 2>/dev/null | head -n1 || true)"
    if [ -z "$MNT" ] && [ -e "/dev/disk/by-label/$LABEL" ] \
            && command -v udisksctl >/dev/null 2>&1; then
        udisksctl mount -b "/dev/disk/by-label/$LABEL" >/dev/null
        MNT="$(findmnt -rn -S LABEL=$LABEL -o TARGET | head -n1 || true)"
    fi
fi

if [ -z "$MNT" ] || [ ! -d "$MNT" ]; then
    echo "Error: no mounted $LABEL drive found."
    echo "  - Is the board in boot1 mode? (hold PROG, press RESET)"
    echo "  - Otherwise mount it and pass the mount point as second argument."
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Drive: $MNT"
echo "  Image: $UF2  ($(stat -c%s "$UF2") bytes)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cp "$UF2" "$MNT/"
sync            # boot1 only sees the image once it has really been written

echo ""
echo "Copy complete.  Now:"
echo "  1. start the monitor on the UART adapter (PB14 → adapter RX):"
echo "       ./scripts/monitor.sh /dev/ttyUSB0 115200"
echo "  2. press PROG on the board (or type 'boot' on boot1's USB console)"
echo "     to verify and run the image."
echo "Or let make do all of it: make PLATFORM=dabao SCHEME=<s> run-bench"
echo "When it finishes the board resets into boot1 by itself (DABAO_RESET_ON_EXIT=1)."
