#!/usr/bin/env bash
# scripts/flash_esp.sh — Flash a pqriscv .bin image to an ESP32 board.
#
# Usage:
#   ./scripts/flash_esp.sh esp32c3 /dev/ttyUSB0 build/ml-kem-512/test.bin
#   ./scripts/flash_esp.sh esp32c6 /dev/ttyACM0 build/ml-kem-512/bench.bin
#
# Or via Make:
#   make PLATFORM=esp32c3 SCHEME=ml-kem-512 flash-test FLASH_PORT=/dev/ttyUSB0

set -euo pipefail

CHIP="${1:-esp32c3}"
PORT="${2:-/dev/ttyUSB0}"
BIN="${3:-}"

usage() {
    echo "Usage: $0 <chip> <port> <binary.bin>"
    echo ""
    echo "  chip : esp32c3 | esp32c6"
    echo "  port : /dev/ttyUSB0, /dev/ttyACM0, /dev/cu.usbserial-*, COM3, ..."
    echo "  bin  : path to the .bin produced by 'make bin-test'"
    echo ""
    echo "Examples:"
    echo "  $0 esp32c3 /dev/ttyUSB0 build/ml-kem-512/test.bin"
    echo "  $0 esp32c6 /dev/ttyACM0 build/ml-dsa-44/bench.bin"
    exit 1
}

[ -z "$BIN" ] && usage
[ ! -f "$BIN" ] && { echo "Error: $BIN not found"; exit 1; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Chip : $CHIP"
echo "  Port : $PORT"
echo "  Image: $BIN  ($(stat -c%s "$BIN") bytes)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

esptool.py --chip "$CHIP"       \
    --port "$PORT"               \
    --baud 460800                \
    write_flash                  \
    --flash_mode dio             \
    --flash_freq 80m             \
    --flash_size 4MB             \
    0x0 "$BIN"

echo ""
echo "Flash complete.  Now monitor with:"
echo "  ./scripts/monitor.sh $PORT"
echo "  (or: python3 -m serial.tools.miniterm --raw $PORT 115200)"
