#!/usr/bin/env bash
# scripts/monitor.sh — Read UART output from ESP32 board after flashing.
#
# Usage:
#   ./scripts/monitor.sh [port] [baud]
#   ./scripts/monitor.sh /dev/ttyUSB0 115200
#
# Requires pyserial:  pip install pyserial
#                 OR: apt install python3-serial
#
# Exit: Ctrl+]  or  Ctrl+C

PORT="${1:-/dev/ttyUSB0}"
BAUD="${2:-115200}"

# miniterm --raw passes through CR/LF unchanged; --eol CR is optional.
# Press Ctrl+] to exit miniterm, or Ctrl+C to kill the script.
echo "Monitoring $PORT @ $BAUD baud  (Ctrl+] to exit)"
python3 -m serial.tools.miniterm --raw "$PORT" "$BAUD"
